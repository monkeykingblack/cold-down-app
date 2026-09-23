import Foundation

public actor CoolingCoordinator {
    private let sensorProvider: any SensorProvider
    private let fanReader: any BuiltInFanReader
    private let builtInController: (any BuiltInFanController)?
    private let externalController: (any ExternalCoolerController)?
    private let helperClient: (any PrivilegedFanHelperClient)?
    private let profileStore: any ProfileStore
    private let clock: any ThermalClock
    private let policy: CoolingPolicy
    private var aggregator = SensorAggregator()
    private var preferences: AppPreferences = .defaults
    private var latestSnapshot: CoolingSnapshot = .empty
    private var refreshTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var externalWasConnected = false
    private var started = false
    private var refreshInFlight = false
    private var refreshPending = false
    private var snapshotContinuations: [UUID: AsyncStream<CoolingSnapshot>.Continuation] = [:]

    public init(
        sensorProvider: any SensorProvider,
        fanReader: any BuiltInFanReader,
        builtInController: (any BuiltInFanController)? = nil,
        externalController: (any ExternalCoolerController)? = nil,
        helperClient: (any PrivilegedFanHelperClient)? = nil,
        profileStore: any ProfileStore,
        clock: any ThermalClock = SystemThermalClock(),
        policy: CoolingPolicy = CoolingPolicy()
    ) {
        self.sensorProvider = sensorProvider
        self.fanReader = fanReader
        self.builtInController = builtInController
        self.externalController = externalController
        self.helperClient = helperClient
        self.profileStore = profileStore
        self.clock = clock
        self.policy = policy
    }

    deinit { refreshTask?.cancel() }

    /// - Parameter revertManualProfiles: set after an unclean exit (crash, force quit, power loss). Every Manual
    ///   profile is switched to Auto before any hardware is touched, so a crash never silently re-applies a fixed
    ///   speed on the next launch. Manual targets are kept. Returns true if any profile was reverted.
    @discardableResult
    public func start(revertManualProfiles: Bool = false) async -> Bool {
        guard !started else { return false }
        started = true
        preferences = await profileStore.load()
        var reverted = false
        if revertManualProfiles {
            for (fanID, profile) in preferences.profiles where profile.mode == .manual {
                var automatic = profile
                automatic.mode = .auto
                preferences.profiles[fanID] = automatic
                reverted = true
            }
            if reverted {
                try? await profileStore.save(preferences)
                ThermalLog.safety.notice("Previous session ended unexpectedly; manual fan profiles returned to Auto")
            }
        }
        await builtInController?.restoreAllToAuto()
        await externalController?.connect()
        await refreshNow()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let interval = await self.refreshInterval()
                do { try await self.clock.sleep(for: interval) } catch { return }
                await self.refreshNow()
            }
        }
        if helperClient != nil {
            heartbeatTask = Task { [weak self] in
                while !Task.isCancelled {
                    guard let self else { return }
                    await self.renewHelperLease()
                    do { try await self.clock.sleep(for: 2) } catch { return }
                }
            }
        }
        return reverted
    }

    public func snapshot() -> CoolingSnapshot { latestSnapshot }

    /// Emits the current snapshot immediately and then every newly generated snapshot.
    public func snapshotUpdates() -> AsyncStream<CoolingSnapshot> {
        let (stream, continuation) = AsyncStream.makeStream(of: CoolingSnapshot.self, bufferingPolicy: .bufferingNewest(1))
        let id = UUID()
        snapshotContinuations[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeSnapshotContinuation(id) }
        }
        continuation.yield(latestSnapshot)
        return stream
    }

    /// Refreshes sensors, evaluates policy, and applies hardware side effects.
    /// Concurrent requests are coalesced: while a refresh is running, further requests schedule exactly one
    /// follow-up pass (which sees the newest preferences) instead of interleaving hardware writes.
    public func refreshNow() async {
        if refreshInFlight {
            refreshPending = true
            return
        }
        refreshInFlight = true
        defer { refreshInFlight = false }
        repeat {
            refreshPending = false
            await performRefresh()
        } while refreshPending
    }

    private func removeSnapshotContinuation(_ id: UUID) {
        snapshotContinuations[id] = nil
    }

    private func performRefresh() async {
        let now = await clock.now()
        let summary: SensorSummary
        do {
            let batch = try await sensorProvider.readSensors()
            summary = aggregator.ingest(batch, now: now, refreshInterval: preferences.refreshInterval)
        } catch {
            summary = aggregator.current(now: now, refreshInterval: preferences.refreshInterval)
        }
        var builtIns = (try? await fanReader.listFans()) ?? []
        var helperStatus = await helperClient?.status() ?? .unavailable
        if helperStatus == .healthy, let helperClient {
            do {
                // Merge per fan: a fan the helper can't control keeps its read-only state instead of vanishing.
                let controlled = Dictionary(try await helperClient.listFans().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                builtIns = builtIns.map { controlled[$0.id] ?? $0 }
                    + controlled.values.filter { fan in !builtIns.contains { $0.id == fan.id } }.sorted { $0.id < $1.id }
            } catch {
                helperStatus = .interrupted
            }
        }
        var external = await externalController?.state()
        if preferences.automaticFlydigiReconnect,
           external?.connection == .connected,
           !externalWasConnected {
            await externalController?.connect()
            external = await externalController?.state()
        }
        externalWasConnected = external?.connection == .connected
        let fans = builtIns + (external.map { [$0] } ?? [])
        let decision = policy.evaluate(
            summary: summary,
            fanStates: fans,
            profiles: preferences.profiles,
            helperStatus: helperStatus,
            externalState: external,
            now: now
        )
        await apply(decision)
        latestSnapshot = CoolingSnapshot(
            sensors: summary,
            fans: fans,
            profiles: preferences.profiles,
            helperStatus: helperStatus,
            overallMode: overallMode(for: decision, helper: helperStatus),
            lastDecision: decision,
            generatedAt: now
        )
        publishSnapshot()
    }

    private func publishSnapshot() {
        for continuation in snapshotContinuations.values { continuation.yield(latestSnapshot) }
    }

    /// - Parameter applyNow: false only saves the profile (used while shutting down, when fans are restored anyway).
    public func updateProfile(fanID: String, profile: FanProfile, applyNow: Bool = true) async {
        if let fan = latestSnapshot.fans.first(where: { $0.id == fanID }) {
            preferences.profiles[fanID] = profile.validated(for: fan)
        } else {
            preferences.profiles[fanID] = profile
        }
        try? await profileStore.save(preferences)
        guard applyNow else { return }
        // Show the new profile immediately; applying it to hardware can take seconds (Apple Silicon takeover).
        latestSnapshot = latestSnapshot.withProfiles(preferences.profiles)
        publishSnapshot()
        await refreshNow()
    }

    public func updatePreferences(_ newValue: AppPreferences) async {
        preferences = AppPreferences(
            profiles: newValue.profiles,
            refreshInterval: newValue.refreshInterval,
            showTemperatureInMenuBar: newValue.showTemperatureInMenuBar,
            launchAtLogin: newValue.launchAtLogin,
            automaticFlydigiReconnect: newValue.automaticFlydigiReconnect
        )
        try? await profileStore.save(preferences)
    }

    public func currentPreferences() -> AppPreferences { preferences }

    public func shutdown() async {
        refreshTask?.cancel()
        refreshTask = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil
        await builtInController?.restoreAllToAuto()
        await externalController?.releaseControl()
        started = false
    }

    private func refreshInterval() -> TimeInterval { preferences.refreshInterval }

    private func apply(_ decision: CoolingDecision) async {
        var externalSucceeded = true
        switch decision.externalAction {
        case .none:
            break
        case .stop:
            do { _ = try await externalController?.setTarget(0) }
            catch { externalSucceeded = false }
        case let .target(speed, _):
            do { _ = try await externalController?.setTarget(speed) }
            catch { externalSucceeded = false }
        }

        for (fanID, action) in decision.builtInActions {
            switch action {
            case .automatic:
                try? await builtInController?.setAuto(fanID: fanID)
            case let .target(rpm, requiresACK):
                guard !requiresACK || externalSucceeded else { continue }
                do {
                    _ = try await builtInController?.setTargetRPM(fanID: fanID, rpm: rpm)
                } catch {
                    ThermalLog.policy.error("Setting \(fanID, privacy: .public) to \(rpm, privacy: .public) RPM failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
        if decision.band == .critical || decision.band == .safetyFallback {
            await builtInController?.restoreAllToAuto()
        }
    }

    private func overallMode(for decision: CoolingDecision, helper: HelperStatus) -> OverallControlMode {
        if decision.band == .critical || decision.band == .safetyFallback { return .safetyFallback }
        if helper != .healthy { return .readOnly }
        if preferences.profiles.values.contains(where: { $0.mode == .manual }) { return .manual }
        return .automatic
    }

    private func renewHelperLease() async {
        guard let helperClient else { return }
        do {
            _ = try await helperClient.renewLease()
        } catch {
            ThermalLog.safety.error("Helper heartbeat failed; requesting system Auto mode")
            await builtInController?.restoreAllToAuto()
        }
    }
}

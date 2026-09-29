import Foundation

public actor CoolingCoordinator {
    private let sensorProvider: any SensorProvider
    private let externalController: (any ExternalCoolerController)?
    private let profileStore: any ProfileStore
    private let clock: any ThermalClock
    private let policy: CoolingPolicy
    private var aggregator = SensorAggregator()
    private var preferences: AppPreferences = .defaults
    private var preferencesLoad: Task<AppPreferences, Never>?
    private var preferencesLoaded = false
    private var latestSnapshot: CoolingSnapshot = .empty
    private var refreshTask: Task<Void, Never>?
    private var externalWasConnected = false
    private var started = false
    private var refreshInFlight = false
    private var refreshPending = false
    private var snapshotContinuations: [UUID: AsyncStream<CoolingSnapshot>.Continuation] = [:]

    public init(
        sensorProvider: any SensorProvider,
        externalController: (any ExternalCoolerController)? = nil,
        profileStore: any ProfileStore,
        clock: any ThermalClock = SystemThermalClock(),
        policy: CoolingPolicy = CoolingPolicy()
    ) {
        self.sensorProvider = sensorProvider
        self.externalController = externalController
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
        await loadPreferencesIfNeeded()
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
        var external = await externalController?.state()
        if preferences.automaticFlydigiReconnect,
           external?.connection == .connected,
           !externalWasConnected {
            await externalController?.connect()
            external = await externalController?.state()
        }
        externalWasConnected = external?.connection == .connected
        let fans = external.map { [$0] } ?? []
        let decision = policy.evaluate(
            summary: summary,
            profiles: preferences.profiles,
            externalState: external,
            now: now
        )
        await apply(decision)
        latestSnapshot = CoolingSnapshot(
            sensors: summary,
            fans: fans,
            profiles: preferences.profiles,
            overallMode: overallMode(for: decision, external: external),
            lastDecision: decision,
            generatedAt: now
        )
        publishSnapshot()
    }

    private func publishSnapshot() {
        for continuation in snapshotContinuations.values { continuation.yield(latestSnapshot) }
    }

    /// - Parameter applyNow: false only saves the profile (used while shutting down, when the cooler is released anyway).
    public func updateProfile(fanID: String, profile: FanProfile, applyNow: Bool = true) async {
        await loadPreferencesIfNeeded()
        if let fan = latestSnapshot.fans.first(where: { $0.id == fanID }) {
            preferences.profiles[fanID] = profile.validated(for: fan)
        } else {
            preferences.profiles[fanID] = profile
        }
        try? await profileStore.save(preferences)
        guard applyNow else { return }
        // Show the new profile immediately; the hardware write follows on the refresh.
        latestSnapshot = latestSnapshot.withProfiles(preferences.profiles)
        publishSnapshot()
        await refreshNow()
    }

    /// Updates the app-wide settings. Profiles are owned by `updateProfile`, so the caller's copy of them (which may
    /// predate the stored ones, e.g. a launch-at-login sync before `start`) is ignored rather than written back.
    public func updatePreferences(_ newValue: AppPreferences) async {
        await loadPreferencesIfNeeded()
        preferences = AppPreferences(
            profiles: preferences.profiles,
            refreshInterval: newValue.refreshInterval,
            showTemperatureInMenuBar: newValue.showTemperatureInMenuBar,
            launchAtLogin: newValue.launchAtLogin,
            automaticFlydigiReconnect: newValue.automaticFlydigiReconnect
        )
        try? await profileStore.save(preferences)
    }

    public func currentPreferences() -> AppPreferences { preferences }

    /// Loads the stored preferences once. Every writer awaits this first, so a write that arrives before `start`
    /// never saves the in-memory defaults over what is on disk.
    private func loadPreferencesIfNeeded() async {
        guard !preferencesLoaded else { return }
        let load = preferencesLoad ?? Task { [profileStore] in await profileStore.load() }
        preferencesLoad = load
        let loaded = await load.value
        guard !preferencesLoaded else { return }
        preferences = loaded
        preferencesLoaded = true
    }

    public func shutdown() async {
        refreshTask?.cancel()
        refreshTask = nil
        await externalController?.releaseControl()
        started = false
    }

    private func refreshInterval() -> TimeInterval { preferences.refreshInterval }

    private func apply(_ decision: CoolingDecision) async {
        let speed: Int
        switch decision.externalAction {
        case .none: return
        case .stop: speed = 0
        case let .target(target): speed = target
        }
        do {
            _ = try await externalController?.setTarget(speed)
        } catch {
            ThermalLog.policy.error("Setting the cooler to \(speed, privacy: .public) RPM failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func overallMode(for decision: CoolingDecision, external: FanDeviceState?) -> OverallControlMode {
        if decision.band == .critical || decision.band == .safetyFallback { return .safetyFallback }
        guard let external, external.connection == .connected, external.writeAvailability == .ready else { return .readOnly }
        return preferences.profiles[external.id]?.mode == .manual ? .manual : .automatic
    }
}

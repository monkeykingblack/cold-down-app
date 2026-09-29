import AppKit
import SwiftUI
import Foundation
import ThermalCore
import IntelSMC
import FlydigiHID

enum AppTab: String, CaseIterable, Identifiable {
    case overview = "Overview", fans = "Fans", sensors = "Sensors", settings = "Settings"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .overview: "gauge.with.dots.needle.33percent"
        case .fans: "fan"
        case .sensors: "thermometer.medium"
        case .settings: "gearshape"
        }
    }
}

@MainActor
@Observable
final class AppModel {
    static let mainWindowID = "main"
    /// The main window is not resizable; every page is laid out for this size.
    static let windowSize = CGSize(width: 560, height: 460)

    private(set) var snapshot = CoolingSnapshot.empty
    var preferences = AppPreferences.defaults
    var destination: AppTab = .overview
    var selectedFanID: String?
    private(set) var isReady = false
    /// True after launching from an unclean exit that reverted Manual profiles to Auto (until dismissed).
    var recoveredFromUncleanExit = false
    /// Notices the user dismissed this session (by message identity).
    private(set) var dismissedBanners: Set<String> = []
    private let sessionMarker = SessionMarker()
    /// Recent hottest-temperature and cooler speed samples for dashboard sparklines. The span follows the
    /// refresh interval — 150 samples is about 12 minutes at the default 5 s — and the chart says which.
    private(set) var temperatureHistory: [Double] = []
    private(set) var fanSpeedHistory: [String: [Double]] = [:]
    static let historyLength = 150
    /// Profile edits (mode switches, presets, slider releases) are shown at once but sent to the hardware only
    /// after this much quiet time, and only the final state: quick Auto ↔ Manual flips never start a takeover.
    static let profileCommitDelay: Duration = .milliseconds(500)
    @ObservationIgnored private var pendingProfiles: [String: FanProfile] = [:]
    @ObservationIgnored private var profileCommitTask: Task<Void, Never>?

    static let colorfulMenuBarIconKey = "ColdDown.colorfulMenuBarIcon"
    /// Stored outside `AppPreferences` so older saved preferences keep decoding.
    var colorfulMenuBarIcon = UserDefaults.standard.object(forKey: AppModel.colorfulMenuBarIconKey) as? Bool ?? true {
        didSet { UserDefaults.standard.set(colorfulMenuBarIcon, forKey: Self.colorfulMenuBarIconKey) }
    }
    let launchAtLogin = LaunchAtLoginService()
    /// The real BS3 Pro, for settings outside speed control; nil in mock mode.
    @ObservationIgnored private var flydigi: BS3ProController?
    private(set) var flydigiGearSpeeds: [Int]?
    private(set) var flydigiSettingError: String?
    static let flydigiAccelerationKey = "ColdDown.flydigi.acceleration"
    static let flydigiSleepBehaviorKey = "ColdDown.flydigi.sleepBehavior"
    /// The cooler cannot report these, so the app shows what it last set (nil until the user picks one).
    private(set) var flydigiAcceleration = (UserDefaults.standard.object(forKey: AppModel.flydigiAccelerationKey) as? Int)
        .flatMap { FlydigiAcceleration(rawValue: UInt8($0)) }
    private(set) var flydigiSleepBehavior = (UserDefaults.standard.object(forKey: AppModel.flydigiSleepBehaviorKey) as? Int)
        .flatMap { FlydigiSleepBehavior(rawValue: UInt8($0)) }
    private let coordinator: CoolingCoordinator
    private let usesMockHardware: Bool
    /// Cancelled from `deinit`, which is nonisolated. A `Task` handle is `Sendable` and cancellation is safe
    /// from any thread; nothing else touches this from off the main actor.
    @ObservationIgnored private nonisolated(unsafe) var snapshotTask: Task<Void, Never>?

    init() {
        // Hosted unit tests launch the real app as their host and it is killed, not quit, when they finish, so it
        // must never take over a real cooler: the release command would not be sent and the cooler would be
        // left in realtime mode at the last target.
        if LaunchOption.mockMode || LaunchOption.runningTests {
            let sensors = MockSensorBackend(noSensors: LaunchOption.noSensors)
            let external = MockExternalCoolingBackend(
                disconnected: LaunchOption.coolerDisconnected,
                capabilityLimited: LaunchOption.capabilityLimitedCooler
            )
            coordinator = CoolingCoordinator(
                sensorProvider: sensors, externalController: external,
                // In memory only: mock launches (and the UI tests using them) must start from the same state.
                profileStore: MemoryProfileStore()
            )
            usesMockHardware = true
        } else {
            let sensorProvider = PlatformSensorProvider()
            let transport = FlydigiHIDTransport()
            // Range and protocol audited against THRM's BS-series implementation.
            let external = BS3ProController(transport: transport, capabilities: BS3ProController.auditedCapabilities)
            flydigi = external
            coordinator = CoolingCoordinator(
                sensorProvider: sensorProvider, externalController: external,
                profileStore: UserDefaultsProfileStore()
            )
            usesMockHardware = false
        }
        // `@Observable` tracks the nested services' properties through the views that read them, so the
        // change forwarding this used to need is gone.
    }

    deinit { snapshotTask?.cancel() }

    func start() {
        guard snapshotTask == nil else { return }
        let tracksSession = !usesMockHardware && !LaunchOption.runningTests
        let previousSessionWasUnclean = tracksSession && sessionMarker.begin()
        refreshSystemStatus()
        let coordinator = self.coordinator
        snapshotTask = Task { [weak self] in
            let reverted = await coordinator.start(revertManualProfiles: previousSessionWasUnclean)
            if reverted { self?.recoveredFromUncleanExit = true }
            let loaded = await coordinator.currentPreferences()
            self?.preferences = loaded
            self?.syncLaunchAtLoginPreference()
            for await snapshot in await coordinator.snapshotUpdates() {
                guard let self else { return }
                self.apply(snapshot)
            }
        }
    }

    /// Stops refreshing and hands the cooler back to its own control, waiting at most `timeout`.
    func shutdown(timeout: Duration = .seconds(3)) async {
        snapshotTask?.cancel()
        snapshotTask = nil
        // Keep the user's last choice, without applying it to hardware that is about to be released.
        profileCommitTask?.cancel()
        let pending = pendingProfiles
        pendingProfiles = [:]
        for (fanID, profile) in pending {
            await self.coordinator.updateProfile(fanID: fanID, profile: profile, applyNow: false)
        }
        let coordinator = self.coordinator
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await coordinator.shutdown() }
            group.addTask { try? await Task.sleep(for: timeout) }
            await group.next()
            group.cancelAll()
        }
        if !usesMockHardware, !LaunchOption.runningTests { sessionMarker.end() }
    }

    private func apply(_ refreshed: CoolingSnapshot) {
        if refreshed.generatedAt != snapshot.generatedAt { recordHistory(refreshed) }
        snapshot = withPendingProfiles(refreshed)
        if selectedFanID.map({ id in !refreshed.fans.contains { $0.id == id } }) ?? true {
            selectedFanID = refreshed.fans.first?.id
        }
        if !isReady { isReady = true }
    }

    private func recordHistory(_ snapshot: CoolingSnapshot) {
        if let hottest = snapshot.sensors.hottestReading?.valueCelsius {
            temperatureHistory = Array((temperatureHistory + [hottest]).suffix(Self.historyLength))
        }
        var speeds = fanSpeedHistory
        for fan in snapshot.fans {
            guard let speed = fan.currentSpeed, fan.connection == .connected else { continue }
            speeds[fan.id] = Array(((speeds[fan.id] ?? []) + [Double(speed)]).suffix(Self.historyLength))
        }
        fanSpeedHistory = speeds
    }

    /// Re-reads SMAppService state; call on activation rather than on every refresh (each read is an IPC).
    func refreshSystemStatus() {
        launchAtLogin.refresh()
        syncLaunchAtLoginPreference()
    }

    func dismiss(_ banner: StatusBanner) {
        dismissedBanners.insert(banner.id)
        if banner.id == "recovery" { recoveredFromUncleanExit = false }
    }

    func openFan(_ id: String) {
        selectedFanID = id
        destination = .fans
    }

    /// The saved profile, or the same default the policy follows until one is saved.
    func profile(for fan: FanDeviceState) -> FanProfile {
        snapshot.profiles[fan.id] ?? FanProfile.suggested(for: fan, summary: snapshot.sensors)
    }

    func updateProfile(fanID: String, profile: FanProfile) {
        pendingProfiles[fanID] = profile
        snapshot = withPendingProfiles(snapshot)
        profileCommitTask?.cancel()
        profileCommitTask = Task { [weak self] in
            guard (try? await Task.sleep(for: Self.profileCommitDelay)) != nil else { return }
            await self?.commitPendingProfiles()
        }
    }

    private func commitPendingProfiles() async {
        let pending = pendingProfiles
        pendingProfiles = [:]
        profileCommitTask = nil
        for (fanID, profile) in pending {
            await coordinator.updateProfile(fanID: fanID, profile: profile)
        }
    }

    /// Overlays edits that are still inside the debounce window so a refresh never flips the UI back.
    private func withPendingProfiles(_ snapshot: CoolingSnapshot) -> CoolingSnapshot {
        guard !pendingProfiles.isEmpty else { return snapshot }
        return snapshot.withProfiles(snapshot.profiles.merging(pendingProfiles) { _, pending in pending })
    }

    func updatePreferences(_ mutate: (inout AppPreferences) -> Void) {
        mutate(&preferences)
        let value = preferences
        let coordinator = self.coordinator
        Task { await coordinator.updatePreferences(value) }
    }

    var supportsFlydigiSettings: Bool { flydigi != nil }

    var flydigiConnected: Bool {
        flydigi != nil && snapshot.fans.contains { $0.connection == .connected }
    }

    func refreshFlydigiGearSpeeds() async {
        guard let flydigi, flydigiConnected else { flydigiGearSpeeds = nil; return }
        flydigiGearSpeeds = try? await flydigi.gearSpeeds()
    }

    func setFlydigiAcceleration(_ level: FlydigiAcceleration) {
        applyFlydigiSetting { try await $0.setAcceleration(level) } onSuccess: { model in
            model.flydigiAcceleration = level
            UserDefaults.standard.set(Int(level.rawValue), forKey: Self.flydigiAccelerationKey)
        }
    }

    func setFlydigiSleepBehavior(_ behavior: FlydigiSleepBehavior) {
        applyFlydigiSetting { try await $0.setSleepBehavior(behavior) } onSuccess: { model in
            model.flydigiSleepBehavior = behavior
            UserDefaults.standard.set(Int(behavior.rawValue), forKey: Self.flydigiSleepBehaviorKey)
        }
    }

    /// Sent only when the user picks a value: these settings live in the cooler, so nothing is replayed on connect.
    private func applyFlydigiSetting(
        _ send: @escaping @Sendable (BS3ProController) async throws -> Void,
        onSuccess: @escaping @MainActor (AppModel) -> Void
    ) {
        guard let flydigi else { return }
        Task { [weak self] in
            do {
                try await send(flydigi)
                guard let self else { return }
                onSuccess(self)
                self.flydigiSettingError = nil
            } catch {
                self?.flydigiSettingError = "The cooler did not accept the setting. Check that it is connected and try again."
            }
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLogin.setEnabled(enabled)
        syncLaunchAtLoginPreference()
    }

    func prepareToShowMainWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// The stored preference mirrors the real login-item state, which the user can also change in System Settings.
    private func syncLaunchAtLoginPreference() {
        guard preferences.launchAtLogin != launchAtLogin.enabled else { return }
        updatePreferences { $0.launchAtLogin = launchAtLogin.enabled }
    }
}

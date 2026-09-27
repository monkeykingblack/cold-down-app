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

/// One user-facing helper state, derived from both SMAppService registration and the live XPC lease.
enum HelperDisplayStatus: Equatable {
    case available, requiresApproval, notInstalled, notResponding, unavailable

    /// Short status in the sidebar, phrased as what the user can do rather than which component is running.
    var sidebarText: String {
        switch self {
        case .available: "Fan control on"
        case .requiresApproval: "Fan control needs approval"
        case .notInstalled: "Monitoring only"
        case .notResponding: "Fan control unavailable"
        case .unavailable: "Monitoring only"
        }
    }

    /// One-line explanation shown on hover and in Settings.
    var explanation: String {
        switch self {
        case .available: "Cold Down can set built-in fan speeds. Temperatures are monitored either way."
        case .requiresApproval: "Turn on Cold Down in System Settings › General › Login Items to control built-in fans."
        case .notInstalled: "Temperatures and fan speeds are shown. Install fan control in Settings to change built-in fan speeds."
        case .notResponding: "The fan control service is installed but not answering. Reinstall it in Settings."
        case .unavailable: "Temperatures and fan speeds are shown, but built-in fans can't be controlled on this setup."
        }
    }

    var settingsText: String {
        switch self {
        case .available: "On"
        case .requiresApproval: "Needs approval"
        case .notInstalled: "Not installed"
        case .notResponding: "Not responding"
        case .unavailable: "Unavailable"
        }
    }

    var symbol: String {
        switch self {
        case .available: "fan.fill"
        case .requiresApproval: "exclamationmark.circle"
        case .notResponding: "exclamationmark.triangle"
        case .notInstalled, .unavailable: "eye"
        }
    }

    var tint: Color {
        switch self {
        case .available: .green
        case .requiresApproval, .notResponding: .orange
        case .notInstalled, .unavailable: .secondary
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
    /// Recent hottest-temperature and per-fan speed samples for dashboard sparklines (about 5 minutes at 2 s).
    private(set) var temperatureHistory: [Double] = []
    private(set) var fanSpeedHistory: [String: [Double]] = [:]
    static let historyLength = 150
    /// Profile edits (mode switches, presets, slider releases) are shown at once but sent to the hardware only
    /// after this much quiet time, and only the final state: quick Auto ↔ Manual flips never start a takeover.
    static let profileCommitDelay: Duration = .milliseconds(500)
    @ObservationIgnored private var pendingProfiles: [String: FanProfile] = [:]
    @ObservationIgnored private var profileCommitTask: Task<Void, Never>?

    let helperRegistration = HelperRegistrationService()
    static let colorfulMenuBarIconKey = "ColdDown.colorfulMenuBarIcon"
    /// Stored outside `AppPreferences` so older saved preferences keep decoding.
    var colorfulMenuBarIcon = UserDefaults.standard.object(forKey: AppModel.colorfulMenuBarIconKey) as? Bool ?? true {
        didSet { UserDefaults.standard.set(colorfulMenuBarIcon, forKey: Self.colorfulMenuBarIconKey) }
    }
    let launchAtLogin = LaunchAtLoginService()
    private let coordinator: CoolingCoordinator
    private let usesMockHelper: Bool
    /// Cancelled from `deinit`, which is nonisolated. A `Task` handle is `Sendable` and cancellation is safe
    /// from any thread; nothing else touches this from off the main actor.
    @ObservationIgnored private nonisolated(unsafe) var snapshotTask: Task<Void, Never>?

    init() {
        if LaunchOption.mockMode {
            let monitoring = MockMonitoringBackend(
                noSensors: LaunchOption.noSensors,
                helperAvailable: !LaunchOption.helperUnavailable,
                twoFans: LaunchOption.twoFans
            )
            let names = LaunchOption.twoFans ? ["Left fan", "Right fan"] : ["Mac fan"]
            let builtInStates = names.enumerated().map { index, name in
                FanDeviceState(
                    id: "builtin:\(index)", name: name, kind: .builtIn, connection: .connected,
                    currentSpeed: 2_200 + index * 180, reportedMode: .auto,
                    capabilities: SpeedCapabilities(minimum: 1_200, maximum: 5_500 + index * 300, step: 10, provenance: .deviceVerified),
                    writeAvailability: LaunchOption.helperUnavailable ? .helperMissing : .ready
                )
            }
            let builtIn = MockBuiltInCoolingBackend(fans: builtInStates)
            let external = MockExternalCoolingBackend(
                disconnected: LaunchOption.coolerDisconnected,
                capabilityLimited: LaunchOption.capabilityLimitedCooler
            )
            coordinator = CoolingCoordinator(
                sensorProvider: monitoring, fanReader: monitoring,
                builtInController: LaunchOption.helperUnavailable ? nil : builtIn,
                externalController: external,
                helperClient: LaunchOption.helperUnavailable ? nil : builtIn,
                // In memory only: mock launches (and the UI tests using them) must start from the same state.
                profileStore: MemoryProfileStore()
            )
            usesMockHelper = true
        } else {
            let sensorProvider = PlatformSensorProvider()
            let fanReader = AppleSMCFanReader()
            let helper = XPCPrivilegedHelperClient(disabled: LaunchOption.helperUnavailable)
            let transport = FlydigiHIDTransport()
            // Range and protocol audited against THRM's BS-series implementation.
            let external = BS3ProController(transport: transport, capabilities: BS3ProController.auditedCapabilities)
            coordinator = CoolingCoordinator(
                sensorProvider: sensorProvider, fanReader: fanReader,
                builtInController: helper, externalController: external, helperClient: helper,
                profileStore: UserDefaultsProfileStore()
            )
            usesMockHelper = false
        }
        // `@Observable` tracks the nested services' properties through the views that read them, so the
        // change forwarding this used to need is gone.
    }

    deinit { snapshotTask?.cancel() }

    var helperDisplayStatus: HelperDisplayStatus {
        if usesMockHelper {
            return snapshot.helperStatus == .healthy ? .available : .unavailable
        }
        switch helperRegistration.status {
        case .requiresApproval: return .requiresApproval
        case .notRegistered: return .notInstalled
        case .unavailable, .interrupted: return .unavailable
        case .healthy: return snapshot.helperStatus == .healthy ? .available : .notResponding
        }
    }

    func start() {
        guard snapshotTask == nil else { return }
        let tracksSession = !usesMockHelper && !LaunchOption.runningTests
        let previousSessionWasUnclean = tracksSession && sessionMarker.begin()
        refreshSystemStatus()
        if !usesMockHelper, !LaunchOption.helperUnavailable, !LaunchOption.runningTests {
            let registration = helperRegistration
            Task { await registration.registerOnFirstLaunchIfNeeded() }
        }
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

    /// Stops refreshing and returns built-in fans to system control, waiting at most `timeout`.
    func shutdown(timeout: Duration = .seconds(3)) async {
        snapshotTask?.cancel()
        snapshotTask = nil
        // Keep the user's last choice, without applying it to hardware that is about to be restored.
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
        if !usesMockHelper, !LaunchOption.runningTests { sessionMarker.end() }
    }

    private func apply(_ refreshed: CoolingSnapshot) {
        let helperStatusChanged = refreshed.helperStatus != snapshot.helperStatus
        if refreshed.generatedAt != snapshot.generatedAt { recordHistory(refreshed) }
        snapshot = withPendingProfiles(refreshed)
        if selectedFanID.map({ id in !refreshed.fans.contains { $0.id == id } }) ?? true {
            selectedFanID = refreshed.fans.first?.id
        }
        if !isReady { isReady = true }
        // While waiting for approval, keep checking so fan control turns on as soon as the user approves,
        // even if Cold Down is only in the menu bar and never becomes active again.
        if helperStatusChanged || helperRegistration.status == .requiresApproval { helperRegistration.refresh() }
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
        helperRegistration.refresh()
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

    func profile(for fan: FanDeviceState) -> FanProfile {
        snapshot.profiles[fan.id] ?? FanProfile(
            selectedSensor: snapshot.sensors.calculated[.cpuAverage] == nil
                ? .calculated(.hottest) : .calculated(.cpuAverage),
            manualTarget: fan.currentSpeed ?? fan.capabilities?.minimum ?? 1
        ).validated(for: fan)
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

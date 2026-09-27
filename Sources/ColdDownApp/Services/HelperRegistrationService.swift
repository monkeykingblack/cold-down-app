import Foundation
import ServiceManagement
import ThermalCore

#if !compiler(>=6.2)
// The macOS 26 SDK declares `SMAppService` as `Sendable`; earlier SDKs do not, even though the class is
// thread-safe, so `await service.unregister()` trips Swift 6's sending check when built with Xcode 16.
extension SMAppService: @retroactive @unchecked Sendable {}
#endif

@MainActor
@Observable
final class HelperRegistrationService {
    static let autoRegistrationAttemptedKey = "ColdDown.helperAutoRegistrationAttempted"

    private(set) var status: HelperStatus = .notRegistered
    private(set) var errorMessage: String?
    private let service = SMAppService.daemon(plistName: "ColdDownHelper.plist")
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    /// Registers the helper once, on first launch, so the user only has to approve it in System Settings.
    /// macOS always requires that approval for a launch daemon; this just saves the user from finding "Install…".
    /// It never retries automatically: if the user later removes or disables the helper, that choice is respected
    /// and re-registration is left to the explicit Install button.
    func registerOnFirstLaunchIfNeeded() async {
        let attempted = defaults.bool(forKey: Self.autoRegistrationAttemptedKey)
        guard Self.shouldAutoRegister(
            serviceStatus: service.status, alreadyAttempted: attempted, helperBundled: Self.helperIsBundled
        ) else { return }
        defaults.set(true, forKey: Self.autoRegistrationAttemptedKey)
        ThermalLog.xpc.info("Registering fan helper on first launch")
        await register()
    }

    /// A daemon that has never been registered usually reports `.notFound` rather than `.notRegistered`,
    /// so both qualify, provided the helper and its launchd plist are really inside the app bundle.
    nonisolated static func shouldAutoRegister(
        serviceStatus: SMAppService.Status, alreadyAttempted: Bool, helperBundled: Bool
    ) -> Bool {
        guard !alreadyAttempted, helperBundled else { return false }
        return serviceStatus == .notRegistered || serviceStatus == .notFound
    }

    nonisolated static var helperIsBundled: Bool {
        let contents = Bundle.main.bundleURL.appendingPathComponent("Contents")
        let files = ["Library/LaunchDaemons/ColdDownHelper.plist", "Library/HelperTools/ColdDownHelper"]
        return files.allSatisfy { FileManager.default.fileExists(atPath: contents.appendingPathComponent($0).path) }
    }

    func refresh() {
        let refreshedStatus: HelperStatus
        switch service.status {
        case .enabled: refreshedStatus = .healthy
        case .requiresApproval: refreshedStatus = .requiresApproval
        // Never-registered daemons commonly report .notFound; only a missing helper is truly unavailable.
        case .notFound: refreshedStatus = Self.helperIsBundled ? .notRegistered : .unavailable
        default: refreshedStatus = .notRegistered
        }
        if status != refreshedStatus {
            status = refreshedStatus
        }
        if refreshedStatus == .healthy, errorMessage != nil {
            errorMessage = nil
        }
    }

    func register() async {
        errorMessage = nil
        do {
            try service.register()
        } catch {
            report(error, action: "registration")
            status = .unavailable
        }
        refresh()
    }

    /// Recovers a registered helper that no longer answers (e.g. after an app update moved its binary).
    func reinstall() async {
        errorMessage = nil
        do {
            try await service.unregister()
        } catch {
            report(error, action: "unregistration")
        }
        await register()
    }

    func openApprovalSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private func report(_ error: Error, action: String) {
        let failure = error as NSError
        errorMessage = "\(failure.localizedDescription) (\(failure.domain) \(failure.code))"
        ThermalLog.xpc.error("Helper \(action, privacy: .public) failed: \(failure.localizedDescription, privacy: .public)")
    }
}

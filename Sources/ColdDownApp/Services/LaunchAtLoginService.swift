import Foundation
import ServiceManagement

@MainActor
@Observable
final class LaunchAtLoginService {
    private(set) var enabled = SMAppService.mainApp.status == .enabled
    private(set) var requiresApproval = SMAppService.mainApp.status == .requiresApproval
    private(set) var errorMessage: String?

    func setEnabled(_ value: Bool) {
        errorMessage = nil
        do {
            if value { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            errorMessage = error.localizedDescription
        }
        refresh()
    }

    func refresh() {
        let status = SMAppService.mainApp.status
        if enabled != (status == .enabled) { enabled = status == .enabled }
        if requiresApproval != (status == .requiresApproval) { requiresApproval = status == .requiresApproval }
    }
}

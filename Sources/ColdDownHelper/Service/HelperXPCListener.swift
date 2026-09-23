import Foundation
import ColdDownShared

final class HelperXPCListenerDelegate: NSObject, NSXPCListenerDelegate, @unchecked Sendable {
    private let controller: HelperSMCFanController
    private let lease = HelperLeaseManager()
    private let acceptsConnections: Bool
    private let lock = NSLock()
    private var activeConnection: NSXPCConnection?

    init(controller: HelperSMCFanController, acceptsConnections: Bool) {
        self.controller = controller
        self.acceptsConnections = acceptsConnections
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard acceptsConnections else { return false }
        let service = PrivilegedFanHelperService(controller: controller, lease: lease)
        connection.exportedInterface = HelperXPCInterface.make()
        connection.exportedObject = service
        connection.interruptionHandler = { [service] in Task { await service.disconnect() } }
        connection.invalidationHandler = { [service] in Task { await service.disconnect() } }

        lock.lock()
        let previous = activeConnection
        activeConnection = connection
        lock.unlock()
        // Single owner: the replaced client loses all access, not just the lease.
        previous?.invalidate()

        connection.resume()
        return true
    }
}

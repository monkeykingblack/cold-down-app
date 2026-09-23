import Foundation
import ColdDownShared
import ThermalCore

#if DEBUG
let allowsUnpinnedTeam = true
#else
let allowsUnpinnedTeam = false
#endif

let listener = NSXPCListener(machServiceName: thermalHelperMachService)
let clientRequirement = HelperClientRequirement.make(
    identifier: thermalExpectedClientIdentifier,
    teamIdentifier: thermalExpectedClientTeamIdentifier,
    allowUnpinnedTeam: allowsUnpinnedTeam
)
if let clientRequirement {
    listener.setConnectionCodeSigningRequirement(clientRequirement)
} else {
    ThermalLog.xpc.fault("No valid client team identifier is configured; refusing all connections")
}

let controller = HelperSMCFanController()
// Fans may still be forced from a previous helper instance that crashed; start from system control.
Task { _ = await controller.restoreAll() }
let lifecycle = HelperLifecycleMonitor(controller: controller)
let delegate = HelperXPCListenerDelegate(controller: controller, acceptsConnections: clientRequirement != nil)
listener.delegate = delegate
listener.activate()
withExtendedLifetime(lifecycle) { RunLoop.current.run() }

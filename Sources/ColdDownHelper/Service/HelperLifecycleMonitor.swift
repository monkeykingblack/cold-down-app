import Foundation
import IOKit
import IOKit.pwr_mgt
import ThermalCore

/// Restores system fan control around sleep/wake and on termination.
/// Uses IOKit root-domain power notifications, which (unlike NSWorkspace) are delivered to launch daemons.
final class HelperLifecycleMonitor: @unchecked Sendable {
    // iokit_common_msg() values; the C macros are not imported into Swift.
    private static let canSystemSleep: natural_t = 0xE000_0270
    private static let systemWillSleep: natural_t = 0xE000_0280
    private static let systemHasPoweredOn: natural_t = 0xE000_0300

    private let controller: HelperSMCFanController
    private var rootPort: io_connect_t = 0
    private var notificationPort: IONotificationPortRef?
    private var notifier: io_object_t = 0
    private var signalSource: DispatchSourceSignal?

    init(controller: HelperSMCFanController) {
        self.controller = controller
        registerForSystemPower()
        registerForTermination()
    }

    deinit {
        signalSource?.cancel()
        if notifier != 0 { IODeregisterForSystemPower(&notifier) }
        if let notificationPort { IONotificationPortDestroy(notificationPort) }
        if rootPort != 0 { IOServiceClose(rootPort) }
    }

    private func registerForSystemPower() {
        var port: IONotificationPortRef?
        let context = Unmanaged.passUnretained(self).toOpaque()
        rootPort = IORegisterForSystemPower(context, &port, { refCon, _, messageType, argument in
            guard let refCon else { return }
            Unmanaged<HelperLifecycleMonitor>.fromOpaque(refCon).takeUnretainedValue()
                .handlePowerMessage(messageType, notificationID: Int(bitPattern: argument))
        }, &notifier)
        guard rootPort != 0, let port else {
            ThermalLog.safety.error("Could not register for system power notifications")
            return
        }
        notificationPort = port
        CFRunLoopAddSource(
            CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(port).takeUnretainedValue(), .commonModes
        )
    }

    private func handlePowerMessage(_ messageType: natural_t, notificationID: Int) {
        let rootPort = self.rootPort
        switch messageType {
        case Self.canSystemSleep:
            IOAllowPowerChange(rootPort, notificationID)
        case Self.systemWillSleep:
            // Acknowledge only after fans are back under system control (the kernel waits up to 30 s).
            Task { [controller] in
                _ = await controller.restoreAll()
                IOAllowPowerChange(rootPort, notificationID)
            }
        case Self.systemHasPoweredOn:
            Task { [controller] in _ = await controller.restoreAll() }
        default:
            break
        }
    }

    private func registerForTermination() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { [controller] in
            Task { _ = await controller.restoreAll(); exit(EXIT_SUCCESS) }
        }
        source.resume(); signalSource = source
    }
}

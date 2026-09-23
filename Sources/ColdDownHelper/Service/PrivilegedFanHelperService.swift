import Foundation
import ThermalCore
import ColdDownShared

private final class UncheckedSendableBox<Value>: @unchecked Sendable {
    let value: Value

    init(_ value: Value) {
        self.value = value
    }
}

final class PrivilegedFanHelperService: NSObject, PrivilegedFanHelperXPCProtocol, @unchecked Sendable {
    private let controller: HelperSMCFanController
    private let lease: HelperLeaseManager
    private let owner = UUID()
    private var startupTask: Task<Void, Never>?
    private var watchdogTask: Task<Void, Never>?

    init(controller: HelperSMCFanController, lease: HelperLeaseManager, watchdogInterval: Duration = .seconds(1)) {
        self.controller = controller; self.lease = lease
        super.init()
        let startup = Task { [lease, controller, owner] in
            _ = await lease.begin(owner: owner)
            _ = await controller.restoreAll()
        }
        startupTask = startup
        watchdogTask = Task { [lease, controller, owner, startup] in
            await startup.value
            while !Task.isCancelled {
                do { try await Task.sleep(for: watchdogInterval) } catch { return }
                guard await lease.needsRestore(owner: owner) else { continue }
                ThermalLog.safety.error("Helper lease expired; restoring system Auto mode")
                // Only give up the lease once restoration is confirmed; otherwise retry on the next tick.
                if await controller.restoreAll() { await lease.clear(owner: owner) }
            }
        }
    }

    deinit {
        startupTask?.cancel()
        watchdogTask?.cancel()
    }

    func listFans(reply: @escaping ([HelperFanRecord]?, NSError?) -> Void) {
        let replyBox = UncheckedSendableBox(reply)
        let startup = startupTask
        Task {
            await startup?.value
            do { replyBox.value(try await controller.listFans(), nil) }
            catch { await invalidState(); replyBox.value(nil, error as NSError) }
        }
    }

    func setFanAuto(fanID: String, reply: @escaping (NSError?) -> Void) {
        let replyBox = UncheckedSendableBox(reply)
        let startup = startupTask
        Task {
            await startup?.value
            do { try await controller.setAuto(fanID: fanID); replyBox.value(nil) }
            catch { await invalidState(); replyBox.value(error as NSError) }
        }
    }

    func setFanTargetRPM(fanID: String, rpm: Int, reply: @escaping (Int, NSError?) -> Void) {
        let replyBox = UncheckedSendableBox(reply)
        let startup = startupTask
        Task {
            await startup?.value
            guard await lease.validate(owner: owner), rpm > 0 else {
                await invalidState(); replyBox.value(0, ThermalControlError.unauthorized as NSError); return
            }
            do { replyBox.value(try await controller.setTarget(fanID: fanID, requestedRPM: rpm), nil) }
            catch { await invalidState(); replyBox.value(0, error as NSError) }
        }
    }

    func restoreAllFansToAuto(reply: @escaping (Bool, NSError?) -> Void) {
        let replyBox = UncheckedSendableBox(reply)
        let startup = startupTask
        Task { await startup?.value; replyBox.value(await controller.restoreAll(), nil) }
    }

    func renewLease(reply: @escaping (Date?, NSError?) -> Void) {
        let replyBox = UncheckedSendableBox(reply)
        let startup = startupTask
        Task {
            await startup?.value
            do { replyBox.value(try await lease.renew(owner: owner), nil) }
            catch { await invalidState(); replyBox.value(nil, error as NSError) }
        }
    }

    func disconnect() async {
        watchdogTask?.cancel()
        await startupTask?.value
        // A replaced session must not undo the targets of the session that took over.
        if await lease.release(owner: owner) {
            _ = await controller.restoreAll()
        }
    }

    private func invalidState() async {
        ThermalLog.safety.error("Helper entered fail-safe restoration")
        if await controller.restoreAll() {
            await lease.clear(owner: owner)
        } else {
            await lease.expire(owner: owner)
        }
    }
}

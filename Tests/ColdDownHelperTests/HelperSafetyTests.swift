import XCTest
import ThermalCore
@testable import ColdDownHelperCore

private actor FakeFanReader: BuiltInFanReader {
    var fans: [FanDeviceState]
    var failure: ThermalControlError?
    init(_ fans: [FanDeviceState]) { self.fans = fans }
    func listFans() throws -> [FanDeviceState] {
        if let failure { throw failure }
        return fans
    }
    func setFailure(_ error: ThermalControlError?) { failure = error }
}

private final class FakeSMCWriter: HelperSMCWriting, @unchecked Sendable {
    private let lock = NSLock()
    private var restoreFailuresRemaining: Int
    private(set) var restoreAttempts = 0
    private(set) var successfulRestores = 0
    private(set) var targets: [(Int, Int)] = []

    init(restoreFailures: Int = 0) { restoreFailuresRemaining = restoreFailures }

    func setTarget(index: Int, rpm: Int) throws { lock.withLock { targets.append((index, rpm)) } }
    func setAutomatic(index: Int) throws {}
    func restoreAllAutomatic() throws {
        try lock.withLock {
            restoreAttempts += 1
            if restoreFailuresRemaining > 0 {
                restoreFailuresRemaining -= 1
                throw ThermalControlError.unavailable("SMC busy")
            }
            successfulRestores += 1
        }
    }
    var counts: (attempts: Int, successes: Int) { lock.withLock { (restoreAttempts, successfulRestores) } }
    var recordedTargets: [(Int, Int)] { lock.withLock { targets } }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T { lock(); defer { unlock() }; return try body() }
}

private func fan(_ index: Int = 0, minimum: Int = 1_200) -> FanDeviceState {
    FanDeviceState(
        id: "builtin:\(index)", name: "Mac fan", kind: .builtIn, connection: .connected, currentSpeed: 2_000,
        capabilities: SpeedCapabilities(minimum: minimum, maximum: 5_000, provenance: .deviceVerified),
        writeAvailability: .helperMissing
    )
}

private func eventually(timeout: TimeInterval = 2, _ condition: () async -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return await condition()
}

final class HelperSafetyTests: XCTestCase {
    func testRestoreDoesNotDependOnReadableFanLimits() async {
        let reader = FakeFanReader([fan(minimum: 0)])
        await reader.setFailure(.invalidData("FNum unreadable"))
        let writer = FakeSMCWriter()
        let controller = HelperSMCFanController(reader: reader, writer: writer)
        let restored = await controller.restoreAll()
        XCTAssertTrue(restored)
        XCTAssertEqual(writer.counts.successes, 1)
    }

    func testTargetsAreClampedAndNeverStopTheFan() async throws {
        let writer = FakeSMCWriter()
        let controller = HelperSMCFanController(reader: FakeFanReader([fan()]), writer: writer)
        let applied = try await controller.setTarget(fanID: "builtin:0", requestedRPM: 1)
        XCTAssertEqual(applied, 1_200)
        XCTAssertEqual(writer.recordedTargets.map(\.1), [1_200])
    }

    func testWatchdogRetriesRestorationUntilItSucceeds() async {
        let writer = FakeSMCWriter(restoreFailures: 3)  // startup + two watchdog ticks fail
        let controller = HelperSMCFanController(reader: FakeFanReader([fan()]), writer: writer)
        let lease = HelperLeaseManager(duration: 0.05)
        let service = PrivilegedFanHelperService(controller: controller, lease: lease, watchdogInterval: .milliseconds(10))
        let recovered = await eventually { writer.counts.successes >= 1 }
        XCTAssertTrue(recovered, "Watchdog must keep retrying a failed restoration")
        XCTAssertGreaterThanOrEqual(writer.counts.attempts, 4)
        await service.disconnect()
    }

    func testSessionReacquiresLeaseAfterFailSafeInsteadOfReconnecting() async throws {
        let lease = HelperLeaseManager(duration: 8)
        let owner = UUID()
        _ = await lease.begin(owner: owner)
        await lease.clear(owner: owner)  // what a fail-safe restoration does
        _ = try await lease.renew(owner: owner)
        let valid = await lease.validate(owner: owner)
        XCTAssertTrue(valid)
    }

    func testReplacedSessionDoesNotRestoreOverNewOwner() async {
        let lease = HelperLeaseManager(duration: 8)
        let old = UUID(), new = UUID()
        _ = await lease.begin(owner: old)
        _ = await lease.begin(owner: new)
        let oldMustRestore = await lease.release(owner: old)
        let newStillValid = await lease.validate(owner: new)
        XCTAssertFalse(oldMustRestore)
        XCTAssertTrue(newStillValid)
        let newMustRestore = await lease.release(owner: new)
        XCTAssertTrue(newMustRestore)
    }

    func testOnlyTheCurrentOwnerTriggersRestoration() async {
        let lease = HelperLeaseManager(duration: 0)
        let old = UUID(), new = UUID()
        _ = await lease.begin(owner: old)
        _ = await lease.begin(owner: new)
        let oldNeedsRestore = await lease.needsRestore(owner: old)
        let newNeedsRestore = await lease.needsRestore(owner: new)
        XCTAssertFalse(oldNeedsRestore)
        XCTAssertTrue(newNeedsRestore)
    }

    func testWriterParameterBlockMatchesKernelABI() {
        let layout = HelperSMCWriteConnection.parameterBlockLayout
        XCTAssertEqual(layout.size, 80)
        XCTAssertEqual(layout.resultOffset, 40)
    }

    func testRestoreWithoutWriterSucceedsBecauseNothingWasForced() async {
        let controller = HelperSMCFanController(reader: FakeFanReader([fan()]), writer: nil)
        let restored = await controller.restoreAll()
        XCTAssertTrue(restored)
    }

    func testOneUnreadableFanDoesNotBlockTheOthers() async throws {
        let broken = FanDeviceState(
            id: "builtin:1", name: "Right fan", kind: .builtIn, connection: .connected,
            capabilities: nil, writeAvailability: .invalidCapabilities
        )
        let writer = FakeSMCWriter()
        let controller = HelperSMCFanController(reader: FakeFanReader([fan(0), broken]), writer: writer)
        let records = try await controller.listFans()
        XCTAssertEqual(records.map(\.fanID), ["builtin:0"])
        _ = try await controller.setTarget(fanID: "builtin:0", requestedRPM: 3_000)
        do {
            _ = try await controller.setTarget(fanID: "builtin:1", requestedRPM: 3_000)
            XCTFail("A fan without readable limits must not be controllable")
        } catch {}
        XCTAssertEqual(writer.recordedTargets.map(\.0), [0])
    }
}

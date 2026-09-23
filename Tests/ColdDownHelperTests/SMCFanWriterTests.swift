import XCTest
import ThermalCore
@testable import ColdDownHelperCore

/// In-memory SMC with programmable firmware rejections, recording every accepted write in order.
private final class FakeSMCKeyStore: SMCKeyAccess, @unchecked Sendable {
    struct Entry { var type: String; var data: Data }
    typealias RejectRule = (_ key: String, _ data: Data, _ current: [String: Entry]) -> Bool

    private let lock = NSLock()
    private var entries: [String: Entry]
    private var writes: [String] = []
    private var rejections = 0
    var rejectWrite: RejectRule = { _, _, _ in false }

    init(_ entries: [String: Entry]) { self.entries = entries }

    func describe(_ key: String) throws -> SMCKeyDescriptor {
        try locked {
            guard let entry = entries[key] else { throw ThermalControlError.unavailable("missing \(key)") }
            return SMCKeyDescriptor(type: entry.type, size: entry.data.count)
        }
    }

    func read(_ key: String) throws -> Data {
        try locked {
            guard let entry = entries[key] else { throw ThermalControlError.unavailable("missing \(key)") }
            return entry.data
        }
    }

    func write(_ key: String, _ data: Data) throws {
        try locked {
            guard var entry = entries[key], entry.data.count == data.count else { throw ThermalControlError.invalidData("bad write \(key)") }
            if rejectWrite(key, data, entries) {
                rejections += 1
                throw ThermalControlError.unavailable("firmware rejected \(key)")
            }
            entry.data = data
            entries[key] = entry
            writes.append("\(key)=\(data.map { String($0) }.joined(separator: ","))")
        }
    }

    func byte(_ key: String) -> UInt8? { locked { entries[key]?.data.first } }
    func data(_ key: String) -> Data? { locked { entries[key]?.data } }
    var log: [String] { locked { writes } }
    var rejectionCount: Int { locked { rejections } }

    private func locked<T>(_ body: () throws -> T) rethrows -> T { lock.lock(); defer { lock.unlock() }; return try body() }
}

private actor SleepLog {
    private(set) var durations: [Duration] = []
    func record(_ duration: Duration) { durations.append(duration) }
}

/// Holds the 3 s thermalmonitord wait open until the test releases it.
private actor Gate {
    private var reached = false
    private var continuation: CheckedContinuation<Void, Never>?
    func wait() async { reached = true; await withCheckedContinuation { continuation = $0 } }
    func open() { continuation?.resume(); continuation = nil }
    func isReached() -> Bool { reached }
}

private func float(_ value: Float) -> Data {
    let bits = value.bitPattern
    return Data([UInt8(truncatingIfNeeded: bits), UInt8(truncatingIfNeeded: bits >> 8), UInt8(truncatingIfNeeded: bits >> 16), UInt8(truncatingIfNeeded: bits >> 24)])
}

private func appleSiliconStore(modeKey: String, mode: UInt8, unlock: UInt8?) -> FakeSMCKeyStore {
    var entries: [String: FakeSMCKeyStore.Entry] = [
        "FNum": .init(type: "ui8 ", data: Data([1])),
        modeKey: .init(type: "ui8 ", data: Data([mode])),
        "F0Tg": .init(type: "flt ", data: float(0)),
        "F0Mn": .init(type: "flt ", data: float(2317)),
        "F0Mx": .init(type: "flt ", data: float(6550))
    ]
    if let unlock { entries["Ftst"] = .init(type: "ui8 ", data: Data([unlock])) }
    return FakeSMCKeyStore(entries)
}

final class SMCFanWriterTests: XCTestCase {
    private func makeWriter(_ store: FakeSMCKeyStore, appleSilicon: Bool, sleeps: SleepLog, gate: Gate? = nil) -> SMCFanWriter {
        SMCFanWriter(keys: store, appleSilicon: appleSilicon) { duration in
            await sleeps.record(duration)
            if let gate { await gate.wait() }
        }
    }

    func testM5DirectModeWriteSkipsFtstUnlock() async throws {
        let store = appleSiliconStore(modeKey: "F0md", mode: 3, unlock: nil)
        let sleeps = SleepLog()
        try await makeWriter(store, appleSilicon: true, sleeps: sleeps).setTarget(index: 0, rpm: 3_000)
        XCTAssertEqual(store.log, ["F0md=1", "F0Tg=\(float(3_000).map { String($0) }.joined(separator: ","))"])
        let recorded = await sleeps.durations
        XCTAssertTrue(recorded.isEmpty)
    }

    func testM1ToM4UnlockWithFtstThenForceThenTarget() async throws {
        let store = appleSiliconStore(modeKey: "F0Md", mode: 0, unlock: 0)
        // Firmware refuses forced mode until the Ftst unlock is set (Stats: "Ftst unlock (M1-M4)").
        store.rejectWrite = { key, data, current in key == "F0Md" && data.first == 1 && current["Ftst"]?.data.first != 1 }
        let sleeps = SleepLog()
        try await makeWriter(store, appleSilicon: true, sleeps: sleeps).setTarget(index: 0, rpm: 4_000)
        XCTAssertEqual(Array(store.log.dropLast()), ["Ftst=1", "F0Md=1"])
        XCTAssertTrue(store.log.last?.hasPrefix("F0Tg=") ?? false)
        XCTAssertEqual(store.data("F0Tg"), float(4_000))
        let recorded = await sleeps.durations
        XCTAssertTrue(recorded.isEmpty, "No fixed settle delay when the firmware accepts the mode write at once")
    }

    func testTakeoverPollsUntilThermalmonitordYields() async throws {
        let store = appleSiliconStore(modeKey: "F0Md", mode: 0, unlock: 0)
        let refusals = Counter()
        // thermalmonitord keeps the fan for the first few attempts after Ftst is set.
        store.rejectWrite = { key, data, current in
            guard key == "F0Md", data.first == 1 else { return false }
            if current["Ftst"]?.data.first != 1 { return true }
            return refusals.next() < 4
        }
        let sleeps = SleepLog()
        try await makeWriter(store, appleSilicon: true, sleeps: sleeps).setTarget(index: 0, rpm: 4_000)
        XCTAssertEqual(store.byte("F0Md"), 1)
        let recorded = await sleeps.durations
        XCTAssertEqual(recorded, Array(repeating: .milliseconds(100), count: 4), "Retries every 100 ms, no 3 s sleep")
    }

    func testRestoreReleasesForcedFanTargetAndUnlock() async throws {
        let store = appleSiliconStore(modeKey: "F0Md", mode: 1, unlock: 1)
        let sleeps = SleepLog()
        try await makeWriter(store, appleSilicon: true, sleeps: sleeps).restoreAllAutomatic()
        XCTAssertEqual(store.byte("F0Md"), 0)
        XCTAssertEqual(store.data("F0Tg"), float(0))
        XCTAssertEqual(store.byte("Ftst"), 0, "Unlike Stats, restoration hands control back to thermalmonitord")
    }

    func testRestoreLeavesSystemControlledFansUntouched() async throws {
        let store = appleSiliconStore(modeKey: "F0md", mode: 3, unlock: 0)
        try await makeWriter(store, appleSilicon: true, sleeps: SleepLog()).restoreAllAutomatic()
        XCTAssertTrue(store.log.isEmpty)
    }

    func testRestoreFailsVerificationWhenFirmwareKeepsFanForced() async {
        let store = appleSiliconStore(modeKey: "F0Md", mode: 1, unlock: 1)
        store.rejectWrite = { key, _, _ in key == "F0Md" }
        do {
            try await makeWriter(store, appleSilicon: true, sleeps: SleepLog()).restoreAllAutomatic()
            XCTFail("A fan still forced after restoration must be reported so the watchdog retries")
        } catch {}
    }

    func testRestoreDuringUnlockWaitAbortsForcing() async throws {
        let store = appleSiliconStore(modeKey: "F0Md", mode: 0, unlock: 0)
        // thermalmonitord has not yielded yet, so the takeover is waiting between retries when restore arrives.
        store.rejectWrite = { key, data, _ in key == "F0Md" && data.first == 1 }
        let gate = Gate()
        let writer = makeWriter(store, appleSilicon: true, sleeps: SleepLog(), gate: gate)
        let forcing = Task { try await writer.setTarget(index: 0, rpm: 4_000) }
        while !(await gate.isReached()) { try await Task.sleep(for: .milliseconds(5)) }

        try await writer.restoreAllAutomatic()  // must not wait for the takeover to finish
        await gate.open()
        do {
            try await forcing.value
            XCTFail("An unlock that outlived a restoration must not force the fan")
        } catch {}
        XCTAssertEqual(store.byte("F0Md"), 0)
        XCTAssertEqual(store.byte("Ftst"), 0)
        XCTAssertFalse(store.log.contains("F0Md=1"))
    }

    func testIntelWritesTargetThenLegacyMaskAndRestoresMask() async throws {
        let store = FakeSMCKeyStore([
            "FNum": .init(type: "ui8 ", data: Data([1])),
            "FS! ": .init(type: "ui16", data: Data([0, 0])),
            "F0Tg": .init(type: "fpe2", data: Data([0, 0]))
        ])
        let writer = makeWriter(store, appleSilicon: false, sleeps: SleepLog())
        try await writer.setTarget(index: 0, rpm: 2_000)
        XCTAssertEqual(store.log, ["F0Tg=31,64", "FS! =0,1"])
        try await writer.restoreAllAutomatic()
        XCTAssertEqual(store.data("FS! "), Data([0, 0]))
    }

    func testTransientFirmwareRejectionsAreRetried() async throws {
        let store = FakeSMCKeyStore([
            "FNum": .init(type: "ui8 ", data: Data([1])),
            "FS! ": .init(type: "ui16", data: Data([0, 1]))
        ])
        var remaining = 2
        store.rejectWrite = { key, _, _ in
            guard key == "FS! ", remaining > 0 else { return false }
            remaining -= 1
            return true
        }
        let sleeps = SleepLog()
        try await makeWriter(store, appleSilicon: false, sleeps: sleeps).restoreAllAutomatic()
        XCTAssertEqual(store.data("FS! "), Data([0, 0]))
        XCTAssertEqual(store.rejectionCount, 2)
        let recorded = await sleeps.durations
        XCTAssertEqual(recorded, [.milliseconds(50), .milliseconds(50)])
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func next() -> Int { lock.lock(); defer { lock.unlock() }; defer { value += 1 }; return value }
}

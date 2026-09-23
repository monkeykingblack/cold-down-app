import Foundation
import IntelSMC
import ThermalCore

/// Fan write sequencing for Intel and Apple Silicon, ported from Stats (SMC/smc.swift: `setFanMode`,
/// `setFanSpeed`, `unlockFanControl`, `retryModeWrite`, `resetFanControl`) with Cold Down's safety rules:
///
/// - Targets arrive already clamped to the fan's [min, max]; a zero target is never accepted from a client.
/// - Waits are asynchronous, so a `restoreAllAutomatic()` can run while an Apple Silicon unlock is waiting for
///   thermalmonitord. A restore bumps `epoch`; an in-flight unlock checks it before every write and aborts,
///   so a restore is never undone by a slower forcing sequence.
/// - Restoration only touches fans that are actually forced (mode 1) and also releases `Ftst`, which Stats leaves set.
actor SMCFanWriter: HelperSMCWriting {
    typealias Sleep = @Sendable (Duration) async throws -> Void

    struct Timing: Sendable {
        var writeAttempts = 10
        var writeRetryDelay: Duration = .milliseconds(50)
        var unlockWriteAttempts = 100
        var modeRetryDelay: Duration = .milliseconds(100)
        var modeAttemptsWhenUnlocked = 20
        /// After `Ftst` is set, the mode write is retried every `modeRetryDelay` until thermalmonitord yields.
        /// Stats sleeps a fixed 3 s first and then retries 300×; polling from the start keeps the same ~33 s
        /// budget but finishes as soon as the firmware accepts the write instead of always waiting 3 s.
        var modeAttemptsAfterUnlock = 330
    }

    private let keys: any SMCKeyAccess
    private let appleSilicon: Bool
    private let timing: Timing
    private let sleep: Sleep
    private var epoch = 0
    private var lowercaseModeKey: Bool?

    init(
        keys: any SMCKeyAccess,
        appleSilicon: Bool,
        timing: Timing = Timing(),
        sleep: @escaping Sleep = { try await Task.sleep(for: $0) }
    ) {
        self.keys = keys; self.appleSilicon = appleSilicon; self.timing = timing; self.sleep = sleep
    }

    // MARK: - HelperSMCWriting

    func setTarget(index: Int, rpm: Int) async throws {
        guard (0..<16).contains(index), rpm > 0 else { throw ThermalControlError.invalidData("Unsafe fan target") }
        let start = epoch
        if appleSilicon {
            // Apple Silicon: take control first, then set the speed (Stats order).
            if try !isForced(index) {
                ThermalLog.smc.notice("Taking manual control of fan \(index, privacy: .public)")
                try await unlockAndForce(index, epoch: start)
                ThermalLog.smc.notice("Fan \(index, privacy: .public) is under manual control")
            }
            try checkNotRestored(since: start)
            try await writeTarget(index, rpm: rpm, epoch: start)
        } else {
            try await writeTarget(index, rpm: rpm, epoch: start)
            try checkNotRestored(since: start)
            try await setIntelForced(index, forced: true)
        }
    }

    func setAutomatic(index: Int) async throws {
        guard (0..<16).contains(index) else { throw ThermalControlError.invalidData("Invalid fan index") }
        if appleSilicon {
            try await releaseAppleSiliconFan(index)
            // Hand control back to thermalmonitord once no fan is forced any more (Stats: popup.swift:66-71).
            if try (0..<fanCount()).allSatisfy({ try !isForced($0) }) { try await releaseUnlock() }
        } else {
            try await setIntelForced(index, forced: false)
        }
    }

    func restoreAllAutomatic() async throws {
        epoch += 1
        if appleSilicon {
            try await restoreAppleSilicon()
        } else {
            try await restoreIntel()
        }
    }

    // MARK: - Apple Silicon

    private func modeKey(_ index: Int) -> String {
        if lowercaseModeKey == nil { lowercaseModeKey = keys.exists(SMCFanKeys.modeKey(0, lowercase: true)) }
        return SMCFanKeys.modeKey(index, lowercase: lowercaseModeKey ?? false)
    }

    private func isForced(_ index: Int) throws -> Bool {
        guard let byte = try keys.read(modeKey(index)).first else { throw ThermalControlError.invalidData("Empty fan mode") }
        return SMCFanKeys.isForced(modeByte: byte)
    }

    private func modeData(_ index: Int, value: UInt8) throws -> Data {
        let descriptor = try keys.describe(modeKey(index))
        var data = Data(repeating: 0, count: descriptor.size)
        data[0] = value
        return data
    }

    /// Stats `unlockFanControl`: direct mode write (M5+) → `Ftst` unlock (M1–M4) → settle → retry mode write.
    private func unlockAndForce(_ index: Int, epoch start: Int) async throws {
        let forced = try modeData(index, value: 1)
        if (try? keys.write(modeKey(index), forced)) != nil {
            ThermalLog.smc.notice("Fan \(index, privacy: .public) accepted a direct mode write")
            return
        }

        guard let unlock = try? keys.read(SMCFanKeys.unlock), let unlockByte = unlock.first else {
            ThermalLog.smc.error("Direct mode write rejected and no Ftst key; manual control unavailable")
            throw ThermalControlError.unavailable("This Mac rejected manual fan control")
        }
        if unlockByte == 1 {
            try await writeWithRetry(modeKey(index), forced, attempts: timing.modeAttemptsWhenUnlocked, delay: timing.modeRetryDelay, epoch: start)
            return
        }
        var unlocked = Data(repeating: 0, count: unlock.count)
        unlocked[0] = 1
        try await writeWithRetry(SMCFanKeys.unlock, unlocked, attempts: timing.unlockWriteAttempts, delay: timing.writeRetryDelay, epoch: start)
        ThermalLog.smc.notice("Ftst unlocked; polling until thermalmonitord yields fan \(index, privacy: .public)")
        let unlockedAt = ContinuousClock.now
        try await writeWithRetry(modeKey(index), forced, attempts: timing.modeAttemptsAfterUnlock, delay: timing.modeRetryDelay, epoch: start)
        ThermalLog.smc.notice("thermalmonitord yielded fan \(index, privacy: .public) after \(String(describing: ContinuousClock.now - unlockedAt), privacy: .public)")
    }

    private func releaseAppleSiliconFan(_ index: Int) async throws {
        guard try isForced(index) else { return }  // leave auto (0) and system (3) modes untouched
        try await writeWithRetry(modeKey(index), try modeData(index, value: 0), attempts: timing.writeAttempts, delay: timing.writeRetryDelay, epoch: nil)
        // Stats also clears the target when returning a fan to auto; best-effort, the mode is what matters.
        let targetKey = SMCFanKeys.key(index, "Tg")
        if let descriptor = try? keys.describe(targetKey), descriptor.type.hasPrefix("flt"), descriptor.size == 4 {
            try? await writeWithRetry(targetKey, Data(count: 4), attempts: timing.writeAttempts, delay: timing.writeRetryDelay, epoch: nil)
        }
    }

    private func releaseUnlock() async throws {
        guard let unlock = try? keys.read(SMCFanKeys.unlock), unlock.first == 1 else { return }
        try await writeWithRetry(SMCFanKeys.unlock, Data(count: unlock.count), attempts: timing.writeAttempts, delay: timing.writeRetryDelay, epoch: nil)
    }

    private func restoreAppleSilicon() async throws {
        ThermalLog.smc.notice("Restoring Apple Silicon fans to system control")
        var failed = false
        for index in 0..<fanCount() {
            guard keys.exists(modeKey(index)) else { continue }
            do { try await releaseAppleSiliconFan(index) } catch { failed = true }
        }
        do { try await releaseUnlock() } catch { failed = true }
        // Verify by read-back: no fan forced and the unlock released.
        for index in 0..<fanCount() where keys.exists(modeKey(index)) {
            if (try? isForced(index)) ?? true { failed = true }
        }
        if let unlock = try? keys.read(SMCFanKeys.unlock), unlock.first == 1 { failed = true }
        if failed { throw ThermalControlError.unavailable("One or more fans did not return to Auto") }
    }

    // MARK: - Intel

    private func setIntelForced(_ index: Int, forced: Bool) async throws {
        if keys.exists(SMCFanKeys.legacyModeMask) {
            let current = try keys.read(SMCFanKeys.legacyModeMask)
            guard current.count >= 2 else { throw ThermalControlError.invalidData("Invalid fan mode mask") }
            var mask = UInt16(current[0]) << 8 | UInt16(current[1])
            let bit = UInt16(1) << UInt16(index)
            if forced { mask |= bit } else { mask &= ~bit }
            try await writeWithRetry(SMCFanKeys.legacyModeMask, Data([UInt8(mask >> 8), UInt8(mask & 0xFF)]), attempts: timing.writeAttempts, delay: timing.writeRetryDelay, epoch: nil)
            return
        }
        let key = SMCFanKeys.modeKey(index, lowercase: false)
        let descriptor = try keys.describe(key)
        var data = Data(repeating: 0, count: descriptor.size)
        data[0] = forced ? 1 : 0
        try await writeWithRetry(key, data, attempts: timing.writeAttempts, delay: timing.writeRetryDelay, epoch: nil)
    }

    private func restoreIntel() async throws {
        if let descriptor = try? keys.describe(SMCFanKeys.legacyModeMask) {
            try await writeWithRetry(SMCFanKeys.legacyModeMask, Data(count: descriptor.size), attempts: timing.writeAttempts, delay: timing.writeRetryDelay, epoch: nil)
            guard try keys.read(SMCFanKeys.legacyModeMask).allSatisfy({ $0 == 0 }) else {
                throw ThermalControlError.unavailable("Fan mode mask did not return to Auto")
            }
            return
        }
        var failed = false
        for index in 0..<fanCount() {
            let key = SMCFanKeys.modeKey(index, lowercase: false)
            guard let descriptor = try? keys.describe(key) else { continue }
            do {
                try await writeWithRetry(key, Data(count: descriptor.size), attempts: timing.writeAttempts, delay: timing.writeRetryDelay, epoch: nil)
                if let byte = try keys.read(key).first, SMCFanKeys.isForced(modeByte: byte) { failed = true }
            } catch { failed = true }
        }
        if failed { throw ThermalControlError.unavailable("One or more fans did not return to Auto") }
    }

    // MARK: - Shared

    private func fanCount() -> Int {
        (try? keys.read("FNum").first).map { min(Int($0), 16) } ?? 0
    }

    private func writeTarget(_ index: Int, rpm: Int, epoch start: Int) async throws {
        let key = SMCFanKeys.key(index, "Tg")
        let descriptor = try keys.describe(key)
        let data = try SMCValueCodec.encodeRPM(rpm, type: descriptor.type, size: descriptor.size)
        try await writeWithRetry(key, data, attempts: timing.writeAttempts, delay: timing.writeRetryDelay, epoch: start)
    }

    /// Bounded retry (Stats `writeWithRetry`: 10 × 50 ms by default). With an `epoch`, the write belongs to a
    /// forcing sequence and is abandoned as soon as a restoration has started.
    private func writeWithRetry(_ key: String, _ data: Data, attempts: Int, delay: Duration, epoch start: Int?) async throws {
        var lastError: Error = ThermalControlError.unavailable("SMC write failed")
        for attempt in 0..<max(attempts, 1) {
            if let start { try checkNotRestored(since: start) }
            do {
                try keys.write(key, data)
                return
            } catch {
                lastError = error
            }
            if attempt < attempts - 1 { try await sleep(delay) }
        }
        ThermalLog.smc.error("SMC write \(key, privacy: .public) failed after \(attempts, privacy: .public) attempts: \(lastError.localizedDescription, privacy: .public)")
        throw lastError
    }

    private func checkNotRestored(since start: Int) throws {
        guard epoch == start else { throw ThermalControlError.unavailable("Fan control was restored to Auto") }
    }
}

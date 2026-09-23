import Foundation
import IntelSMC
import ThermalCore
import ColdDownShared

actor HelperSMCFanController {
    private let reader: any BuiltInFanReader
    private let writer: (any HelperSMCWriting)?

    init(
        reader: any BuiltInFanReader = AppleSMCFanReader(),
        writer: (any HelperSMCWriting)? = HelperSMCFanController.defaultWriter()
    ) {
        self.reader = reader; self.writer = writer
    }

    /// Intel uses the `FS! `/`F%dMd` keys; Apple Silicon uses the Stats-style `Ftst` unlock (see `SMCFanWriter`).
    static func defaultWriter() -> (any HelperSMCWriting)? {
        guard let connection = try? HelperSMCWriteConnection() else { return nil }
        return SMCFanWriter(keys: connection, appleSilicon: HardwarePlatform.isAppleSilicon)
    }

    /// Only fans whose limits are readable and sane are offered for control; the others stay read-only in the
    /// app (it falls back to the unprivileged reader's state for them) instead of disabling every fan.
    func listFans() async throws -> [HelperFanRecord] {
        try await controllableFans().map { fan in
            let capabilities = fan.capabilities!
            return HelperFanRecord(
                fanID: fan.id, name: fan.name, currentRPM: fan.currentSpeed ?? capabilities.minimum,
                minimumRPM: capabilities.minimum, maximumRPM: capabilities.maximum,
                targetRPM: fan.targetSpeed, isAutomatic: fan.reportedMode.map { $0 == .auto }
            )
        }
    }

    func setAuto(fanID: String) async throws {
        let (index, _) = try await validatedFan(fanID)
        guard let writer else { throw ThermalControlError.unavailable("SMC writer unavailable") }
        try await writer.setAutomatic(index: index)
    }

    func setTarget(fanID: String, requestedRPM: Int) async throws -> Int {
        let (index, fan) = try await validatedFan(fanID)
        guard let capabilities = fan.capabilities, capabilities.isStructurallyValid, capabilities.minimum > 0 else {
            throw ThermalControlError.invalidCapabilities
        }
        let target = capabilities.clamped(requestedRPM)
        guard target > 0, let writer else { throw ThermalControlError.unavailable("SMC writer unavailable") }
        try await writer.setTarget(index: index, rpm: target)
        return target
    }

    /// Fail-safe restoration. Deliberately independent of fan discovery or limit validation:
    /// a fan whose limits can no longer be read must still be returned to system control.
    func restoreAll() async -> Bool {
        // Without a writer the helper can never have forced a fan, so there is nothing to restore.
        guard let writer else { return true }
        do {
            try await writer.restoreAllAutomatic()
            return true
        } catch {
            ThermalLog.safety.error("Restoring system Auto mode failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func controllableFans() async throws -> [FanDeviceState] {
        let fans = try await reader.listFans()
        guard fans.count <= 16 else { throw ThermalControlError.invalidCapabilities }
        return fans.enumerated().compactMap { index, fan in
            Self.isControllable(fan, index: index) ? fan : nil
        }
    }

    static func isControllable(_ fan: FanDeviceState, index: Int) -> Bool {
        guard fan.id == "builtin:\(index)", let capability = fan.capabilities else { return false }
        return capability.isStructurallyValid && capability.minimum > 0
    }

    private func validatedFan(_ id: String) async throws -> (Int, FanDeviceState) {
        guard id.hasPrefix("builtin:"), let index = Int(id.dropFirst("builtin:".count)) else {
            throw ThermalControlError.invalidData("Unknown fan identity")
        }
        let fans = try await reader.listFans()
        guard fans.count <= 16, fans.indices.contains(index), fans[index].id == id else {
            throw ThermalControlError.invalidData("Fan index changed")
        }
        guard Self.isControllable(fans[index], index: index) else { throw ThermalControlError.invalidCapabilities }
        return (index, fans[index])
    }
}

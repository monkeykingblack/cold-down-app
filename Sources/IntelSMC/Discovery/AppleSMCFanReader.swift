import Foundation
import ThermalCore

public actor AppleSMCFanReader: BuiltInFanReader {
    private let connection: AppleSMCConnection?
    public init(connection: AppleSMCConnection? = try? AppleSMCConnection()) { self.connection = connection }

    public func listFans() async throws -> [FanDeviceState] {
        guard let connection,
              let countValue = try? connection.read("FNum"),
              let first = countValue.bytes.first else { return [] }
        let count = min(Int(first), 16)
        // Legacy Macs expose a global forced-mode mask; T2 Macs expose a per-fan F*Md key instead.
        let forcedMask = (try? connection.read(SMCFanKeys.legacyModeMask)).flatMap { try? SMCValueCodec.decodeUnsigned16(data: $0.bytes) }
        let lowercaseModeKey = HardwarePlatform.isAppleSilicon && (try? connection.read(SMCFanKeys.modeKey(0, lowercase: true))) != nil
        var fans: [FanDeviceState] = []
        for index in 0..<count {
            let prefix = SMCFanKeys.key(index, "")
            let current = readRPM(connection, key: prefix + "Ac")
            let minimum = readRPM(connection, key: prefix + "Mn")
            let maximum = readRPM(connection, key: prefix + "Mx")
            let target = readRPM(connection, key: prefix + "Tg")
            let reportedMode: FanControlMode?
            if let forcedMask {
                reportedMode = forcedMask & (UInt16(1) << UInt16(index)) == 0 ? .auto : .manual
            } else {
                reportedMode = (try? connection.read(SMCFanKeys.modeKey(index, lowercase: lowercaseModeKey)).bytes.first)
                    .map { SMCFanKeys.isForced(modeByte: $0) ? .manual : .auto }
            }
            let capabilities: SpeedCapabilities?
            if let minimum, let maximum, minimum > 0, maximum >= minimum {
                capabilities = SpeedCapabilities(minimum: minimum, maximum: maximum, provenance: .deviceVerified)
            } else { capabilities = nil }
            fans.append(FanDeviceState(
                id: "builtin:\(index)", name: fanName(connection, prefix: prefix, index: index, count: count),
                kind: .builtIn, connection: .connected, currentSpeed: current, targetSpeed: target,
                reportedMode: reportedMode, capabilities: capabilities,
                writeAvailability: capabilities == nil ? .invalidCapabilities : Self.writeAvailability,
                statusMessage: capabilities == nil ? "Fan limits unavailable" : Self.controlMessage
            ))
        }
        return fans
    }

    private static let writeAvailability = WriteAvailability.helperMissing
    private static let controlMessage = "Install helper to enable control"

    /// The SMC's own label ("Left fan", "Right fan", …) when available, else "Mac fan" / "Mac fan N".
    private func fanName(_ connection: AppleSMCConnection, prefix: String, index: Int, count: Int) -> String {
        if let value = try? connection.read(prefix + "ID"),
           let name = SMCValueCodec.decodeFanName(data: value.bytes, type: value.dataType) {
            return name.localizedCaseInsensitiveContains("fan") ? name.capitalizedFirst : "\(name.capitalizedFirst) fan"
        }
        return count == 1 ? "Mac fan" : "Mac fan \(index + 1)"
    }

    private func readRPM(_ connection: AppleSMCConnection, key: String) -> Int? {
        guard let value = try? connection.read(key) else { return nil }
        return try? SMCValueCodec.decodeRPM(data: value.bytes, type: value.dataType)
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

import Foundation
import ThermalCore

/// Commands Cold Down may send or understand. Protocol reference: THRM (TIANLI0/THRM), internal/deviceproto;
/// 0x0D, 0x27 and 0x2A as described by Flydigi-BS and confirmed on a BS3 Pro (firmware 2.4).
/// Destructive maintenance commands (0x03 init, 0x05/0x06, which sources describe as clear latch/factory reset or
/// power off/on), flash-writing gear/RGB commands (including 0x26 gear speeds), and firmware update are
/// intentionally not representable.
public enum FlydigiCommand: UInt8, CaseIterable, Sendable {
    case firmwareVersion = 0x01
    case capabilityTier = 0x07
    /// What the cooler does when the host sleeps; payload is a `FlydigiSleepBehavior`.
    case setSleepBehavior = 0x0D
    case selectGear = 0x08
    case setRealtimeRPM = 0x21
    case queryRPM = 0x22
    case enterRealtimeRPM = 0x23
    case exitRealtimeRPM = 0x24
    case queryWorkMode = 0x25
    /// Answers the four gear speeds as little-endian RPM pairs.
    case queryGearSpeeds = 0x27
    /// How quickly the fan ramps between speeds; payload is a `FlydigiAcceleration`.
    case setAcceleration = 0x2A
    /// Unsolicited status frame the device pushes periodically.
    case statusPush = 0xEF
}

public struct FlydigiFrame: Equatable, Sendable {
    public let command: FlydigiCommand
    public let payload: Data
    public init(command: FlydigiCommand, payload: Data) {
        self.command = command
        self.payload = payload
    }
}

/// Fan acceleration (0x2A). The device cannot report the current level, so the app remembers what it last set.
public enum FlydigiAcceleration: UInt8, CaseIterable, Sendable {
    case level1 = 0, level2 = 1, level3 = 2, level4 = 3
    public var title: String { "Level \(rawValue + 1)" }
}

/// What the cooler does when the host sleeps (0x0D). Like acceleration, it cannot be read back.
public enum FlydigiSleepBehavior: UInt8, CaseIterable, Sendable {
    case keepRunning = 0, stopImmediately = 1, stopAfterDelay = 2
    public var title: String {
        switch self {
        case .keepRunning: "Keep running"
        case .stopImmediately: "Stop at once"
        case .stopAfterDelay: "Stop after a delay"
        }
    }
}

/// Decoded 0xEF push: `[gear][mode][reserved][currentRPM LE][targetRPM LE]…`.
public struct FlydigiStatus: Equatable, Sendable {
    public let gear: UInt8
    public let mode: UInt8
    public let currentRPM: Int
    public let targetRPM: Int

    /// Bit 0 of the mode byte is set while the host's realtime RPM control is active.
    public var realtimeActive: Bool { mode & 0x01 != 0 }

    public init?(frame: FlydigiFrame) {
        guard frame.command == .statusPush, frame.payload.count >= 7 else { return nil }
        let bytes = [UInt8](frame.payload)
        gear = bytes[0]
        mode = bytes[1]
        currentRPM = Int(bytes[3]) | Int(bytes[4]) << 8
        targetRPM = Int(bytes[5]) | Int(bytes[6]) << 8
    }
}

public enum FlydigiPacketCodec {
    /// Report ID (1 byte) + exactly 24 data bytes. The firmware's Bluetooth HID path rejects any other write length.
    public static let reportLength = 25
    /// Output (host → device) report ID. Replies arrive on input report ID 0x01.
    public static let reportID: UInt8 = 0x02

    public static func encode(command: FlydigiCommand, payload: Data = Data()) throws -> Data {
        guard command != .statusPush else { throw ThermalControlError.forbiddenCommand }
        guard payload.count <= reportLength - 6 else {
            throw ThermalControlError.invalidData("Flydigi payload is too large")
        }
        var report = Data(repeating: 0, count: reportLength)
        report[0] = reportID
        report[1] = 0x5A
        report[2] = 0xA5
        report[3] = command.rawValue
        report[4] = UInt8(payload.count + 2)
        report.replaceSubrange(5..<(5 + payload.count), with: payload)
        report[5 + payload.count] = checksum(command: command.rawValue, length: report[4], payload: payload)
        return report
    }

    public static func encodeTargetRPM(_ rpm: Int) throws -> Data {
        guard (1...UInt16.max.intValue).contains(rpm) else {
            throw ThermalControlError.invalidData("RPM target must be positive UInt16")
        }
        let value = UInt16(rpm)
        return try encode(command: .setRealtimeRPM, payload: Data([UInt8(value & 0xFF), UInt8(value >> 8)]))
    }

    /// Decodes a frame with or without a leading report-ID byte. Any report ID is accepted (replies use 0x01,
    /// our own output reports 0x02), as long as the `5A A5` marker follows it.
    public static func decode(_ input: Data) throws -> FlydigiFrame {
        let input = Data(Array(input))
        let start: Int
        if input.count >= 6, input[1] == 0x5A, input[2] == 0xA5 { start = 1 }
        else if input.count >= 5, input[0] == 0x5A, input[1] == 0xA5 { start = 0 }
        else { throw ThermalControlError.invalidData("Flydigi marker is invalid") }

        let commandOffset = start + 2
        let lengthOffset = start + 3
        guard let command = FlydigiCommand(rawValue: input[commandOffset]) else {
            throw ThermalControlError.forbiddenCommand
        }
        let declaredLength = Int(input[lengthOffset])
        guard declaredLength >= 2 else { throw ThermalControlError.invalidData("Flydigi length is invalid") }
        let payloadCount = declaredLength - 2
        let payloadStart = start + 4
        let checksumOffset = payloadStart + payloadCount
        guard checksumOffset < input.count else { throw ThermalControlError.invalidData("Flydigi frame is truncated") }
        let payload = input.subdata(in: payloadStart..<checksumOffset)
        let expected = checksum(command: command.rawValue, length: input[lengthOffset], payload: payload)
        guard input[checksumOffset] == expected else { throw ThermalControlError.invalidData("Flydigi checksum mismatch") }
        return FlydigiFrame(command: command, payload: payload)
    }

    /// Status byte rules from THRM `commands.go`: set commands answer 1 on success; 0x23 also answers 3
    /// ("already realtime") and 0x24 answers 2 ("already out of realtime").
    public static func acceptsAcknowledgement(_ frame: FlydigiFrame, for command: FlydigiCommand) -> Bool {
        guard frame.command == command else { return false }
        switch command {
        case .enterRealtimeRPM, .setRealtimeRPM, .exitRealtimeRPM, .selectGear, .setSleepBehavior, .setAcceleration:
            guard let status = frame.payload.first else { return false }
            switch command {
            case .enterRealtimeRPM: return status == 0x01 || status == 0x03
            case .exitRealtimeRPM: return status == 0x01 || status == 0x02
            default: return status == 0x01
            }
        case .firmwareVersion, .capabilityTier, .queryRPM, .queryWorkMode, .queryGearSpeeds, .statusPush:
            return true
        }
    }

    private static func checksum(command: UInt8, length: UInt8, payload: Data) -> UInt8 {
        var sum = UInt16(command) + UInt16(length)
        for byte in payload { sum += UInt16(byte) }
        return UInt8(truncatingIfNeeded: sum)
    }
}

private extension UInt16 {
    var intValue: Int { Int(self) }
}

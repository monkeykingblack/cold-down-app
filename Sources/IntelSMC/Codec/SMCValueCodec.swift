import Foundation
import ThermalCore

public enum SMCValueCodec {
    public static func decodeTemperature(data: Data, type: String) throws -> Double {
        let value: Double
        switch normalizedType(type) {
        case "sp78":
            guard data.count >= 2 else { throw ThermalControlError.invalidData("sp78 requires two bytes") }
            let raw = Int16(bitPattern: UInt16(data[0]) << 8 | UInt16(data[1]))
            value = Double(raw) / 256
        case "fpe2":
            value = Double(try decodeUnsigned16(data: data)) / 4
        case "flt":
            value = Double(try decodeFloat32(data: data))
        case "ui8":
            guard let byte = data.first else { throw ThermalControlError.invalidData("ui8 requires one byte") }
            value = Double(byte)
        case "ui16":
            value = Double(try decodeUnsigned16(data: data))
        default:
            throw ThermalControlError.invalidData("Unsupported SMC type \(type)")
        }
        guard value.isFinite, (-20...125).contains(value) else {
            throw ThermalControlError.invalidData("Temperature is not plausible")
        }
        return value
    }

    public static func decodeRPM(data: Data, type: String) throws -> Int {
        let rpm: Double
        switch normalizedType(type) {
        case "fpe2": rpm = Double(try decodeUnsigned16(data: data)) / 4
        case "flt": rpm = Double(try decodeFloat32(data: data))
        case "ui16": rpm = Double(try decodeUnsigned16(data: data))
        case "ui8":
            guard let value = data.first else { throw ThermalControlError.invalidData("ui8 requires one byte") }
            rpm = Double(value)
        default: throw ThermalControlError.invalidData("Unsupported fan type \(type)")
        }
        guard rpm.isFinite, rpm >= 0, rpm <= 30_000 else {
            throw ThermalControlError.invalidData("Fan speed is not plausible")
        }
        return Int(rpm.rounded())
    }

    /// Encodes a fan target for the key's reported SMC type and size.
    /// `fpe2`/`ui16` are big-endian; `flt` (T2 Macs) is a little-endian IEEE-754 float.
    public static func encodeRPM(_ rpm: Int, type: String, size: Int) throws -> Data {
        guard rpm > 0, rpm <= 30_000 else { throw ThermalControlError.invalidData("Unsafe RPM") }
        switch (normalizedType(type), size) {
        case ("fpe2", 2):
            let raw = UInt16(rpm * 4)
            return Data([UInt8(raw >> 8), UInt8(raw & 0xFF)])
        case ("ui16", 2):
            let raw = UInt16(rpm)
            return Data([UInt8(raw >> 8), UInt8(raw & 0xFF)])
        case ("flt", 4):
            let bits = Float(rpm).bitPattern
            return Data([
                UInt8(truncatingIfNeeded: bits), UInt8(truncatingIfNeeded: bits >> 8),
                UInt8(truncatingIfNeeded: bits >> 16), UInt8(truncatingIfNeeded: bits >> 24)
            ])
        default:
            throw ThermalControlError.invalidData("Unsupported fan target type \(type) (\(size) bytes)")
        }
    }

    /// Fan description key `F%dID` (type `{fds`): the name is a NUL-padded ASCII string at bytes 4..<16
    /// (Stats `SMC/smc.swift`). Returns nil for anything that isn't a plausible name.
    public static func decodeFanName(data: Data, type: String) -> String? {
        guard normalizedType(type) == "{fds", data.count >= 5 else { return nil }
        let bytes = data.subdata(in: data.startIndex + 4..<data.startIndex + min(16, data.count))
        let name = String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
        guard !name.isEmpty, name.unicodeScalars.allSatisfy({ $0.isASCII && $0.value >= 0x20 }) else { return nil }
        return name
    }

    public static func decodeUnsigned16(data: Data) throws -> UInt16 {
        guard data.count >= 2 else { throw ThermalControlError.invalidData("Expected two bytes") }
        return UInt16(data[0]) << 8 | UInt16(data[1])
    }

    public static func decodeUnsigned32(data: Data) throws -> UInt32 {
        guard data.count >= 4 else { throw ThermalControlError.invalidData("Expected four bytes") }
        return UInt32(data[0]) << 24 | UInt32(data[1]) << 16 | UInt32(data[2]) << 8 | UInt32(data[3])
    }

    /// SMC `flt` values are stored in the host's little-endian byte order.
    public static func decodeFloat32(data: Data) throws -> Float {
        guard data.count >= 4 else { throw ThermalControlError.invalidData("float requires four bytes") }
        let bits = UInt32(data[0]) | UInt32(data[1]) << 8 | UInt32(data[2]) << 16 | UInt32(data[3]) << 24
        return Float(bitPattern: bits)
    }

    private static func normalizedType(_ type: String) -> String {
        type.trimmingCharacters(in: .controlCharacters.union(.whitespaces).union(CharacterSet(charactersIn: "\0")))
    }
}

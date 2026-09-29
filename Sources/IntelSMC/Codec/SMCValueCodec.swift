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

import Foundation
import IOKit
import ThermalCore

public struct SMCValue: Sendable {
    public let key: String
    public let dataType: String
    public let bytes: Data
}

private struct SMCVersion {
    var major: UInt8 = 0
    var minor: UInt8 = 0
    var build: UInt8 = 0
    var reserved: UInt8 = 0
    var release: UInt16 = 0
}

private struct SMCPLimitData {
    var version: UInt16 = 0
    var length: UInt16 = 0
    var cpuPLimit: UInt32 = 0
    var gpuPLimit: UInt32 = 0
    var memPLimit: UInt32 = 0
}

/// Mirrors the kernel's C struct, which is 12 bytes: Swift does not add the 3 bytes of tail padding C does,
/// and without them every later field (result, command, data) lands at the wrong offset and all calls fail.
private struct SMCKeyInfoData {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
    var padding: (UInt8, UInt8, UInt8) = (0, 0, 0)
}

private typealias SMCBytes = (
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
)

private struct SMCParamStruct {
    var key: UInt32 = 0
    var vers = SMCVersion()
    var pLimitData = SMCPLimitData()
    var keyInfo = SMCKeyInfoData()
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: SMCBytes = (0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0)
}

public final class AppleSMCConnection: @unchecked Sendable {
    private static let selector: UInt32 = 2
    private static let readBytesCommand: UInt8 = 5
    private static let readIndexCommand: UInt8 = 8
    private static let readKeyInfoCommand: UInt8 = 9
    private let connection: io_connect_t
    private let lock = NSLock()
    private var keyInfoCache: [UInt32: SMCKeyInfoData] = [:]

    public init() throws {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { throw ThermalControlError.unavailable("AppleSMC service is unavailable") }
        defer { IOObjectRelease(service) }
        var connection: io_connect_t = 0
        let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
        guard result == KERN_SUCCESS else {
            throw ThermalControlError.unavailable("AppleSMC could not be opened")
        }
        self.connection = connection
    }

    deinit { IOServiceClose(connection) }

    /// Size of the AppleSMC parameter block and the offset of its result byte; must be 80 and 40 to match the kernel ABI.
    public static var parameterBlockLayout: (size: Int, resultOffset: Int) {
        (MemoryLayout<SMCParamStruct>.stride, MemoryLayout<SMCParamStruct>.offset(of: \SMCParamStruct.result) ?? -1)
    }

    public func read(_ key: String) throws -> SMCValue {
        lock.lock(); defer { lock.unlock() }
        let numericKey = try Self.fourCC(key)
        let info = try keyInfo(for: numericKey)
        guard info.dataSize > 0, info.dataSize <= 32 else {
            throw ThermalControlError.invalidData("Invalid AppleSMC data size")
        }
        var input = SMCParamStruct()
        input.key = numericKey
        input.keyInfo.dataSize = info.dataSize
        input.data8 = Self.readBytesCommand
        let output = try call(input)
        let bytes = withUnsafeBytes(of: output.bytes) { Data($0.prefix(Int(info.dataSize))) }
        return SMCValue(key: key, dataType: Self.string(from: info.dataType), bytes: bytes)
    }

    public func allKeys() throws -> [String] {
        let countValue = try read("#KEY")
        let count = Int(try SMCValueCodec.decodeUnsigned32(data: countValue.bytes))
        guard count >= 0, count < 20_000 else { throw ThermalControlError.invalidData("Invalid SMC key count") }
        lock.lock(); defer { lock.unlock() }
        var keys: [String] = []
        keys.reserveCapacity(count)
        for index in 0..<count {
            var input = SMCParamStruct()
            input.data8 = Self.readIndexCommand
            input.data32 = UInt32(index)
            if let output = try? call(input) { keys.append(Self.string(from: output.key)) }
        }
        return keys
    }

    private func keyInfo(for key: UInt32) throws -> SMCKeyInfoData {
        if let cached = keyInfoCache[key] { return cached }
        var input = SMCParamStruct()
        input.key = key
        input.data8 = Self.readKeyInfoCommand
        let output = try call(input)
        keyInfoCache[key] = output.keyInfo
        return output.keyInfo
    }

    private func call(_ input: SMCParamStruct) throws -> SMCParamStruct {
        var input = input
        var output = SMCParamStruct()
        var outputSize = MemoryLayout<SMCParamStruct>.stride
        let result = withUnsafePointer(to: &input) { inputPointer in
            withUnsafeMutablePointer(to: &output) { outputPointer in
                IOConnectCallStructMethod(
                    connection, Self.selector, inputPointer, MemoryLayout<SMCParamStruct>.stride,
                    outputPointer, &outputSize
                )
            }
        }
        guard result == KERN_SUCCESS, output.result == 0 else {
            throw ThermalControlError.unavailable("AppleSMC request failed")
        }
        return output
    }

    private static func fourCC(_ string: String) throws -> UInt32 {
        let bytes = Array(string.utf8)
        guard bytes.count == 4 else { throw ThermalControlError.invalidData("SMC keys must contain four bytes") }
        return bytes.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }

    private static func string(from value: UInt32) -> String {
        let bytes: [UInt8] = [
            UInt8(truncatingIfNeeded: value >> 24), UInt8(truncatingIfNeeded: value >> 16),
            UInt8(truncatingIfNeeded: value >> 8), UInt8(truncatingIfNeeded: value)
        ]
        return String(bytes: bytes, encoding: .ascii) ?? "????"
    }
}

import Foundation
import IOKit
import IntelSMC
import ThermalCore

/// The helper's fan-control surface. Async because Apple Silicon unlocking waits for thermalmonitord.
protocol HelperSMCWriting: Sendable {
    func setTarget(index: Int, rpm: Int) async throws
    func setAutomatic(index: Int) async throws
    /// Returns every fan to system control without relying on fan limits being readable, then verifies by read-back.
    func restoreAllAutomatic() async throws
}

struct SMCKeyDescriptor: Equatable, Sendable {
    /// Four-character SMC type, e.g. "flt ", "fpe2", "ui8 ".
    let type: String
    let size: Int
}

/// Single-shot SMC key primitives. Sequencing, retries and safety live in `SMCFanWriter`, so they can be
/// tested against a fake key store; this protocol's IOKit implementation stays deliberately thin.
protocol SMCKeyAccess: Sendable {
    func describe(_ key: String) throws -> SMCKeyDescriptor
    func read(_ key: String) throws -> Data
    func write(_ key: String, _ data: Data) throws
}

extension SMCKeyAccess {
    func exists(_ key: String) -> Bool { (try? describe(key)) != nil }
}

private struct WriteSMCVersion { var major: UInt8 = 0; var minor: UInt8 = 0; var build: UInt8 = 0; var reserved: UInt8 = 0; var release: UInt16 = 0 }
private struct WriteSMCPLimit { var version: UInt16 = 0; var length: UInt16 = 0; var cpu: UInt32 = 0; var gpu: UInt32 = 0; var memory: UInt32 = 0 }
// 12 bytes like the kernel's C struct; the explicit tail padding keeps later fields at their C offsets.
private struct WriteSMCKeyInfo { var size: UInt32 = 0; var type: UInt32 = 0; var attributes: UInt8 = 0; var padding: (UInt8, UInt8, UInt8) = (0, 0, 0) }
private typealias WriteSMCBytes = (
    UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,
    UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,
    UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,
    UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8
)
private struct WriteSMCParam {
    var key: UInt32 = 0; var version = WriteSMCVersion(); var limits = WriteSMCPLimit()
    var info = WriteSMCKeyInfo(); var result: UInt8 = 0; var status: UInt8 = 0
    var command: UInt8 = 0; var data32: UInt32 = 0
    var bytes: WriteSMCBytes = (0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0)
}

/// IOKit AppleSMC key access for the root helper. The only code in the project that writes SMC keys.
final class HelperSMCWriteConnection: SMCKeyAccess, @unchecked Sendable {
    private let connection: io_connect_t
    private let lock = NSLock()
    private static let selector: UInt32 = 2

    init() throws {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { throw ThermalControlError.unavailable("AppleSMC unavailable") }
        defer { IOObjectRelease(service) }
        var connection: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == KERN_SUCCESS else {
            throw ThermalControlError.unavailable("AppleSMC open failed")
        }
        self.connection = connection
    }

    deinit { IOServiceClose(connection) }

    static var parameterBlockLayout: (size: Int, resultOffset: Int) {
        (MemoryLayout<WriteSMCParam>.stride, MemoryLayout<WriteSMCParam>.offset(of: \WriteSMCParam.result) ?? -1)
    }

    func describe(_ key: String) throws -> SMCKeyDescriptor {
        lock.lock(); defer { lock.unlock() }
        let info = try keyInfo(key)
        return SMCKeyDescriptor(type: typeName(info.type), size: Int(info.size))
    }

    func read(_ key: String) throws -> Data {
        lock.lock(); defer { lock.unlock() }
        let info = try keyInfo(key)
        var input = WriteSMCParam(); input.key = try fourCC(key); input.info.size = info.size; input.command = 5
        let output = try call(input)
        return withUnsafeBytes(of: output.bytes) { Data($0.prefix(Int(info.size))) }
    }

    func write(_ key: String, _ data: Data) throws {
        lock.lock(); defer { lock.unlock() }
        let info = try keyInfo(key)
        guard data.count == Int(info.size), data.count <= 32 else { throw ThermalControlError.invalidData("SMC write size mismatch") }
        var input = WriteSMCParam(); input.key = try fourCC(key); input.info = info; input.command = 6
        _ = withUnsafeMutableBytes(of: &input.bytes) { destination in data.copyBytes(to: destination) }
        _ = try call(input)
    }

    // MARK: - Locked helpers (caller holds `lock`)

    private func keyInfo(_ key: String) throws -> WriteSMCKeyInfo {
        var input = WriteSMCParam(); input.key = try fourCC(key); input.command = 9
        let info = try call(input).info
        guard info.size > 0, info.size <= 32 else { throw ThermalControlError.invalidData("Invalid SMC key size") }
        return info
    }

    private func call(_ inputValue: WriteSMCParam) throws -> WriteSMCParam {
        var input = inputValue; var output = WriteSMCParam(); var size = MemoryLayout<WriteSMCParam>.stride
        let result = withUnsafePointer(to: &input) { source in
            withUnsafeMutablePointer(to: &output) { destination in
                IOConnectCallStructMethod(connection, Self.selector, source, MemoryLayout<WriteSMCParam>.stride, destination, &size)
            }
        }
        // IOKit can return success while the SMC firmware still rejects the request (Stats smc.swift:684);
        // the firmware verdict is the result byte.
        guard result == KERN_SUCCESS, output.result == 0 else { throw ThermalControlError.unavailable("AppleSMC request rejected") }
        return output
    }

    private func typeName(_ value: UInt32) -> String {
        let bytes = [value >> 24, value >> 16, value >> 8, value].map { UInt8(truncatingIfNeeded: $0) }
        return String(bytes: bytes, encoding: .ascii) ?? ""
    }

    private func fourCC(_ value: String) throws -> UInt32 {
        let bytes = Array(value.utf8); guard bytes.count == 4 else { throw ThermalControlError.invalidData("Invalid SMC key") }
        return bytes.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }
}

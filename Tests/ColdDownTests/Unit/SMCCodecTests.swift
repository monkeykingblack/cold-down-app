import XCTest
import IntelSMC

final class SMCCodecTests: XCTestCase {
    func testSP78Decoding() throws {
        XCTAssertEqual(try SMCValueCodec.decodeTemperature(data: Data([0x37, 0x80]), type: "sp78"), 55.5, accuracy: 0.001)
    }

    func testSignedNegativeSP78Decoding() throws {
        XCTAssertEqual(try SMCValueCodec.decodeTemperature(data: Data([0xFB, 0x00]), type: "sp78"), -5, accuracy: 0.001)
    }

    func testFPE2Decoding() throws {
        XCTAssertEqual(try SMCValueCodec.decodeTemperature(data: Data([0x00, 0xA0]), type: "fpe2"), 40)
    }

    /// SMC `flt` values are little-endian (as returned by AppleSMC on T2 and Apple Silicon Macs).
    func testFloatDecoding() throws {
        let bits = Float(61.25).bitPattern
        let data = Data([
            UInt8(truncatingIfNeeded: bits), UInt8(truncatingIfNeeded: bits >> 8),
            UInt8(truncatingIfNeeded: bits >> 16), UInt8(truncatingIfNeeded: bits >> 24)
        ])
        XCTAssertEqual(try SMCValueCodec.decodeTemperature(data: data, type: "flt"), 61.25, accuracy: 0.001)
        XCTAssertEqual(try SMCValueCodec.decodeTemperature(data: data, type: "flt "), 61.25, accuracy: 0.001)
    }

    func testRejectsInvalidLengthTypeAndRange() {
        XCTAssertThrowsError(try SMCValueCodec.decodeTemperature(data: Data([0]), type: "sp78"))
        XCTAssertThrowsError(try SMCValueCodec.decodeTemperature(data: Data([0, 0]), type: "xxxx"))
        XCTAssertThrowsError(try SMCValueCodec.decodeTemperature(data: Data([0x7F, 0xFF]), type: "sp78"))
    }

    /// Real-hardware regression: without C tail padding the result byte sat at offset 37 and every SMC call failed.
    func testParameterBlockMatchesKernelABI() {
        let layout = AppleSMCConnection.parameterBlockLayout
        XCTAssertEqual(layout.size, 80)
        XCTAssertEqual(layout.resultOffset, 40)
    }

}

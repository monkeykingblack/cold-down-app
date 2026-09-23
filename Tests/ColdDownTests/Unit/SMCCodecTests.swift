import XCTest
import IntelSMC

final class SMCCodecTests: XCTestCase {
    func testSP78Decoding() throws {
        XCTAssertEqual(try SMCValueCodec.decodeTemperature(data: Data([0x37, 0x80]), type: "sp78"), 55.5, accuracy: 0.001)
    }

    func testSignedNegativeSP78Decoding() throws {
        XCTAssertEqual(try SMCValueCodec.decodeTemperature(data: Data([0xFB, 0x00]), type: "sp78"), -5, accuracy: 0.001)
    }

    func testFPE2AndIntegerDecoding() throws {
        XCTAssertEqual(try SMCValueCodec.decodeTemperature(data: Data([0x00, 0xA0]), type: "fpe2"), 40)
        XCTAssertEqual(try SMCValueCodec.decodeRPM(data: Data([0x1F, 0x40]), type: "ui16"), 8_000)
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

    func testT2FloatFanSpeedsRoundTrip() throws {
        let encoded = try SMCValueCodec.encodeRPM(2_150, type: "flt ", size: 4)
        XCTAssertEqual(encoded.count, 4)
        XCTAssertEqual(try SMCValueCodec.decodeRPM(data: encoded, type: "flt "), 2_150)
    }

    func testLegacyFPE2FanTargetEncoding() throws {
        XCTAssertEqual(try SMCValueCodec.encodeRPM(2_000, type: "fpe2", size: 2), Data([0x1F, 0x40]))
        XCTAssertEqual(try SMCValueCodec.decodeRPM(data: Data([0x1F, 0x40]), type: "fpe2"), 2_000)
    }

    func testFanTargetEncodingRejectsUnsafeOrMismatchedValues() {
        XCTAssertThrowsError(try SMCValueCodec.encodeRPM(0, type: "fpe2", size: 2))
        XCTAssertThrowsError(try SMCValueCodec.encodeRPM(2_000, type: "flt ", size: 2))
        XCTAssertThrowsError(try SMCValueCodec.encodeRPM(2_000, type: "sp78", size: 2))
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

    func testFanNameFromFdsKey() {
        var data = Data([0x00, 0x00, 0x00, 0x00])
        data.append(contentsOf: Array("Left side".utf8))
        data.append(contentsOf: [UInt8](repeating: 0, count: 16 - data.count))
        XCTAssertEqual(SMCValueCodec.decodeFanName(data: data, type: "{fds"), "Left side")
        XCTAssertNil(SMCValueCodec.decodeFanName(data: Data(count: 16), type: "{fds"))
        XCTAssertNil(SMCValueCodec.decodeFanName(data: data, type: "ui16"))
    }
}

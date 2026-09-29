import XCTest
import FlydigiHID
import ThermalCore

final class FlydigiPacketCodecTests: XCTestCase {
    func testFixedTargetFixture() throws {
        let report = try FlydigiPacketCodec.encodeTargetRPM(1_700)
        XCTAssertEqual(report.count, 25)
        XCTAssertEqual(Array(report.prefix(8)), [0x02, 0x5A, 0xA5, 0x21, 0x04, 0xA4, 0x06, 0xCF])
        XCTAssertEqual(try FlydigiPacketCodec.decode(report).payload, Data([0xA4, 0x06]))
    }

    func testDecodeWithoutReportIDAndRejectCorruption() throws {
        let full = try FlydigiPacketCodec.encode(command: .queryWorkMode)
        XCTAssertEqual(try FlydigiPacketCodec.decode(full.dropFirst()).command, .queryWorkMode)
        var corrupt = full; corrupt[5] = 0xFF
        XCTAssertThrowsError(try FlydigiPacketCodec.decode(corrupt))
    }

    func testPublicCommandTypeCannotRepresentDestructiveCommands() {
        XCTAssertNil(FlydigiCommand(rawValue: 0x05))
        XCTAssertNil(FlydigiCommand(rawValue: 0x06))
        XCTAssertNil(FlydigiCommand(rawValue: 0x03))
        XCTAssertNil(FlydigiCommand(rawValue: 0x26))  // flash-writing gear table
        XCTAssertEqual(
            Set(FlydigiCommand.allCases.map(\.rawValue)),
            Set([0x01, 0x07, 0x08, 0x0D, 0x21, 0x22, 0x23, 0x24, 0x25, 0x27, 0x2A, 0xEF])
        )
        XCTAssertThrowsError(try FlydigiPacketCodec.encode(command: .statusPush))
    }
}


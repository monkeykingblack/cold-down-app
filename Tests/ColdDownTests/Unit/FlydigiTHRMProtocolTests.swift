import XCTest
import FlydigiHID
import ThermalCore

/// Fixtures from THRM (TIANLI0/THRM): scripts/hid_data.md and internal/deviceproto.
final class FlydigiTHRMProtocolTests: XCTestCase {
    /// Device→host reports carry input report ID 0x01, not the output ID 0x02.
    func testDecodesInputReportIDAndStatusPush() throws {
        let captured = Data([0x01, 0x5A, 0xA5, 0xEF, 0x0B, 0x68, 0x04, 0x05, 0x80, 0x0C, 0x14, 0x05, 0xC7, 0x00, 0xD7, 0x00])
        let frame = try FlydigiPacketCodec.decode(captured)
        XCTAssertEqual(frame.command, .statusPush)
        let status = try XCTUnwrap(FlydigiStatus(frame: frame))
        XCTAssertEqual(status.currentRPM, 3_200)
        XCTAssertEqual(status.targetRPM, 1_300)
        XCTAssertFalse(status.realtimeActive)
    }

    func testReferenceRequestFrames() throws {
        XCTAssertEqual(Array(try FlydigiPacketCodec.encode(command: .enterRealtimeRPM).prefix(6)), [0x02, 0x5A, 0xA5, 0x23, 0x02, 0x25])
        XCTAssertEqual(Array(try FlydigiPacketCodec.encode(command: .exitRealtimeRPM).prefix(6)), [0x02, 0x5A, 0xA5, 0x24, 0x02, 0x26])
        XCTAssertEqual(Array(try FlydigiPacketCodec.encode(command: .queryRPM).prefix(6)), [0x02, 0x5A, 0xA5, 0x22, 0x02, 0x24])
    }

    func testAcknowledgementStatusRules() throws {
        func ack(_ command: FlydigiCommand, _ status: UInt8) -> Bool {
            FlydigiPacketCodec.acceptsAcknowledgement(FlydigiFrame(command: command, payload: Data([status])), for: command)
        }
        XCTAssertTrue(ack(.enterRealtimeRPM, 0x03))
        XCTAssertTrue(ack(.exitRealtimeRPM, 0x02))
        XCTAssertFalse(ack(.setRealtimeRPM, 0x02))
        XCTAssertTrue(ack(.setRealtimeRPM, 0x01))
    }

    func testRealtimeModeIsEnteredOnceAndSmallChangesAreSkipped() async throws {
        let enter = try reply(.enterRealtimeRPM, 0x01)
        let set = try reply(.setRealtimeRPM, 0x01)
        let transport = ScriptedReportTransport([.data(enter), .data(set), .data(set)])
        let controller = BS3ProController(transport: transport, capabilities: BS3ProController.auditedCapabilities)
        _ = try await controller.setTarget(2_000)
        _ = try await controller.setTarget(2_020)  // < 50 RPM change: no write
        _ = try await controller.setTarget(3_000)
        let commands = await transport.sentReports().map { $0[3] }
        XCTAssertEqual(commands, [0x23, 0x21, 0x21])
    }

    func testLostRealtimeModeIsReenteredOnce() async throws {
        let transport = ScriptedReportTransport([
            .data(try reply(.enterRealtimeRPM, 0x01)), .data(try reply(.setRealtimeRPM, 0x01)),
            .data(try reply(.setRealtimeRPM, 0x02)),  // "not in realtime mode"
            .data(try reply(.enterRealtimeRPM, 0x01)), .data(try reply(.setRealtimeRPM, 0x01))
        ])
        let controller = BS3ProController(transport: transport, capabilities: BS3ProController.auditedCapabilities)
        _ = try await controller.setTarget(2_000)
        _ = try await controller.setTarget(3_000)
        let commands = await transport.sentReports().map { $0[3] }
        XCTAssertEqual(commands, [0x23, 0x21, 0x21, 0x23, 0x21])
    }

    func testReleaseHandsControlBackToTheCooler() async throws {
        let transport = ScriptedReportTransport([
            .data(try reply(.enterRealtimeRPM, 0x01)), .data(try reply(.setRealtimeRPM, 0x01)),
            .data(try reply(.exitRealtimeRPM, 0x01))
        ])
        let controller = BS3ProController(transport: transport, capabilities: BS3ProController.auditedCapabilities)
        _ = try await controller.setTarget(2_000)
        await controller.releaseControl()
        let commands = await transport.sentReports().map { $0[3] }
        XCTAssertEqual(commands.last, 0x24)
    }

    func testTargetsStayWithinAuditedRange() async throws {
        let transport = ScriptedReportTransport([.data(try reply(.enterRealtimeRPM, 0x01)), .data(try reply(.setRealtimeRPM, 0x01))])
        let controller = BS3ProController(transport: transport, capabilities: BS3ProController.auditedCapabilities)
        let applied = try await controller.setTarget(9_000)
        XCTAssertEqual(applied.target, 4_000)
    }

    private func reply(_ command: FlydigiCommand, _ status: UInt8) throws -> Data {
        var data = try FlydigiPacketCodec.encode(command: command, payload: Data([status]))
        data[0] = 0x01  // input report ID
        return data
    }
}

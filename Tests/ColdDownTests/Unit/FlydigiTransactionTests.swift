import XCTest
import FlydigiHID
import ThermalCore

final class FlydigiTransactionTests: XCTestCase {
    func testMatchingAcknowledgementCompletesOneAttempt() async throws {
        let ack = try FlydigiPacketCodec.encode(command: .setRealtimeRPM, payload: Data([0x01]))
        let transport = ScriptedReportTransport([.data(ack)])
        let executor = FlydigiTransactionExecutor(transport: transport, attemptTimeout: .milliseconds(20))
        _ = try await executor.execute(command: .setRealtimeRPM, payload: Data([0xA4, 0x06]))
        let count = await transport.sentReports().count
        XCTAssertEqual(count, 1)
    }

    func testUnrelatedFramesAreIgnored() async throws {
        let unrelated = try FlydigiPacketCodec.encode(command: .queryWorkMode)
        let ack = try FlydigiPacketCodec.encode(command: .enterRealtimeRPM, payload: Data([0x03]))
        let transport = ScriptedReportTransport([.data(unrelated), .data(ack)])
        let executor = FlydigiTransactionExecutor(transport: transport, attemptTimeout: .milliseconds(20))
        _ = try await executor.execute(command: .enterRealtimeRPM)
        let count = await transport.sentReports().count
        XCTAssertEqual(count, 1)
    }

    func testRetryLimitIsThree() async {
        let transport = ScriptedReportTransport([.failure(.timeout), .failure(.timeout), .failure(.timeout)])
        let executor = FlydigiTransactionExecutor(transport: transport, attemptTimeout: .milliseconds(5))
        do { _ = try await executor.execute(command: .queryRPM); XCTFail("Expected timeout") }
        catch {
            let count = await transport.sentReports().count
            XCTAssertEqual(count, 3)
        }
    }

    func testStaleAcknowledgementFromEarlierAttemptIsDiscarded() async throws {
        let staleRejection = try FlydigiPacketCodec.encode(command: .setRealtimeRPM, payload: Data([0x00]))
        let ack = try FlydigiPacketCodec.encode(command: .setRealtimeRPM, payload: Data([0x01]))
        let transport = ScriptedReportTransport([.data(ack)], staleReports: [staleRejection])
        let executor = FlydigiTransactionExecutor(transport: transport, attemptTimeout: .milliseconds(20))
        _ = try await executor.execute(command: .setRealtimeRPM, payload: Data([0xA4, 0x06]))
        let discards = await transport.discards
        XCTAssertEqual(discards, 1)
    }

    func testConcurrentTransactionsAreSerialized() async throws {
        let first = try FlydigiPacketCodec.encode(command: .queryRPM, payload: Data([0x10, 0x00]))
        let second = try FlydigiPacketCodec.encode(command: .queryRPM, payload: Data([0x20, 0x00]))
        let transport = ScriptedReportTransport([.data(first), .data(second)])
        let executor = FlydigiTransactionExecutor(transport: transport, attemptTimeout: .milliseconds(50))
        async let a = executor.execute(command: .queryRPM)
        async let b = executor.execute(command: .queryRPM)
        let frames = try await [a, b]
        XCTAssertEqual(Set(frames.map(\.payload)), [Data([0x10, 0x00]), Data([0x20, 0x00])])
        let sent = await transport.sentReports().count
        XCTAssertEqual(sent, 2)
    }
}

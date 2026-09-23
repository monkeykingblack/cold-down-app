import Foundation
import ThermalCore

public protocol FlydigiReportTransport: Sendable {
    func send(_ report: Data) async throws
    func nextReport() async throws -> Data
    func isConnected() async -> Bool
    /// Drops input reports received before a request, so a late reply to an earlier attempt is never
    /// mistaken for the reply to the next one.
    func discardPendingReports() async
    /// Most recent unsolicited 0xEF status push, if the transport routes those separately from replies.
    func latestStatus() async -> FlydigiStatus?
    /// USB/Bluetooth product ID of the attached cooler.
    func connectedProductID() async -> Int?
}

extension FlydigiReportTransport {
    public func discardPendingReports() async {}
    public func latestStatus() async -> FlydigiStatus? { nil }
    public func connectedProductID() async -> Int? { nil }
}

public actor FlydigiTransactionExecutor {
    private let transport: any FlydigiReportTransport
    private let attemptTimeout: Duration
    private let maximumAttempts: Int
    private var busy = false
    private var queuedTransactions: [CheckedContinuation<Void, Never>] = []

    public init(
        transport: any FlydigiReportTransport,
        attemptTimeout: Duration = .milliseconds(900),
        maximumAttempts: Int = 3
    ) {
        self.transport = transport
        self.attemptTimeout = attemptTimeout
        self.maximumAttempts = min(max(maximumAttempts, 1), 3)
    }

    public func execute(command: FlydigiCommand, payload: Data = Data()) async throws -> FlydigiFrame {
        await beginTransaction()
        defer { endTransaction() }
        guard await transport.isConnected() else { throw ThermalControlError.disconnected }
        let report = try FlydigiPacketCodec.encode(command: command, payload: payload)
        var lastError: Error = ThermalControlError.timeout
        for _ in 0..<maximumAttempts {
            do {
                // Expected command is established by this call before the write occurs.
                await transport.discardPendingReports()
                try await transport.send(report)
                return try await matchingResponse(for: command)
            } catch ThermalControlError.acknowledgementRejected {
                // The device answered; resending the same command would not change its answer.
                throw ThermalControlError.acknowledgementRejected
            } catch {
                lastError = error
                if !(await transport.isConnected()) { throw ThermalControlError.disconnected }
            }
        }
        throw lastError
    }

    /// FIFO serialization of transactions without polling.
    private func beginTransaction() async {
        guard busy else { busy = true; return }
        await withCheckedContinuation { queuedTransactions.append($0) }
    }

    private func endTransaction() {
        if queuedTransactions.isEmpty { busy = false } else { queuedTransactions.removeFirst().resume() }
    }

    private func matchingResponse(for command: FlydigiCommand) async throws -> FlydigiFrame {
        let transport = self.transport
        let timeout = attemptTimeout
        return try await withThrowingTaskGroup(of: FlydigiFrame.self) { group in
            group.addTask {
                while !Task.isCancelled {
                    let data = try await transport.nextReport()
                    guard let frame = try? FlydigiPacketCodec.decode(data), frame.command == command else { continue }
                    guard FlydigiPacketCodec.acceptsAcknowledgement(frame, for: command) else {
                        throw ThermalControlError.acknowledgementRejected
                    }
                    return frame
                }
                throw CancellationError()
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw ThermalControlError.timeout
            }
            guard let result = try await group.next() else { throw ThermalControlError.timeout }
            group.cancelAll()
            return result
        }
    }
}


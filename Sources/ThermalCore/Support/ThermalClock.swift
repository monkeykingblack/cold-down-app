import Foundation

public protocol ThermalClock: Sendable {
    func now() async -> Date
    func sleep(for seconds: TimeInterval) async throws
}

public struct SystemThermalClock: ThermalClock {
    public init() {}
    public func now() async -> Date { Date() }
    public func sleep(for seconds: TimeInterval) async throws {
        try await Task.sleep(for: .seconds(seconds))
    }
}

public actor ManualThermalClock: ThermalClock {
    private var current: Date
    public init(now: Date = Date(timeIntervalSince1970: 0)) { current = now }
    public func now() -> Date { current }
    public func sleep(for seconds: TimeInterval) { current.addTimeInterval(seconds) }
    public func advance(by seconds: TimeInterval) { current.addTimeInterval(seconds) }
}


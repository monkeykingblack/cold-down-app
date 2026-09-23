import Foundation

public protocol SensorProvider: Sendable {
    func readSensors() async throws -> SensorBatch
}

public protocol FanDevice: Sendable {
    func state() async -> FanDeviceState
}

public protocol BuiltInFanReader: Sendable {
    func listFans() async throws -> [FanDeviceState]
}

public protocol BuiltInFanController: Sendable {
    func listFans() async throws -> [FanDeviceState]
    func setAuto(fanID: String) async throws
    func setTargetRPM(fanID: String, rpm: Int) async throws -> Int
    func restoreAllToAuto() async
}

public struct AcknowledgedTarget: Codable, Equatable, Sendable {
    public let target: Int
    public let acknowledgedAt: Date
    public init(target: Int, acknowledgedAt: Date) {
        self.target = target
        self.acknowledgedAt = acknowledgedAt
    }
}

public protocol ExternalCoolerController: FanDevice {
    func connect() async
    func setTarget(_ speed: Int) async throws -> AcknowledgedTarget
    /// Returns the device to its own control mode (called on shutdown).
    func releaseControl() async
}

extension ExternalCoolerController {
    public func releaseControl() async {}
}

public protocol PrivilegedFanHelperClient: BuiltInFanController {
    func status() async -> HelperStatus
    func renewLease() async throws -> Date
}

public protocol ProfileStore: Sendable {
    func load() async -> AppPreferences
    func save(_ preferences: AppPreferences) async throws
}


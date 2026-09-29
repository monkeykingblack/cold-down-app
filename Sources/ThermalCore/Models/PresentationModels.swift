import Foundation

public struct FanConfigurationState: Sendable {
    public let fan: FanDeviceState
    public private(set) var profile: FanProfile

    public init(fan: FanDeviceState, profile: FanProfile) {
        self.fan = fan
        self.profile = profile.validated(for: fan)
    }

    public var controlsEnabled: Bool { fan.connection == .connected && fan.writeAvailability == .ready }
    public mutating func setMode(_ mode: FanControlMode) { profile.mode = mode }
    public mutating func setThreshold(_ value: Int) { profile.thresholdCelsius = min(max(value, 45), 85) }
    public mutating func setManualTarget(_ value: Int) {
        profile.manualTarget = fan.capabilities?.clamped(value) ?? value
    }
}

public struct MenuBarPresentation: Equatable, Sendable {
    public let label: String
    public let hottestDescription: String
    public let externalSummary: String
    public let overallMode: String

    public init(snapshot: CoolingSnapshot, showTemperature: Bool) {
        if showTemperature, let hottest = snapshot.sensors.hottestReading?.valueCelsius {
            label = "\(Int(hottest.rounded()))°"
        } else { label = "" }
        if let hottest = snapshot.sensors.hottestReading, let value = hottest.valueCelsius {
            hottestDescription = "\(hottest.identity.name) · \(Int(value.rounded()))°C"
        } else { hottestDescription = "No valid temperature" }
        if let external = snapshot.fans.first {
            externalSummary = external.connection == .connected
                ? "\(external.name): \(Self.speed(external) ?? "Connected")"
                : "\(external.name): Disconnected"
        } else { externalSummary = "Flydigi BS3 Pro: Disconnected" }
        overallMode = snapshot.overallMode.rawValue
    }

    private static func speed(_ fan: FanDeviceState) -> String? {
        fan.currentSpeed.map { "\($0) \(fan.capabilities?.unit ?? "RPM")" }
    }
}


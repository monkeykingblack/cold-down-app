import Foundation

public struct AppPreferences: Codable, Equatable, Sendable {
    public static let schemaVersion = 1
    public var schemaVersion: Int
    public var profiles: [String: FanProfile]
    public var refreshInterval: TimeInterval
    public var showTemperatureInMenuBar: Bool
    public var launchAtLogin: Bool
    public var automaticFlydigiReconnect: Bool

    public init(
        schemaVersion: Int = AppPreferences.schemaVersion,
        profiles: [String: FanProfile] = [:],
        refreshInterval: TimeInterval = 5,
        showTemperatureInMenuBar: Bool = true,
        launchAtLogin: Bool = false,
        automaticFlydigiReconnect: Bool = true
    ) {
        self.schemaVersion = schemaVersion
        self.profiles = profiles
        self.refreshInterval = min(max(refreshInterval, 1), 30)
        self.showTemperatureInMenuBar = showTemperatureInMenuBar
        self.launchAtLogin = launchAtLogin
        self.automaticFlydigiReconnect = automaticFlydigiReconnect
    }

    public static let defaults = AppPreferences()
}

public enum OverallControlMode: String, Codable, Sendable {
    case readOnly = "Read only"
    case automatic = "Automatic"
    case manual = "Manual"
    case safetyFallback = "Safety fallback"
}

public struct CoolingSnapshot: Codable, Sendable {
    public let sensors: SensorSummary
    public let fans: [FanDeviceState]
    public let profiles: [String: FanProfile]
    public let overallMode: OverallControlMode
    public let lastDecision: CoolingDecision?
    public let generatedAt: Date

    public init(
        sensors: SensorSummary,
        fans: [FanDeviceState],
        profiles: [String: FanProfile],
        overallMode: OverallControlMode,
        lastDecision: CoolingDecision?,
        generatedAt: Date
    ) {
        self.sensors = sensors
        self.fans = fans
        self.profiles = profiles
        self.overallMode = overallMode
        self.lastDecision = lastDecision
        self.generatedAt = generatedAt
    }

    public func withProfiles(_ profiles: [String: FanProfile]) -> CoolingSnapshot {
        CoolingSnapshot(
            sensors: sensors, fans: fans, profiles: profiles,
            overallMode: overallMode, lastDecision: lastDecision, generatedAt: generatedAt
        )
    }

    public static var empty: CoolingSnapshot {
        CoolingSnapshot(
            sensors: .empty(), fans: [], profiles: [:],
            overallMode: .readOnly, lastDecision: nil, generatedAt: Date()
        )
    }
}


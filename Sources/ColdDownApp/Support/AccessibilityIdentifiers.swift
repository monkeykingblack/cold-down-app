import Foundation

enum AccessibilityID {
    static let root = "thermal.root"
    static let tabs = "thermal.tabs"
    static let hottest = "thermal.hottest"
    static let unavailableTemperature = "thermal.temperature.unavailable"
    static let fanPrefix = "thermal.fan."
    // Per-fan, because the Fans page shows every fan's controls at once.
    static func fanMode(_ fanID: String) -> String { "thermal.fan.mode.\(fanID)" }
    static func autoSensor(_ fanID: String) -> String { "thermal.fan.auto.sensor.\(fanID)" }
    static func thresholdSlider(_ fanID: String) -> String { "thermal.fan.auto.threshold.slider.\(fanID)" }
    static func thresholdField(_ fanID: String) -> String { "thermal.fan.auto.threshold.field.\(fanID)" }
    static func speedSlider(_ fanID: String) -> String { "thermal.fan.manual.speed.slider.\(fanID)" }
    static func speedField(_ fanID: String) -> String { "thermal.fan.manual.speed.field.\(fanID)" }
    static func fanConnectionMessage(_ fanID: String) -> String { "thermal.fan.connection.message.\(fanID)" }
    static func fanCard(_ fanID: String) -> String { "thermal.fan.card.\(fanID)" }
    static let menuBarPopover = "thermal.menubar.popover"
    static let menuBarHottest = "thermal.menubar.hottest"
    static let menuBarFanPrefix = "thermal.menubar.fan."
    static let menuBarFanModePrefix = "thermal.menubar.fan.mode."
    static let menuBarOpen = "thermal.menubar.open"
    static let menuBarQuit = "thermal.menubar.quit"
}

enum LaunchOption {
    static var mockMode: Bool { CommandLine.arguments.contains("--mock") }
    static var coolerDisconnected: Bool { CommandLine.arguments.contains("--cooler-disconnected") }
    static var noSensors: Bool { CommandLine.arguments.contains("--no-sensors") }
    static var capabilityLimitedCooler: Bool { CommandLine.arguments.contains("--capability-limited-cooler") }
    /// Hosted unit tests launch the real app; they must never touch the session marker or login item.
    static var runningTests: Bool { ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil }
}

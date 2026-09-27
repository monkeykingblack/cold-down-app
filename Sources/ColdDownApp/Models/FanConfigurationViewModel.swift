import Foundation
import ThermalCore

/// Holds the user's draft settings for one fan. The device state itself is refreshed from each snapshot
/// via `updateFan(_:)`, so connection, speed, limits, and write availability never go stale.
@MainActor
@Observable
final class FanConfigurationViewModel {
    private(set) var fan: FanDeviceState
    var mode: FanControlMode
    var selectedSensor: SensorSelection
    var threshold: Double
    var manualTarget: Double

    init(fan: FanDeviceState, profile: FanProfile) {
        self.fan = fan
        let profile = profile.validated(for: fan)
        mode = profile.mode
        selectedSensor = profile.selectedSensor
        threshold = Double(profile.thresholdCelsius)
        manualTarget = Double(profile.manualTarget)
    }

    var controlsEnabled: Bool { fan.connection == .connected && fan.writeAvailability == .ready }
    var minimumSpeed: Double { Double(fan.capabilities?.minimum ?? 0) }
    var maximumSpeed: Double { Double(fan.capabilities?.maximum ?? 1) }
    var speedStep: Double { Double(fan.capabilities?.step ?? 1) }

    func updateFan(_ latest: FanDeviceState) {
        guard latest != fan else { return }
        let limitsChanged = latest.capabilities != fan.capabilities
        fan = latest
        if limitsChanged, fan.capabilities != nil { setManualTarget(manualTarget) }
    }

    /// Adopts a profile changed elsewhere (e.g. the menu-bar popover). Returns true if anything changed.
    @discardableResult
    func adopt(_ external: FanProfile) -> Bool {
        let validated = external.validated(for: fan)
        guard validated != profile() else { return false }
        mode = validated.mode
        selectedSensor = validated.selectedSensor
        threshold = Double(validated.thresholdCelsius)
        manualTarget = Double(validated.manualTarget)
        return true
    }

    func setThreshold(_ value: Double) {
        threshold = min(max(value.rounded(), 45), 85)
    }

    func setManualTarget(_ value: Double) {
        manualTarget = min(max(value, minimumSpeed), maximumSpeed)
    }

    func profile() -> FanProfile {
        FanProfile(
            mode: mode, selectedSensor: selectedSensor,
            thresholdCelsius: min(max(Int(threshold.rounded()), 45), 85),
            manualTarget: fan.capabilities?.clamped(Int(manualTarget.rounded())) ?? Int(manualTarget.rounded())
        )
    }
}

import XCTest
import ThermalCore
@testable import ColdDownApp

@MainActor
final class FanConfigurationViewModelTests: XCTestCase {
    func testSliderAndNumericValuesShareValidatedState() {
        let fan = FanDeviceState(
            id: "external", name: "BS3 Pro", connection: .connected,
            currentSpeed: 2_000,
            capabilities: SpeedCapabilities(minimum: 1_200, maximum: 5_000, step: 10, provenance: .deterministicMock),
            writeAvailability: .ready
        )
        let model = FanConfigurationViewModel(fan: fan, profile: FanProfile())
        model.setThreshold(100)
        model.setManualTarget(9_000)
        XCTAssertEqual(model.threshold, 85)
        XCTAssertEqual(model.manualTarget, 5_000)
        let profile = model.profile()
        XCTAssertEqual(profile.thresholdCelsius, 85)
        XCTAssertEqual(profile.manualTarget, 5_000)
    }

    func testDisconnectedAndCapabilityLimitedStatesDisableControls() {
        let disconnected = FanDeviceState(
            id: "external", name: "BS3 Pro", connection: .disconnected,
            writeAvailability: .disconnected
        )
        XCTAssertFalse(FanConfigurationViewModel(fan: disconnected, profile: FanProfile()).controlsEnabled)
        let limited = FanDeviceState(
            id: "external", name: "BS3 Pro", connection: .connected,
            capabilities: SpeedCapabilities(minimum: 1_300, maximum: 4_000, provenance: .unverified),
            writeAvailability: .capabilityLimited
        )
        XCTAssertFalse(FanConfigurationViewModel(fan: limited, profile: FanProfile()).controlsEnabled)
    }

    func testLiveDeviceUpdatesEnableControlsAndReclampTarget() {
        let limited = FanDeviceState(
            id: "external", name: "BS3 Pro", connection: .connected, currentSpeed: 2_000,
            capabilities: SpeedCapabilities(minimum: 1_200, maximum: 5_000, provenance: .unverified),
            writeAvailability: .capabilityLimited
        )
        let model = FanConfigurationViewModel(fan: limited, profile: FanProfile(manualTarget: 4_800))
        XCTAssertFalse(model.controlsEnabled)
        var ready = limited
        ready.writeAvailability = .ready
        ready.capabilities = SpeedCapabilities(minimum: 1_200, maximum: 4_000, provenance: .deterministicMock)
        model.updateFan(ready)
        XCTAssertTrue(model.controlsEnabled)
        XCTAssertEqual(model.manualTarget, 4_000)
    }
}

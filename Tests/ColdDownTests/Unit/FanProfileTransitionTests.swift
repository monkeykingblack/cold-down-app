import XCTest
import ThermalCore

final class FanProfileTransitionTests: XCTestCase {
    func testTypedValuesClampToCapabilities() {
        var state = FanConfigurationState(fan: Fixtures.external(), profile: FanProfile())
        state.setThreshold(100); XCTAssertEqual(state.profile.thresholdCelsius, 85)
        state.setThreshold(10); XCTAssertEqual(state.profile.thresholdCelsius, 45)
        state.setManualTarget(0); XCTAssertEqual(state.profile.manualTarget, 1_300)
        state.setManualTarget(99_000); XCTAssertEqual(state.profile.manualTarget, 4_000)
    }

    func testDisconnectedAndCapabilityLimitedControlsAreDisabled() {
        XCTAssertFalse(FanConfigurationState(fan: Fixtures.external(availability: .disconnected), profile: FanProfile()).controlsEnabled)
        XCTAssertFalse(FanConfigurationState(fan: Fixtures.external(availability: .capabilityLimited), profile: FanProfile()).controlsEnabled)
    }
}


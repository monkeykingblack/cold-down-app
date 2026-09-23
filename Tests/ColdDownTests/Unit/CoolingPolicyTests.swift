import XCTest
import ThermalCore

final class CoolingPolicyTests: XCTestCase {
    private let policy = CoolingPolicy()

    func testCoolVerifiedStopMinimumAndCapabilityLimitedBranches() {
        let fan = Fixtures.builtIn()
        let summary = Fixtures.summary([Fixtures.reading("TC0P", 40)])
        let profile = FanProfile(selectedSensor: .physical("smc:TC0P"), thresholdCelsius: 45)

        let stop = evaluate(summary, fan, profile, Fixtures.external(stop: true))
        XCTAssertEqual(stop.externalAction, .stop)
        let minimum = evaluate(summary, fan, profile, Fixtures.external())
        XCTAssertEqual(minimum.externalAction, .target(1_300, requiresAcknowledgement: false))
        let limited = evaluate(summary, fan, profile, Fixtures.external(availability: .capabilityLimited))
        XCTAssertEqual(limited.externalAction, .none)
    }

    func testWarmAndHotInterpolationBoundaries() {
        let fan = Fixtures.builtIn(current: 1_200)
        let profile = FanProfile(selectedSensor: .physical("smc:TC0P"), thresholdCelsius: 72)
        let warm = evaluate(Fixtures.summary([Fixtures.reading("TC0P", 77)]), fan, profile, Fixtures.external())
        XCTAssertEqual(warm.band, .warm)
        XCTAssertEqual(warm.externalAction, .target(2_700, requiresAcknowledgement: false))
        XCTAssertEqual(warm.builtInActions[fan.id], .automatic)

        let hot = evaluate(Fixtures.summary([Fixtures.reading("TC0P", 90)]), fan, profile, Fixtures.external())
        XCTAssertEqual(hot.band, .hot)
        XCTAssertEqual(hot.externalAction, .target(4_000, requiresAcknowledgement: true))
        guard case let .target(target, requiresACK) = hot.builtInActions[fan.id] else { return XCTFail("Missing hot target") }
        XCTAssertTrue(requiresACK); XCTAssertGreaterThan(target, 1_200); XCTAssertLessThan(target, 5_000)
    }

    func testHotTargetFollowsTemperatureDownOnceFanIsUnderControl() {
        var fan = Fixtures.builtIn(current: 4_500)
        fan.reportedMode = .manual  // current speed only echoes our previous target
        let profile = FanProfile(selectedSensor: .physical("smc:TC0P"), thresholdCelsius: 72)
        let decision = evaluate(Fixtures.summary([Fixtures.reading("TC0P", 83)]), fan, profile, Fixtures.external())
        guard case let .target(target, _) = decision.builtInActions[fan.id] else { return XCTFail("Missing hot target") }
        XCTAssertLessThan(target, 4_500)
    }

    func testHotTargetNeverUndercutsSystemAutoSpeed() {
        var fan = Fixtures.builtIn(current: 4_500)
        fan.reportedMode = .auto
        let profile = FanProfile(selectedSensor: .physical("smc:TC0P"), thresholdCelsius: 72)
        let decision = evaluate(Fixtures.summary([Fixtures.reading("TC0P", 83)]), fan, profile, Fixtures.external())
        guard case let .target(target, _) = decision.builtInActions[fan.id] else { return XCTFail("Missing hot target") }
        XCTAssertEqual(target, 4_500)
    }

    func testHighestDemandWinsAndAnyFreshSensorCanTriggerCritical() {
        let first = Fixtures.builtIn(id: "builtin:0")
        let second = Fixtures.builtIn(id: "builtin:1")
        let summary = Fixtures.summary([
            Fixtures.reading("TC0P", 75),
            Fixtures.reading("TG0P", 90, group: .gpu),
            Fixtures.reading("TH0H", 95, group: .heatsink)
        ])
        let profiles = [
            first.id: FanProfile(selectedSensor: .physical("smc:TC0P"), thresholdCelsius: 72),
            second.id: FanProfile(selectedSensor: .physical("smc:TG0P"), thresholdCelsius: 72)
        ]
        let decision = policy.evaluate(summary: summary, fanStates: [first, second], profiles: profiles, helperStatus: .healthy, externalState: Fixtures.external(), now: Fixtures.now)
        XCTAssertEqual(decision.band, .critical)
        XCTAssertTrue(decision.builtInActions.values.allSatisfy { $0 == .automatic })
    }

    func testStaleSelectedSourceUsesSafetyFallback() {
        let fan = Fixtures.builtIn()
        let summary = Fixtures.summary([Fixtures.reading("TC0P", 80, state: .stale)])
        let decision = evaluate(summary, fan, FanProfile(selectedSensor: .physical("smc:TC0P")), Fixtures.external())
        XCTAssertEqual(decision.band, .safetyFallback)
        XCTAssertEqual(decision.externalAction, .target(4_000, requiresAcknowledgement: false))
        XCTAssertEqual(decision.builtInActions[fan.id], .automatic)
    }

    private func evaluate(_ summary: SensorSummary, _ fan: FanDeviceState, _ profile: FanProfile, _ external: FanDeviceState) -> CoolingDecision {
        policy.evaluate(summary: summary, fanStates: [fan], profiles: [fan.id: profile], helperStatus: .healthy, externalState: external, now: Fixtures.now)
    }
}


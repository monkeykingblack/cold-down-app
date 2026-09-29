import XCTest
import ThermalCore

final class CoolingPolicyTests: XCTestCase {
    private let policy = CoolingPolicy()
    private let profile = FanProfile(selectedSensor: .physical("smc:TC0P"), thresholdCelsius: 72)

    func testCoolVerifiedStopMinimumAndCapabilityLimitedBranches() {
        let summary = Fixtures.summary([Fixtures.reading("TC0P", 40)])
        let profile = FanProfile(selectedSensor: .physical("smc:TC0P"), thresholdCelsius: 45)

        let stop = evaluate(summary, profile, Fixtures.external(stop: true))
        XCTAssertEqual(stop.externalAction, .stop)
        let minimum = evaluate(summary, profile, Fixtures.external())
        XCTAssertEqual(minimum.externalAction, .target(1_300))
        let limited = evaluate(summary, profile, Fixtures.external(availability: .capabilityLimited))
        XCTAssertEqual(limited.externalAction, .none)
    }

    func testCoolerRampsAcrossTheWarmBandAndHoldsMaximumOnceHot() {
        let cool = evaluate(Fixtures.summary([Fixtures.reading("TC0P", 60)]), profile, Fixtures.external())
        XCTAssertEqual(cool.band, .cool)
        XCTAssertEqual(cool.externalAction, .target(1_300))

        // 77 °C is halfway from the 72 °C threshold to the 82 °C hot boundary.
        let warm = evaluate(Fixtures.summary([Fixtures.reading("TC0P", 77)]), profile, Fixtures.external())
        XCTAssertEqual(warm.band, .warm)
        XCTAssertEqual(warm.externalAction, .target(2_700))
        XCTAssertEqual(warm.demand?.normalizedProgress, 0.5)

        let hot = evaluate(Fixtures.summary([Fixtures.reading("TC0P", 90)]), profile, Fixtures.external())
        XCTAssertEqual(hot.band, .hot)
        XCTAssertEqual(hot.externalAction, .target(4_000))
    }

    func testProfilesForOtherDeviceIDsDoNotAffectTheCooler() {
        // A profile saved under another device id must not create a demand of its own.
        let external = Fixtures.external()
        let profiles = [
            "other:0": FanProfile(selectedSensor: .physical("smc:TG0P"), thresholdCelsius: 45),
            external.id: profile
        ]
        let summary = Fixtures.summary([Fixtures.reading("TC0P", 60), Fixtures.reading("TG0P", 90, group: .gpu)])
        let decision = policy.evaluate(summary: summary, profiles: profiles, externalState: external, now: Fixtures.now)
        XCTAssertEqual(decision.band, .cool)
        XCTAssertEqual(decision.externalAction, .target(1_300))
        XCTAssertEqual(decision.demand?.fanID, external.id)
    }

    func testCoolerWithoutASavedProfileFollowsTheSuggestedDefault() {
        let external = Fixtures.external()
        // The default follows the CPU average with a 65 °C threshold: 70 °C is halfway through the warm band.
        let warm = policy.evaluate(
            summary: Fixtures.summary([Fixtures.reading("TC0P", 70)]), profiles: [:], externalState: external, now: Fixtures.now
        )
        XCTAssertEqual(warm.band, .warm)
        XCTAssertEqual(warm.externalAction, .target(2_700))
        // Without a CPU sensor the hottest reading is followed instead of falling back to full speed.
        let noCPU = policy.evaluate(
            summary: Fixtures.summary([Fixtures.reading("TG0P", 50, group: .gpu)]), profiles: [:], externalState: external, now: Fixtures.now
        )
        XCTAssertEqual(noCPU.band, .cool)
        XCTAssertEqual(noCPU.externalAction, .target(1_300))
    }

    func testAnyFreshSensorCanTriggerCritical() {
        let summary = Fixtures.summary([
            Fixtures.reading("TC0P", 60),
            Fixtures.reading("TH0H", 95, group: .heatsink)
        ])
        let decision = evaluate(summary, profile, Fixtures.external())
        XCTAssertEqual(decision.band, .critical)
        XCTAssertEqual(decision.externalAction, .target(4_000))
        // Critical is reported even when the cooler cannot be driven.
        let disconnected = evaluate(summary, profile, Fixtures.external(availability: .disconnected))
        XCTAssertEqual(disconnected.band, .critical)
        XCTAssertEqual(disconnected.externalAction, .none)
    }

    func testManualProfileHoldsItsOwnTarget() {
        let external = Fixtures.external()
        let manual = FanProfile(mode: .manual, selectedSensor: .physical("smc:TC0P"), manualTarget: 2_500)
        let cool = evaluate(Fixtures.summary([Fixtures.reading("TC0P", 40)]), manual, external)
        XCTAssertEqual(cool.externalAction, .target(2_500))
        let hot = evaluate(Fixtures.summary([Fixtures.reading("TC0P", 90)]), manual, external)
        XCTAssertEqual(hot.externalAction, .target(2_500))
        // Targets are snapped to the cooler's range and step.
        let outOfRange = evaluate(Fixtures.summary([Fixtures.reading("TC0P", 40)]), FanProfile(mode: .manual, manualTarget: 9_000), external)
        XCTAssertEqual(outOfRange.externalAction, .target(4_000))
    }

    func testManualProfileStillYieldsToCriticalTemperature() {
        let manual = FanProfile(mode: .manual, selectedSensor: .physical("smc:TC0P"), manualTarget: 1_500)
        let decision = evaluate(Fixtures.summary([Fixtures.reading("TC0P", 96)]), manual, Fixtures.external())
        XCTAssertEqual(decision.band, .critical)
        XCTAssertEqual(decision.externalAction, .target(4_000))
    }

    func testStaleSelectedSourceUsesSafetyFallback() {
        let summary = Fixtures.summary([Fixtures.reading("TC0P", 80, state: .stale)])
        let decision = evaluate(summary, FanProfile(selectedSensor: .physical("smc:TC0P")), Fixtures.external())
        XCTAssertEqual(decision.band, .safetyFallback)
        XCTAssertEqual(decision.externalAction, .target(4_000))
    }

    func testNothingToDriveIsCoolWithNoAction() {
        let summary = Fixtures.summary([Fixtures.reading("TC0P", 80, state: .stale)])
        let absent = policy.evaluate(summary: summary, profiles: [:], externalState: nil, now: Fixtures.now)
        XCTAssertEqual(absent.band, .cool)
        XCTAssertEqual(absent.externalAction, .none)
        let disconnected = evaluate(summary, profile, Fixtures.external(availability: .disconnected))
        XCTAssertEqual(disconnected.band, .cool)
        XCTAssertEqual(disconnected.externalAction, .none)
    }

    private func evaluate(_ summary: SensorSummary, _ profile: FanProfile, _ external: FanDeviceState) -> CoolingDecision {
        policy.evaluate(summary: summary, profiles: [external.id: profile], externalState: external, now: Fixtures.now)
    }
}

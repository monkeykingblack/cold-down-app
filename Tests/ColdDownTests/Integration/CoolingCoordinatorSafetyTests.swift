import XCTest
import ThermalCore

final class CoolingCoordinatorSafetyTests: XCTestCase {
    private let coolerID = "flydigi:37d7:1004"

    func testHotTemperatureDrivesTheCoolerToMaximum() async {
        let external = MockExternalController(Fixtures.external())
        let preferences = AppPreferences(profiles: [
            coolerID: FanProfile(selectedSensor: .physical("smc:TC0P"), thresholdCelsius: 72)
        ])
        let coordinator = makeCoordinator(temp: 90, external: external, preferences: preferences)
        await coordinator.start()
        let targets = await external.recordedTargets()
        XCTAssertEqual(Set(targets), [4_000])
        let snapshot = await coordinator.snapshot()
        XCTAssertEqual(snapshot.overallMode, .automatic)
        await coordinator.shutdown()
    }

    func testCapabilityLimitedCoolerIsNeverWritten() async {
        let external = MockExternalController(Fixtures.external(availability: .capabilityLimited))
        let preferences = AppPreferences(profiles: [coolerID: FanProfile(selectedSensor: .physical("smc:TC0P"), thresholdCelsius: 72)])
        let coordinator = makeCoordinator(temp: 90, external: external, preferences: preferences)
        await coordinator.start()
        let targets = await external.recordedTargets()
        XCTAssertTrue(targets.isEmpty)
        let snapshot = await coordinator.snapshot()
        XCTAssertEqual(snapshot.overallMode, .readOnly)
        await coordinator.shutdown()
    }

    func testFailedCoolerWriteIsSurvivedAndRetriedNextRefresh() async {
        let external = MockExternalController(Fixtures.external())
        await external.setFailure(true)
        let preferences = AppPreferences(profiles: [coolerID: FanProfile(selectedSensor: .physical("smc:TC0P"), thresholdCelsius: 72)])
        let coordinator = makeCoordinator(temp: 90, external: external, preferences: preferences)
        await coordinator.start()
        await external.setFailure(false)
        await coordinator.refreshNow()
        let targets = await external.recordedTargets()
        XCTAssertEqual(Set(targets), [4_000])
        XCTAssertGreaterThanOrEqual(targets.count, 2, "The failed write is retried on the next refresh")
        await coordinator.shutdown()
    }

    func testStaleSourceRequestsExternalMaximumAndReportsFallback() async {
        let external = MockExternalController(Fixtures.external())
        let stale = Fixtures.reading("TC0P", 80, state: .stale)
        let provider = MockSensorProvider([SensorBatch(generation: 1, sampledAt: Fixtures.now, readings: [stale])])
        let preferences = AppPreferences(profiles: [coolerID: FanProfile(selectedSensor: .physical("smc:TC0P"))])
        let coordinator = CoolingCoordinator(
            sensorProvider: provider,
            externalController: external,
            profileStore: MemoryProfileStore(preferences), clock: ManualThermalClock(now: Fixtures.now)
        )
        await coordinator.start()
        let targets = await external.recordedTargets()
        XCTAssertEqual(Set(targets), [4_000])
        let snapshot = await coordinator.snapshot()
        XCTAssertEqual(snapshot.overallMode, .safetyFallback)
        await coordinator.shutdown()
    }

    func testShutdownReleasesTheCooler() async {
        let external = ReleaseRecordingController(Fixtures.external())
        let coordinator = makeCoordinator(temp: 50, external: external, preferences: .defaults)
        await coordinator.start()
        await coordinator.shutdown()
        let released = await external.releaseCount
        XCTAssertEqual(released, 1)
    }

    func testConcurrentRefreshRequestsAreCoalesced() async {
        let provider = SlowCountingSensorProvider(batch: SensorBatch(generation: 1, sampledAt: Fixtures.now, readings: [Fixtures.reading("TC0P", 50)]))
        let coordinator = CoolingCoordinator(
            sensorProvider: provider, profileStore: MemoryProfileStore(), clock: ManualThermalClock(now: Fixtures.now)
        )
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<10 { group.addTask { await coordinator.refreshNow() } }
        }
        let reads = await provider.reads
        XCTAssertLessThanOrEqual(reads, 3, "Overlapping refreshes must collapse into one follow-up pass")
        XCTAssertGreaterThanOrEqual(reads, 1)
    }

    func testSnapshotUpdatesDeliverEachRefresh() async {
        let coordinator = makeCoordinator(temp: 50, external: MockExternalController(Fixtures.external()), preferences: .defaults)
        var iterator = await coordinator.snapshotUpdates().makeAsyncIterator()
        let initial = await iterator.next()
        XCTAssertEqual(initial?.fans.count, 0)
        await coordinator.refreshNow()
        let refreshed = await iterator.next()
        XCTAssertEqual(refreshed?.fans.count, 1)
    }

    func testUncleanExitRevertsManualProfilesToAutoButKeepsTargets() async {
        let external = MockExternalController(Fixtures.external())
        let store = MemoryProfileStore(AppPreferences(profiles: [
            coolerID: FanProfile(mode: .manual, manualTarget: 3_000)
        ]))
        let coordinator = CoolingCoordinator(
            sensorProvider: MockSensorProvider([SensorBatch(generation: 1, sampledAt: Fixtures.now, readings: [Fixtures.reading("TC0P", 50)])]),
            externalController: external,
            profileStore: store, clock: ManualThermalClock(now: Fixtures.now)
        )
        let reverted = await coordinator.start(revertManualProfiles: true)
        XCTAssertTrue(reverted)
        let saved = await store.load()
        XCTAssertEqual(saved.profiles[coolerID]?.mode, .auto)
        XCTAssertEqual(saved.profiles[coolerID]?.manualTarget, 3_000)
        let targets = await external.recordedTargets()
        XCTAssertFalse(targets.contains(3_000), "No manual speed after a crash")
        await coordinator.shutdown()
    }

    func testCleanStartKeepsManualProfiles() async {
        let external = MockExternalController(Fixtures.external())
        let store = MemoryProfileStore(AppPreferences(profiles: [coolerID: FanProfile(mode: .manual, manualTarget: 3_000)]))
        let coordinator = CoolingCoordinator(
            sensorProvider: MockSensorProvider([SensorBatch(generation: 1, sampledAt: Fixtures.now, readings: [Fixtures.reading("TC0P", 50)])]),
            externalController: external,
            profileStore: store, clock: ManualThermalClock(now: Fixtures.now)
        )
        let reverted = await coordinator.start()
        XCTAssertFalse(reverted)
        let saved = await store.load()
        XCTAssertEqual(saved.profiles[coolerID]?.mode, .manual)
        let targets = await external.recordedTargets()
        XCTAssertEqual(Set(targets), [3_000])
        let snapshot = await coordinator.snapshot()
        XCTAssertEqual(snapshot.overallMode, .manual)
        await coordinator.shutdown()
    }

    func testSettingsWriteBeforeStartKeepsStoredProfiles() async {
        let store = MemoryProfileStore(AppPreferences(profiles: [coolerID: FanProfile(thresholdCelsius: 60)]))
        let coordinator = CoolingCoordinator(
            sensorProvider: MockSensorProvider([SensorBatch(generation: 1, sampledAt: Fixtures.now, readings: [Fixtures.reading("TC0P", 50)])]),
            profileStore: store, clock: ManualThermalClock(now: Fixtures.now)
        )
        // The app syncs launch-at-login from its not-yet-loaded defaults, whose profiles are empty.
        await coordinator.updatePreferences(AppPreferences(launchAtLogin: true))
        await coordinator.start()
        let saved = await store.load()
        XCTAssertEqual(saved.profiles[coolerID]?.thresholdCelsius, 60)
        XCTAssertTrue(saved.launchAtLogin)
        await coordinator.shutdown()
    }

    func testSettingsWriteKeepsProfilesChangedSinceTheCallerLoaded() async {
        let store = MemoryProfileStore()
        let coordinator = CoolingCoordinator(
            sensorProvider: MockSensorProvider([SensorBatch(generation: 1, sampledAt: Fixtures.now, readings: [Fixtures.reading("TC0P", 50)])]),
            profileStore: store, clock: ManualThermalClock(now: Fixtures.now)
        )
        await coordinator.start()
        let callerCopy = await coordinator.currentPreferences()
        await coordinator.updateProfile(fanID: coolerID, profile: FanProfile(thresholdCelsius: 60))
        var changed = callerCopy
        changed.refreshInterval = 10
        await coordinator.updatePreferences(changed)
        let saved = await store.load()
        XCTAssertEqual(saved.profiles[coolerID]?.thresholdCelsius, 60)
        XCTAssertEqual(saved.refreshInterval, 10)
        await coordinator.shutdown()
    }

    private func makeCoordinator(
        temp: Double, external: any ExternalCoolerController, preferences: AppPreferences
    ) -> CoolingCoordinator {
        let batch = SensorBatch(generation: 1, sampledAt: Fixtures.now, readings: [Fixtures.reading("TC0P", temp)])
        return CoolingCoordinator(
            sensorProvider: MockSensorProvider([batch]),
            externalController: external,
            profileStore: MemoryProfileStore(preferences), clock: ManualThermalClock(now: Fixtures.now)
        )
    }
}

private actor SlowCountingSensorProvider: SensorProvider {
    let batch: SensorBatch
    private(set) var reads = 0
    init(batch: SensorBatch) { self.batch = batch }
    func readSensors() async throws -> SensorBatch {
        reads += 1
        try await Task.sleep(for: .milliseconds(30))
        return batch
    }
}

private actor ReleaseRecordingController: ExternalCoolerController {
    let fanState: FanDeviceState
    private(set) var releaseCount = 0
    init(_ state: FanDeviceState) { fanState = state }
    func state() -> FanDeviceState { fanState }
    func connect() {}
    func setTarget(_ speed: Int) -> AcknowledgedTarget { AcknowledgedTarget(target: speed, acknowledgedAt: Fixtures.now) }
    func releaseControl() { releaseCount += 1 }
}

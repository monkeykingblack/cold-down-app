import XCTest
import ThermalCore

final class CoolingCoordinatorSafetyTests: XCTestCase {
    func testWriteReadyExternalPrecedesHotBuiltInIncrease() async {
        let recorder = EventRecorder()
        let fan = Fixtures.builtIn(current: 1_200)
        let builtIn = MockBuiltInController([fan], recorder: recorder)
        let external = MockExternalController(Fixtures.external(), recorder: recorder)
        let preferences = AppPreferences(profiles: [
            fan.id: FanProfile(selectedSensor: .physical("smc:TC0P"), thresholdCelsius: 72)
        ])
        let coordinator = makeCoordinator(temp: 90, fan: fan, builtIn: builtIn, external: external, preferences: preferences)
        await coordinator.start()
        let events = await recorder.values()
        XCTAssertLessThan(events.firstIndex(of: "external")!, events.firstIndex(of: "internal")!)
        await coordinator.shutdown()
    }

    func testFailedRequiredACKSuppressesBuiltInIncrease() async {
        let fan = Fixtures.builtIn(current: 1_200)
        let builtIn = MockBuiltInController([fan])
        let external = MockExternalController(Fixtures.external())
        await external.setFailure(true)
        let preferences = AppPreferences(profiles: [fan.id: FanProfile(selectedSensor: .physical("smc:TC0P"), thresholdCelsius: 72)])
        let coordinator = makeCoordinator(temp: 90, fan: fan, builtIn: builtIn, external: external, preferences: preferences)
        await coordinator.start()
        let actions = await builtIn.recorded()
        XCTAssertFalse(actions.contains { if case .target = $0 { true } else { false } })
        await coordinator.shutdown()
    }

    func testCapabilityLimitedCoolerDoesNotBlockHotBuiltInIncrease() async {
        let fan = Fixtures.builtIn(current: 1_200)
        let builtIn = MockBuiltInController([fan])
        let external = MockExternalController(Fixtures.external(availability: .capabilityLimited))
        let preferences = AppPreferences(profiles: [fan.id: FanProfile(selectedSensor: .physical("smc:TC0P"), thresholdCelsius: 72)])
        let coordinator = makeCoordinator(temp: 90, fan: fan, builtIn: builtIn, external: external, preferences: preferences)
        await coordinator.start()
        let actions = await builtIn.recorded()
        let targets = await external.recordedTargets()
        XCTAssertTrue(actions.contains { if case .target = $0 { true } else { false } })
        XCTAssertTrue(targets.isEmpty)
        await coordinator.shutdown()
    }

    func testStaleSourceRequestsExternalMaximumAndRestoresBuiltIns() async {
        let fan = Fixtures.builtIn()
        let builtIn = MockBuiltInController([fan])
        let external = MockExternalController(Fixtures.external())
        let stale = Fixtures.reading("TC0P", 80, state: .stale)
        let provider = MockSensorProvider([SensorBatch(generation: 1, sampledAt: Fixtures.now, readings: [stale])])
        let preferences = AppPreferences(profiles: [fan.id: FanProfile(selectedSensor: .physical("smc:TC0P"))])
        let helper = MockHelperClient(controller: builtIn)
        let coordinator = CoolingCoordinator(
            sensorProvider: provider, fanReader: MockFanReader([fan]), builtInController: builtIn,
            externalController: external, helperClient: helper,
            profileStore: MemoryProfileStore(preferences), clock: ManualThermalClock(now: Fixtures.now)
        )
        await coordinator.start()
        let targets = await external.recordedTargets()
        let actions = await builtIn.recorded()
        XCTAssertEqual(targets, [4_000])
        XCTAssertTrue(actions.contains(.restore))
        await coordinator.shutdown()
    }

    func testConcurrentRefreshRequestsAreCoalesced() async {
        let fan = Fixtures.builtIn()
        let provider = SlowCountingSensorProvider(batch: SensorBatch(generation: 1, sampledAt: Fixtures.now, readings: [Fixtures.reading("TC0P", 50)]))
        let coordinator = CoolingCoordinator(
            sensorProvider: provider, fanReader: MockFanReader([fan]),
            profileStore: MemoryProfileStore(), clock: ManualThermalClock(now: Fixtures.now)
        )
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<10 { group.addTask { await coordinator.refreshNow() } }
        }
        let reads = await provider.reads
        XCTAssertLessThanOrEqual(reads, 3, "Overlapping refreshes must collapse into one follow-up pass")
        XCTAssertGreaterThanOrEqual(reads, 1)
    }

    func testSnapshotUpdatesDeliverEachRefresh() async {
        let fan = Fixtures.builtIn()
        let coordinator = makeCoordinator(
            temp: 50, fan: fan, builtIn: MockBuiltInController([fan]),
            external: MockExternalController(Fixtures.external()), preferences: .defaults
        )
        var iterator = await coordinator.snapshotUpdates().makeAsyncIterator()
        let initial = await iterator.next()
        XCTAssertEqual(initial?.fans.count, 0)
        await coordinator.refreshNow()
        let refreshed = await iterator.next()
        XCTAssertEqual(refreshed?.fans.count, 2)
    }

    func testUncleanExitRevertsManualProfilesToAutoButKeepsTargets() async {
        let fan = Fixtures.builtIn()
        let store = MemoryProfileStore(AppPreferences(profiles: [
            fan.id: FanProfile(mode: .manual, manualTarget: 4_200),
            "flydigi:37d7:1004": FanProfile(mode: .manual, manualTarget: 3_000)
        ]))
        let builtIn = MockBuiltInController([fan])
        let coordinator = CoolingCoordinator(
            sensorProvider: MockSensorProvider([SensorBatch(generation: 1, sampledAt: Fixtures.now, readings: [Fixtures.reading("TC0P", 50)])]),
            fanReader: MockFanReader([fan]), builtInController: builtIn, helperClient: MockHelperClient(controller: builtIn),
            profileStore: store, clock: ManualThermalClock(now: Fixtures.now)
        )
        let reverted = await coordinator.start(revertManualProfiles: true)
        XCTAssertTrue(reverted)
        let saved = await store.load()
        XCTAssertTrue(saved.profiles.values.allSatisfy { $0.mode == .auto })
        XCTAssertEqual(saved.profiles[fan.id]?.manualTarget, 4_200)
        let actions = await builtIn.recorded()
        XCTAssertFalse(actions.contains { if case .target = $0 { true } else { false } }, "No manual speed after a crash")
        await coordinator.shutdown()
    }

    func testCleanStartKeepsManualProfiles() async {
        let fan = Fixtures.builtIn()
        let store = MemoryProfileStore(AppPreferences(profiles: [fan.id: FanProfile(mode: .manual, manualTarget: 4_200)]))
        let coordinator = CoolingCoordinator(
            sensorProvider: MockSensorProvider([SensorBatch(generation: 1, sampledAt: Fixtures.now, readings: [Fixtures.reading("TC0P", 50)])]),
            fanReader: MockFanReader([fan]), profileStore: store, clock: ManualThermalClock(now: Fixtures.now)
        )
        let reverted = await coordinator.start()
        XCTAssertFalse(reverted)
        let saved = await store.load()
        XCTAssertEqual(saved.profiles[fan.id]?.mode, .manual)
        await coordinator.shutdown()
    }

    func testFanTheHelperCannotControlStaysVisibleReadOnly() async {
        let left = Fixtures.builtIn(id: "builtin:0")
        var right = Fixtures.builtIn(id: "builtin:1")
        right.writeAvailability = .invalidCapabilities
        let helperFans = MockBuiltInController([left])  // helper only offers the controllable fan
        let coordinator = CoolingCoordinator(
            sensorProvider: MockSensorProvider([SensorBatch(generation: 1, sampledAt: Fixtures.now, readings: [Fixtures.reading("TC0P", 50)])]),
            fanReader: MockFanReader([left, right]), builtInController: helperFans,
            helperClient: MockHelperClient(controller: helperFans),
            profileStore: MemoryProfileStore(), clock: ManualThermalClock(now: Fixtures.now)
        )
        await coordinator.start()
        let fans = await coordinator.snapshot().fans
        XCTAssertEqual(fans.map(\.id), ["builtin:0", "builtin:1"])
        XCTAssertEqual(fans.last?.writeAvailability, .invalidCapabilities)
        await coordinator.shutdown()
    }

    private func makeCoordinator(
        temp: Double, fan: FanDeviceState, builtIn: MockBuiltInController,
        external: MockExternalController, preferences: AppPreferences
    ) -> CoolingCoordinator {
        let batch = SensorBatch(generation: 1, sampledAt: Fixtures.now, readings: [Fixtures.reading("TC0P", temp)])
        let helper = MockHelperClient(controller: builtIn)
        return CoolingCoordinator(
            sensorProvider: MockSensorProvider([batch]), fanReader: MockFanReader([fan]),
            builtInController: builtIn, externalController: external, helperClient: helper,
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

import XCTest
import ThermalCore

final class ReadOnlyMonitoringTests: XCTestCase {
    func testDisconnectedCoolerStillPublishesMonitoringSnapshot() async {
        let batch = SensorBatch(generation: 1, sampledAt: Fixtures.now, readings: [Fixtures.reading("TC0P", 65)])
        let external = MockExternalController(Fixtures.external(availability: .disconnected))
        let coordinator = CoolingCoordinator(
            sensorProvider: MockSensorProvider([batch]), externalController: external,
            profileStore: MemoryProfileStore(), clock: ManualThermalClock(now: Fixtures.now)
        )
        await coordinator.start()
        let snapshot = await coordinator.snapshot()
        XCTAssertEqual(snapshot.overallMode, .readOnly)
        XCTAssertEqual(snapshot.sensors.hottestReading?.valueCelsius, 65)
        XCTAssertEqual(snapshot.fans.count, 1)
        XCTAssertEqual(snapshot.fans.first?.connection, .disconnected)
        let targets = await external.recordedTargets()
        XCTAssertTrue(targets.isEmpty, "A disconnected cooler is never written to")
        await coordinator.shutdown()
    }

    func testNoRecognizedSensorsRemainsRepresentable() async {
        let batch = SensorBatch(generation: 1, sampledAt: Fixtures.now, readings: [])
        let coordinator = CoolingCoordinator(
            sensorProvider: MockSensorProvider([batch]),
            profileStore: MemoryProfileStore(), clock: ManualThermalClock(now: Fixtures.now)
        )
        await coordinator.start()
        let snapshot = await coordinator.snapshot()
        XCTAssertNil(snapshot.sensors.hottestReading)
        await coordinator.shutdown()
    }
}

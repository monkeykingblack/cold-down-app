import XCTest
import ThermalCore

final class ReadOnlyMonitoringTests: XCTestCase {
    func testNoHelperAndDisconnectedCoolerStillPublishMonitoringSnapshot() async {
        let batch = SensorBatch(generation: 1, sampledAt: Fixtures.now, readings: [Fixtures.reading("TC0P", 65)])
        let fan = FanDeviceState(
            id: "builtin:0", name: "Mac fan", kind: .builtIn, connection: .connected,
            currentSpeed: 2_000, capabilities: Fixtures.builtIn().capabilities,
            writeAvailability: .helperMissing
        )
        let coordinator = CoolingCoordinator(
            sensorProvider: MockSensorProvider([batch]), fanReader: MockFanReader([fan]),
            externalController: MockExternalController(Fixtures.external(availability: .disconnected)),
            profileStore: MemoryProfileStore(), clock: ManualThermalClock(now: Fixtures.now)
        )
        await coordinator.start()
        let snapshot = await coordinator.snapshot()
        XCTAssertEqual(snapshot.helperStatus, .unavailable)
        XCTAssertEqual(snapshot.sensors.hottestReading?.valueCelsius, 65)
        XCTAssertEqual(snapshot.fans.count, 2)
        await coordinator.shutdown()
    }

    func testNoRecognizedSensorsRemainsRepresentable() async {
        let batch = SensorBatch(generation: 1, sampledAt: Fixtures.now, readings: [])
        let coordinator = CoolingCoordinator(
            sensorProvider: MockSensorProvider([batch]), fanReader: MockFanReader([]),
            profileStore: MemoryProfileStore(), clock: ManualThermalClock(now: Fixtures.now)
        )
        await coordinator.start()
        let snapshot = await coordinator.snapshot()
        XCTAssertNil(snapshot.sensors.hottestReading)
        await coordinator.shutdown()
    }
}

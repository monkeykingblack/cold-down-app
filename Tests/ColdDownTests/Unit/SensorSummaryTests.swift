import XCTest
import ThermalCore

final class SensorSummaryTests: XCTestCase {
    func testAveragesAndHottestUseOnlyFreshValidReadings() {
        let summary = Fixtures.summary([
            Fixtures.reading("TC0P", 60), Fixtures.reading("TC1P", 70),
            Fixtures.reading("TG0P", 80, group: .gpu),
            Fixtures.reading("TB0T", 20, group: .battery),
            Fixtures.reading("TA0P", nil, group: .ambient, state: .invalid)
        ])
        XCTAssertEqual(summary.calculated[.cpuAverage], 65)
        XCTAssertEqual(summary.calculated[.gpuAverage], 80)
        XCTAssertEqual(summary.calculated[.allAverage], 57.5)
        XCTAssertEqual(summary.calculated[.hottest], 80)
        XCTAssertEqual(summary.hottestByGroup[.cpu]?.valueCelsius, 70)
    }

    func testCPUAverageUsesOnlyAveragedSensorsWhenPresent() {
        func sensor(_ key: String, _ value: Double, core: Bool) -> SensorReading {
            SensorReading(
                identity: SensorIdentity(rawKey: key, name: key, group: .cpu, countsTowardAverage: core),
                valueCelsius: value, timestamp: Fixtures.now, state: .fresh
            )
        }
        // Readings from an i9 MacBook Pro under load: a 0.2 °C uncore key used to drag the average below 72 °C.
        let summary = Fixtures.summary([
            sensor("TC1C", 79, core: true), sensor("TC2C", 80, core: true), sensor("TC3C", 75, core: true),
            sensor("TC4C", 73, core: true), sensor("TC5C", 69, core: true), sensor("TC6C", 68, core: true),
            sensor("TC7C", 68, core: true), sensor("TC8C", 68, core: true),
            sensor("TC0P", 63.1, core: false), sensor("TCSA", 73, core: false), sensor("TC0T", 0.2, core: false),
            sensor("TCXC", 79.8, core: false)
        ])
        XCTAssertEqual(summary.calculated[.cpuAverage] ?? 0, 72.5, accuracy: 0.001)
        XCTAssertEqual(summary.calculated[.hottest], 80)
    }

    func testCPUAverageFallsBackToWholeGroupWithoutAveragedSensors() {
        let summary = Fixtures.summary([
            SensorReading(identity: SensorIdentity(rawKey: "TC0P", name: "p", group: .cpu, countsTowardAverage: false),
                          valueCelsius: 60, timestamp: Fixtures.now, state: .fresh),
            SensorReading(identity: SensorIdentity(rawKey: "TC0D", name: "d", group: .cpu, countsTowardAverage: false),
                          valueCelsius: 70, timestamp: Fixtures.now, state: .fresh)
        ])
        XCTAssertEqual(summary.calculated[.cpuAverage], 65)
    }

    func testEmptyGroupDoesNotProduceAggregate() {
        let summary = Fixtures.summary([Fixtures.reading("TC0P", 60)])
        XCTAssertNil(summary.calculated[.gpuAverage])
    }
}


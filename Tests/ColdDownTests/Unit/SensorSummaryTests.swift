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

    func testEmptyGroupDoesNotProduceAggregate() {
        let summary = Fixtures.summary([Fixtures.reading("TC0P", 60)])
        XCTAssertNil(summary.calculated[.gpuAverage])
    }
}


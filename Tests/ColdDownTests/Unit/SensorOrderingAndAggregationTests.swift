import XCTest
import ThermalCore

final class SensorOrderingAndAggregationTests: XCTestCase {
    func testOlderGenerationCannotReplaceNewerReading() {
        var aggregator = SensorAggregator()
        _ = aggregator.ingest(.init(generation: 2, sampledAt: Fixtures.now, readings: [Fixtures.reading("TC0P", 70)]), now: Fixtures.now, refreshInterval: 2)
        let result = aggregator.ingest(.init(generation: 1, sampledAt: Fixtures.now.addingTimeInterval(-2), readings: [Fixtures.reading("TC0P", 20)]), now: Fixtures.now, refreshInterval: 2)
        XCTAssertEqual(result.readings.first?.valueCelsius, 70)
    }

    func testOlderAndConflictingEqualTimestampsAreIgnored() {
        var aggregator = SensorAggregator()
        _ = aggregator.ingest(.init(generation: 1, sampledAt: Fixtures.now, readings: [Fixtures.reading("TC0P", 60)]), now: Fixtures.now, refreshInterval: 2)
        let conflicting = Fixtures.reading("TC0P", 80, at: Fixtures.now)
        let result = aggregator.ingest(.init(generation: 1, sampledAt: Fixtures.now, readings: [conflicting]), now: Fixtures.now, refreshInterval: 2)
        XCTAssertEqual(result.readings.first?.valueCelsius, 60)
    }

    func testMissingKeyBecomesUnavailableAndFreshReadingBecomesStale() {
        var aggregator = SensorAggregator()
        _ = aggregator.ingest(.init(generation: 1, sampledAt: Fixtures.now, readings: [Fixtures.reading("TC0P", 60)]), now: Fixtures.now, refreshInterval: 2)
        let missing = aggregator.ingest(.init(generation: 2, sampledAt: Fixtures.now.addingTimeInterval(2), readings: []), now: Fixtures.now.addingTimeInterval(2), refreshInterval: 2)
        XCTAssertEqual(missing.readings.first?.state, .unavailable)

        var staleAggregator = SensorAggregator()
        _ = staleAggregator.ingest(.init(generation: 1, sampledAt: Fixtures.now, readings: [Fixtures.reading("TC0P", 60)]), now: Fixtures.now, refreshInterval: 2)
        let stale = staleAggregator.current(now: Fixtures.now.addingTimeInterval(7), refreshInterval: 2)
        XCTAssertEqual(stale.readings.first?.state, .stale)
    }
}


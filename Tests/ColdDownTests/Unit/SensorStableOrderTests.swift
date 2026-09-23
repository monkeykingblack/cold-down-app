import XCTest
import ThermalCore

/// Apple Silicon exposes several HID sensors with identical names; list order must not depend on dictionary order.
final class SensorStableOrderTests: XCTestCase {
    func testDuplicateNamesKeepTheSameOrderAcrossRefreshes() {
        let readings = (0..<12).map { index in
            SensorReading(
                identity: SensorIdentity(rawKey: "tdie\(index)", name: "PMU tdie", group: .cpu, idPrefix: "hid"),
                valueCelsius: 50 + Double(index % 3), timestamp: Fixtures.now, state: .fresh
            )
        }
        var orders = Set<[String]>()
        for pass in 0..<20 {
            var aggregator = SensorAggregator()
            let batch = SensorBatch(generation: UInt64(pass), sampledAt: Fixtures.now, readings: readings.shuffled())
            orders.insert(aggregator.ingest(batch, now: Fixtures.now, refreshInterval: 2).readings.map(\.id))
        }
        XCTAssertEqual(orders.count, 1)
    }
}

import XCTest

final class RefreshLatencyTests: XCTestCase {
    func testNinetyNinePercentBoundaryAcrossVirtualIntervals() {
        for interval in [1.0, 2.0, 30.0] {
            let passing = (0..<200).map { $0 < 198 ? interval + 0.49 : interval + 0.51 }
            XCTAssertEqual(passing.filter { $0 <= interval + 0.5 }.count, 198)
            XCTAssertGreaterThanOrEqual(Double(198) / 200, 0.99)

            let failing = (0..<200).map { $0 < 197 ? interval : interval + 1 }
            XCTAssertLessThan(Double(failing.filter { $0 <= interval + 0.5 }.count) / 200, 0.99)
        }
    }
}


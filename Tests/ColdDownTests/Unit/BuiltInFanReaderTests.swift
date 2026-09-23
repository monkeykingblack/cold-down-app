import XCTest
import ThermalCore

final class BuiltInFanReaderTests: XCTestCase {
    func testCapabilityValidationRejectsUnsafeRanges() {
        XCTAssertFalse(SpeedCapabilities(minimum: 0, maximum: 5_000, provenance: .deviceVerified).isStructurallyValid)
        XCTAssertFalse(SpeedCapabilities(minimum: 2_000, maximum: 1_000, provenance: .deviceVerified).isStructurallyValid)
        XCTAssertFalse(SpeedCapabilities(minimum: 1_000, maximum: 5_000, step: 0, provenance: .deviceVerified).isStructurallyValid)
    }

    func testFixedPositiveRangeIsValidAndNeverStops() {
        let capability = SpeedCapabilities(minimum: 2_000, maximum: 2_000, provenance: .deviceVerified)
        XCTAssertTrue(capability.isStructurallyValid)
        XCTAssertEqual(capability.clamped(0), 2_000)
    }
}


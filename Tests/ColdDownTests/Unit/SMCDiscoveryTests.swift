import XCTest
import IntelSMC
import ThermalCore

final class SMCDiscoveryTests: XCTestCase {
    func testKnownAndUnknownKeysPreserveRawIdentity() {
        let known = SMCSensorCatalog.identity(for: "TC0P")
        XCTAssertEqual(known.rawKey, "TC0P")
        XCTAssertEqual(known.name, "CPU proximity")
        XCTAssertEqual(known.group, .cpu)

        let unknown = SMCSensorCatalog.identity(for: "TZ99")
        XCTAssertEqual(unknown.rawKey, "TZ99")
        XCTAssertEqual(unknown.group, .other)
    }

    func testConservativeGroupingHeuristics() {
        XCTAssertEqual(SMCSensorCatalog.identity(for: "TG9X").group, .gpu)
        XCTAssertEqual(SMCSensorCatalog.identity(for: "TB9X").group, .battery)
        XCTAssertFalse(SMCSensorCatalog.looksLikeTemperature(key: "VC0C", type: "sp78"))
        XCTAssertTrue(SMCSensorCatalog.looksLikeTemperature(key: "TC9X", type: "sp78"))
    }
}


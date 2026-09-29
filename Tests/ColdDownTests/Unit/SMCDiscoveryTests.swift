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

    func testOnlyIntelPerCoreKeysFeedTheCPUAverage() {
        for key in ["TC1C", "TC8C", "TC2c"] {
            let core = SMCSensorCatalog.identity(for: key)
            XCTAssertEqual(core.group, .cpu, key)
            XCTAssertTrue(core.countsTowardAverage, key)
        }
        XCTAssertEqual(SMCSensorCatalog.identity(for: "TC3C").name, "CPU core 3")
        for key in ["TC0P", "TC0F", "TCXC", "TCMX", "TCSA", "TC0T"] {
            let other = SMCSensorCatalog.identity(for: key)
            XCTAssertEqual(other.group, .cpu, key)
            XCTAssertFalse(other.countsTowardAverage, key)
        }
        // Stats files the Intel iGPU under GPU, not CPU.
        XCTAssertEqual(SMCSensorCatalog.identity(for: "TCGC").group, .gpu)
    }
}


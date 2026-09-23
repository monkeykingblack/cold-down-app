import XCTest
import IntelSMC
import ThermalCore

final class PlatformHandlingTests: XCTestCase {
    func testChipParsingFromBrandStrings() {
        XCTAssertEqual(ChipPlatform.parse(brandString: "Apple M4"), .appleSilicon(generation: 4, tier: .base))
        XCTAssertEqual(ChipPlatform.parse(brandString: "Apple M4 Pro"), .appleSilicon(generation: 4, tier: .pro))
        XCTAssertEqual(ChipPlatform.parse(brandString: "Apple M3 Max"), .appleSilicon(generation: 3, tier: .max))
        XCTAssertEqual(ChipPlatform.parse(brandString: "Apple M1 Ultra"), .appleSilicon(generation: 1, tier: .ultra))
        XCTAssertEqual(ChipPlatform.parse(brandString: "Intel(R) Core(TM) i9-9980HK CPU @ 2.40GHz"), .intel)
        XCTAssertEqual(ChipPlatform.parse(brandString: "Apple M9"), .unknownAppleSilicon)
        XCTAssertEqual(ChipPlatform.parse(brandString: "Apple M10"), .unknownAppleSilicon, "m10 must not be read as m1")
        XCTAssertEqual(ChipPlatform.parse(brandString: "Apple A18 Pro"), .unknownAppleSilicon)
    }

    func testRosettaBrandStringDoesNotMasqueradeAsIntel() {
        XCTAssertEqual(ChipPlatform.resolve(brandString: "VirtualApple @ 2.50GHz processor", isAppleSilicon: true), .unknownAppleSilicon)
        XCTAssertEqual(ChipPlatform.resolve(brandString: "Intel(R) Core(TM) i7", isAppleSilicon: true), .unknownAppleSilicon)
        XCTAssertEqual(ChipPlatform.resolve(brandString: "", isAppleSilicon: false), .intel)
    }

    func testFanModeValues() {
        XCTAssertFalse(SMCFanKeys.isForced(modeByte: 0))
        XCTAssertTrue(SMCFanKeys.isForced(modeByte: 1))
        XCTAssertFalse(SMCFanKeys.isForced(modeByte: 3), "3 = system-controlled on Apple Silicon")
        XCTAssertEqual(SMCFanKeys.modeKey(0, lowercase: true), "F0md")
        XCTAssertEqual(SMCFanKeys.modeKey(1, lowercase: false), "F1Md")
    }

    func testM4BaseAndProUseDifferentFirstGPUKeys() {
        let base = Set(AppleSiliconSMCSensorKeys.definitions(for: .appleSilicon(generation: 4, tier: .base)).map(\.key))
        let pro = Set(AppleSiliconSMCSensorKeys.definitions(for: .appleSilicon(generation: 4, tier: .pro)).map(\.key))
        XCTAssertTrue(base.isSuperset(of: ["Te05", "Tp01", "Tg0G", "Tg0H", "Tg0K", "TB1T"]))
        XCTAssertFalse(base.contains("Tg1U"))
        XCTAssertTrue(pro.isSuperset(of: ["Tg1U", "Tg1k", "Tg0K"]))
        XCTAssertFalse(pro.contains("Tg0G"))
    }

    func testSensorKeySelectionIntersectsWithAvailableKeysAndGroupsCores() {
        let available = ["Tp09", "Tp01", "Tg05", "TB1T", "Tp1h", "VC0C"]
        let m1 = AppleSMCSensorProvider.sensorCandidates(chip: .appleSilicon(generation: 1, tier: .base), availableKeys: available)
        XCTAssertEqual(Set(m1.map(\.rawKey)), ["Tp09", "Tp01", "Tg05", "TB1T"])
        XCTAssertEqual(m1.first { $0.rawKey == "Tp09" }?.name, "CPU efficiency core 1")
        XCTAssertEqual(m1.first { $0.rawKey == "Tp09" }?.group, .cpu)
        XCTAssertEqual(m1.first { $0.rawKey == "Tg05" }?.group, .gpu)

        let m2 = AppleSMCSensorProvider.sensorCandidates(chip: .appleSilicon(generation: 2, tier: .base), availableKeys: available)
        XCTAssertEqual(m2.first { $0.rawKey == "Tp09" }?.name, "CPU performance core 3", "Stats renames Tp09 on M2")
        XCTAssertTrue(m2.contains { $0.rawKey == "Tp1h" })
    }

    func testUnknownAppleSiliconOnlyUsesCommonKeysAndIntelStaysGeneric() {
        let available = ["Tp01", "TB1T", "TC0P"]
        let unknown = AppleSMCSensorProvider.sensorCandidates(chip: .unknownAppleSilicon, availableKeys: available)
        XCTAssertEqual(unknown.map(\.rawKey), ["TB1T"])
        let intel = AppleSMCSensorProvider.sensorCandidates(chip: .intel, availableKeys: available)
        XCTAssertEqual(Set(intel.map(\.rawKey)), ["Tp01", "TB1T", "TC0P"])
        XCTAssertEqual(intel.first { $0.rawKey == "TC0P" }?.name, "CPU proximity")
    }

    func testFloatTypeWithTrailingSpaceCountsAsTemperature() {
        XCTAssertTrue(SMCSensorCatalog.looksLikeTemperature(key: "Tp01", type: "flt "))
    }

    func testImplausibleTemperaturesAreDropped() {
        XCTAssertFalse(AppleSMCSensorProvider.plausibleRange.contains(0))
        XCTAssertFalse(AppleSMCSensorProvider.plausibleRange.contains(110.5))
        XCTAssertTrue(AppleSMCSensorProvider.plausibleRange.contains(45))
    }
}

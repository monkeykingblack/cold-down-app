import XCTest
import ThermalCore

final class ProfilePersistenceTests: XCTestCase {
    func testRoundTripAndValidation() async throws {
        let temporary = Fixtures.temporaryDefaults("ColdDownTests")
        defer { temporary.cleanUp() }
        let store = UserDefaultsProfileStore(defaults: temporary.defaults)
        let saved = AppPreferences(
            profiles: ["flydigi:37d7:1004": FanProfile(thresholdCelsius: 99, manualTarget: 99_999)],
            refreshInterval: 100
        )
        try store.save(saved)
        let loaded = store.load()
        XCTAssertEqual(loaded.refreshInterval, 30)
        XCTAssertEqual(loaded.profiles["flydigi:37d7:1004"]?.thresholdCelsius, 85)
    }

    func testCorruptDataFallsBackToDefaults() async {
        let temporary = Fixtures.temporaryDefaults("ColdDownTests")
        defer { temporary.cleanUp() }
        temporary.defaults.set(Data("bad".utf8), forKey: "prefs")
        let store = UserDefaultsProfileStore(defaults: temporary.defaults, key: "prefs")
        let loaded = store.load()
        XCTAssertEqual(loaded, .defaults)
    }
}

import XCTest
import ThermalCore

final class ProfilePersistenceTests: XCTestCase {
    func testRoundTripAndValidation() async throws {
        let suite = "ColdDownTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsProfileStore(defaults: defaults)
        let saved = AppPreferences(
            profiles: ["builtin:0": FanProfile(thresholdCelsius: 99, manualTarget: 99_999)],
            refreshInterval: 100
        )
        try store.save(saved)
        let loaded = store.load()
        XCTAssertEqual(loaded.refreshInterval, 30)
        XCTAssertEqual(loaded.profiles["builtin:0"]?.thresholdCelsius, 85)
    }

    func testCorruptDataFallsBackToDefaults() async {
        let suite = "ColdDownTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(Data("bad".utf8), forKey: "prefs")
        let store = UserDefaultsProfileStore(defaults: defaults, key: "prefs")
        let loaded = store.load()
        XCTAssertEqual(loaded, .defaults)
    }
}

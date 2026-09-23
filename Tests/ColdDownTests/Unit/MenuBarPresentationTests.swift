import XCTest
import ThermalCore

final class MenuBarPresentationTests: XCTestCase {
    func testSnapshotPresentationAndTemperaturePreference() {
        let summary = Fixtures.summary([Fixtures.reading("TC0P", 74.4)])
        let snapshot = CoolingSnapshot(
            sensors: summary, fans: [Fixtures.builtIn(), Fixtures.external(availability: .disconnected)],
            profiles: [:], helperStatus: .unavailable, overallMode: .readOnly,
            lastDecision: nil, generatedAt: Fixtures.now
        )
        let shown = MenuBarPresentation(snapshot: snapshot, showTemperature: true)
        XCTAssertEqual(shown.label, "74°")
        XCTAssertTrue(shown.externalSummary.contains("Disconnected"))
        XCTAssertEqual(shown.builtInSummaries.count, 1)
        XCTAssertEqual(MenuBarPresentation(snapshot: snapshot, showTemperature: false).label, "")
    }
}


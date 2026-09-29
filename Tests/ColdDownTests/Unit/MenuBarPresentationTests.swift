import XCTest
import ThermalCore

final class MenuBarPresentationTests: XCTestCase {
    func testSnapshotPresentationAndTemperaturePreference() {
        let summary = Fixtures.summary([Fixtures.reading("TC0P", 74.4)])
        let snapshot = CoolingSnapshot(
            sensors: summary, fans: [Fixtures.external(availability: .disconnected)],
            profiles: [:], overallMode: .readOnly,
            lastDecision: nil, generatedAt: Fixtures.now
        )
        let shown = MenuBarPresentation(snapshot: snapshot, showTemperature: true)
        XCTAssertEqual(shown.label, "74°")
        XCTAssertTrue(shown.externalSummary.contains("Disconnected"))
        XCTAssertEqual(MenuBarPresentation(snapshot: snapshot, showTemperature: false).label, "")
    }
}


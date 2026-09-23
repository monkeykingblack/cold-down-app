import XCTest
@testable import ColdDownApp

final class SessionMarkerTests: XCTestCase {
    func testDetectsUncleanExitOnlyWhenPreviousSessionNeverEnded() throws {
        let suite = "ColdDown.SessionMarkerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let marker = SessionMarker(defaults: defaults)

        XCTAssertFalse(marker.begin(), "First launch ever is clean")
        XCTAssertTrue(marker.begin(), "No end() before the next launch means a crash")
        marker.end()
        XCTAssertFalse(marker.begin(), "A normal quit is clean")
    }
}

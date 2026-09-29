import XCTest
@testable import ColdDownApp

final class SessionMarkerTests: XCTestCase {
    func testDetectsUncleanExitOnlyWhenPreviousSessionNeverEnded() throws {
        let temporary = Fixtures.temporaryDefaults("ColdDown.SessionMarkerTests")
        defer { temporary.cleanUp() }
        let marker = SessionMarker(defaults: temporary.defaults)

        XCTAssertFalse(marker.begin(), "First launch ever is clean")
        XCTAssertTrue(marker.begin(), "No end() before the next launch means a crash")
        marker.end()
        XCTAssertFalse(marker.begin(), "A normal quit is clean")
    }
}

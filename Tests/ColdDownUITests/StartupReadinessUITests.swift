import XCTest

@MainActor
final class StartupReadinessUITests: XCTestCase {
    func testReadOnlyStartupShowsTemperatureAndAllFansWithinTenSeconds() {
        let app = UITestLaunchConfiguration.application()
        let start = Date()
        app.launch()
        // Found by scene ID: page navigation titles replace the "Cold Down" window title.
        XCTAssertTrue(app.windows["main"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["thermal.hottest"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["thermal.fan.builtin:0"].waitForExistence(timeout: 10))
        XCTAssertLessThan(Date().timeIntervalSince(start), 10.5)
    }

    func testNoRecognizedSensorsStillShowsUnavailableState() {
        let app = UITestLaunchConfiguration.application(["--no-sensors"])
        app.launch()
        XCTAssertTrue(app.staticTexts["thermal.temperature.unavailable"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["thermal.fan.builtin:0"].exists)
    }
}

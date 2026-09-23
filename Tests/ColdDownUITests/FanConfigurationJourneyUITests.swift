import XCTest

@MainActor
final class FanConfigurationJourneyUITests: XCTestCase {
    func testWriteReadyFanAutoAndManualControlsStaySynchronized() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ApplePersistenceIgnoreState", "YES",
            "-NSQuitAlwaysKeepsWindows", "NO",
            "--mock"
        ]
        app.launch()
        // Found by scene ID: page navigation titles replace the "Cold Down" window title.
        XCTAssertTrue(app.windows["main"].waitForExistence(timeout: 10))
        app.buttons["thermal.fan.builtin:0"].click()
        XCTAssertTrue(app.buttons["thermal.fan.mode.builtin:0.auto"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.sliders["thermal.fan.auto.threshold.slider.builtin:0"].exists)
        XCTAssertTrue(app.textFields["thermal.fan.auto.threshold.field.builtin:0"].exists)
        app.buttons["thermal.fan.mode.builtin:0.manual"].click()
        XCTAssertTrue(app.sliders["thermal.fan.manual.speed.slider.builtin:0"].exists)
        XCTAssertTrue(app.textFields["thermal.fan.manual.speed.field.builtin:0"].exists)
    }

    func testDisconnectedCoolerRemainsVisibleAndDisabled() {
        let app = UITestLaunchConfiguration.application()
        app.launch()
        let cooler = app.buttons["thermal.fan.flydigi:37d7:1004"]
        XCTAssertTrue(cooler.waitForExistence(timeout: 10))
        XCTAssertTrue(cooler.isEnabled)
        cooler.click()
        XCTAssertTrue(app.staticTexts["thermal.fan.connection.message.flydigi:37d7:1004"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["thermal.fan.mode.flydigi:37d7:1004.manual"].isEnabled)
    }
}

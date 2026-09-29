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
        let cooler = "flydigi:37d7:1004"
        app.buttons["thermal.fan.\(cooler)"].click()
        XCTAssertTrue(app.buttons["thermal.fan.mode.\(cooler).auto"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.sliders["thermal.fan.auto.threshold.slider.\(cooler)"].exists)
        XCTAssertTrue(app.textFields["thermal.fan.auto.threshold.field.\(cooler)"].exists)
        app.buttons["thermal.fan.mode.\(cooler).manual"].click()
        XCTAssertTrue(app.sliders["thermal.fan.manual.speed.slider.\(cooler)"].exists)
        XCTAssertTrue(app.textFields["thermal.fan.manual.speed.field.\(cooler)"].exists)
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

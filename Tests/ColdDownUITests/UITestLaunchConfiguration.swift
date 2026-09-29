import XCTest

enum UITestLaunchConfiguration {
    @MainActor
    static func application(_ extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ApplePersistenceIgnoreState", "YES",
            "-NSQuitAlwaysKeepsWindows", "NO",
            "--mock", "--cooler-disconnected"
        ] + extraArguments
        return app
    }
}

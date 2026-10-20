import XCTest

/// The UI tests of the application.
final class MackeepDesktopUITests: XCTestCase {
    func testTheWindowOpens() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
    }
}

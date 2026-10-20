import XCTest

/// The UI tests of the application.
final class MackeepDesktopUITests: XCTestCase {
    /// The window of the application.
    private var window: XCUIElement {
        XCUIApplication().windows.firstMatch
    }

    func testTheWindowOpens() {
        XCUIApplication().launch()

        XCTAssertTrue(window.waitForExistence(timeout: 20))
    }

    func testTheApplicationsAreListed() {
        XCUIApplication().launch()

        XCTAssertTrue(window.waitForExistence(timeout: 20))

        // The applications of Mackeep are listed
        let list: XCUIElement = window.outlines.element(boundBy: 1)
        XCTAssertTrue(list.waitForExistence(timeout: 20))

        // The applications of the database of Mackeep are there
        let checkbox: XCUIElement = list.descendants(matching: .checkBox).firstMatch
        XCTAssertTrue(checkbox.waitForExistence(timeout: 20))
        XCTAssertTrue(
            checkbox.label.contains("Синхронизировать")
                || checkbox.label.contains("Sync")
        )
    }
}

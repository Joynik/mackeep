import XCTest

@testable import MackeepDesktop

/// The tests of the shell of the application.
final class MackeepDesktopTests: XCTestCase {
    func testTheSectionsHaveATitle() {
        for section in SidebarSection.allCases {
            XCTAssertFalse(section.title.isEmpty)
            XCTAssertNotEqual(section.title, section.rawValue)
        }
    }

    func testAMissingStringFallsBackToItsKey() {
        XCTAssertEqual(L10n.string("a.missing.key"), "a.missing.key")
    }
}

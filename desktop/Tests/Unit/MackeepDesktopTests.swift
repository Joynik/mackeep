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

    func testTheLanguageOfTheInterfaceIsLookedUpInItsBundle() {
        L10n.language = .russian
        defer { L10n.language = .system }

        XCTAssertEqual(
            L10n.string("section.applications.title"),
            "Приложения"
        )
    }

    func testAMissingStringFallsBackToItsKey() {
        XCTAssertEqual(L10n.string("a.missing.key"), "a.missing.key")
    }
}

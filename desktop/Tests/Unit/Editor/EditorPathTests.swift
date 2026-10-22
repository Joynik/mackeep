import XCTest

@testable import MackeepDesktop

/// The tests of the paths of an application.
final class EditorPathTests: XCTestCase {
    /// The home directory of the user.
    private var home: String { NSHomeDirectory() }

    func testThePathInTheHomeFolderIsRelative() {
        XCTAssertEqual(
            EditorPath.corrected("\(home)/.Test", isXDG: false),
            ".Test"
        )
    }

    func testThePathOutsideOfTheHomeFolderIsCut() {
        XCTAssertEqual(EditorPath.corrected("/.Test", isXDG: false), ".Test")
    }

    func testTheRelativePathIsKept() {
        XCTAssertEqual(
            EditorPath.corrected(".config/git/config", isXDG: false),
            ".config/git/config"
        )
    }

    func testThePathInTheConfigFolderIsRelative() {
        XCTAssertEqual(
            EditorPath.corrected("\(home)/.config/git/config", isXDG: true),
            "git/config"
        )
    }

    func testThePathOutsideOfTheConfigFolderIsCut() {
        XCTAssertEqual(
            EditorPath.corrected("/.config/git/config", isXDG: true),
            "git/config"
        )
    }

    func testTheTildeIsTheHomeFolder() {
        XCTAssertEqual(EditorPath.corrected("~/.Test", isXDG: false), ".Test")
    }

    func testTheEmptyPathIsKept() {
        XCTAssertEqual(EditorPath.corrected("  ", isXDG: false), "")
    }

    func testTheHomeVariableIsCut() {
        XCTAssertEqual(
            EditorPath.corrected("$HOME/.Test", isXDG: false),
            ".Test"
        )
    }

    func testTheHomeVariableWithBracesIsCut() {
        XCTAssertEqual(
            EditorPath.corrected("${HOME}/.Test", isXDG: false),
            ".Test"
        )
    }

    func testTheConfigVariableIsCut() {
        XCTAssertEqual(
            EditorPath.corrected("$XDG_CONFIG_HOME/git/config", isXDG: true),
            "git/config"
        )
    }

    func testTheConfigVariableWithBracesIsCut() {
        XCTAssertEqual(
            EditorPath.corrected("${XDG_CONFIG_HOME}/git/config", isXDG: true),
            "git/config"
        )
    }

    func testTheHomeVariableIsCutInTheConfigSection() {
        XCTAssertEqual(
            EditorPath.corrected("\(home)/.config/git/config", isXDG: true),
            "git/config"
        )
    }

    func testTheMaskIsCut() {
        XCTAssertEqual(
            EditorPath.corrected("$HOME/.Test/1/*.log", isXDG: false),
            ".Test/1/*.log"
        )
    }

    func testTheMaskWithWildcardsIsKept() {
        XCTAssertEqual(
            EditorPath.corrected("**/cache/**", isXDG: false),
            "**/cache/**"
        )
    }
}

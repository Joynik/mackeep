import XCTest

@testable import MackeepDesktop

/// The tests of the INI document.
final class INIDocumentTests: XCTestCase {
    /// A config file of an application, with everything it can hold.
    static let applicationConfig: String = """
    # The config of an application
    [application]
    name = Test App

    ; The paths of the application
    [configuration_files]
    .testrc
    .testdir

    [xdg_configuration_files]
    test-app/config

    # The paths that are not backed up
    [exclude]
    .testdir/cache
    *.log

    [xdg_exclude]
    test-app/cache
    """

    func testTheDocumentIsLossless() {
        let document: INIDocument = INIDocument(text: Self.applicationConfig)
        XCTAssertEqual(document.text, Self.applicationConfig)
    }

    func testTheDocumentIsLosslessWithoutATrailingNewline() {
        let text: String = "[application]\nname = Test App"
        let document: INIDocument = INIDocument(text: text)
        XCTAssertEqual(document.text, text)
    }

    func testTheSectionsAreInOrder() {
        let document: INIDocument = INIDocument(text: Self.applicationConfig)
        XCTAssertEqual(
            document.sectionNames,
            [
                "application",
                "configuration_files",
                "xdg_configuration_files",
                "exclude",
                "xdg_exclude",
            ]
        )
    }

    func testTheValueOfAnOption() {
        let document: INIDocument = INIDocument(text: Self.applicationConfig)
        XCTAssertEqual(document.value(forKey: "name", inSection: "application"), "Test App")
        XCTAssertNil(document.value(forKey: "name", inSection: "exclude"))
        XCTAssertNil(document.value(forKey: "missing", inSection: "application"))
    }

    func testTheValuesOfASectionAreTheKeysOfTheOptionsWithoutValue() {
        let document: INIDocument = INIDocument(text: Self.applicationConfig)
        XCTAssertEqual(
            document.values(inSection: "configuration_files"),
            [".testrc", ".testdir"]
        )
        XCTAssertEqual(
            document.values(inSection: "exclude"),
            [".testdir/cache", "*.log"]
        )
    }

    func testTheCommentsAreKept() {
        let document: INIDocument = INIDocument(text: Self.applicationConfig)
        XCTAssertEqual(
            document.lines.filter { line in
                if case .comment = line { return true }
                return false
            }.count,
            3
        )
    }

    func testTheInlineCommentsAreStrippedFromTheValues() {
        let document: INIDocument = INIDocument(
            text: "[s]\nname = Test App ; the name\n",
            stripsInlineComments: true
        )
        XCTAssertEqual(document.value(forKey: "name", inSection: "s"), "Test App")
    }

    func testTheInlineCommentsAreKeptInTheValues() {
        let document: INIDocument = INIDocument(
            text: "[s]\nname = Test App ; the name\n"
        )
        XCTAssertEqual(
            document.value(forKey: "name", inSection: "s"),
            "Test App ; the name"
        )
    }

    func testTheInlineCommentNeedsAWhitespaceBeforeIt() {
        let document: INIDocument = INIDocument(
            text: "[s]\nname = a#b\n",
            stripsInlineComments: true
        )
        XCTAssertEqual(document.value(forKey: "name", inSection: "s"), "a#b")
    }

    func testTheValueOfAnOptionWithoutValueIsNil() {
        let document: INIDocument = INIDocument(text: "[s]\npath\n")
        XCTAssertNil(document.value(forKey: "path", inSection: "s"))
        XCTAssertEqual(document.values(inSection: "s"), ["path"])
    }

    func testSettingAValueKeepsTheFile() {
        var document: INIDocument = INIDocument(text: Self.applicationConfig)
        document.setValue("New Name", forKey: "name", inSection: "application")

        XCTAssertEqual(
            document.value(forKey: "name", inSection: "application"),
            "New Name"
        )
        XCTAssertEqual(document.sectionNames.count, 5)
        XCTAssertTrue(document.text.contains("# The config of an application"))
        XCTAssertTrue(document.text.contains(".testdir/cache"))
    }

    func testSettingAValueAddsTheOptionWhenItIsMissing() {
        var document: INIDocument = INIDocument(text: "[application]\nname = Test App\n")
        document.setValue("file_system", forKey: "engine", inSection: "storage")

        XCTAssertEqual(
            document.value(forKey: "engine", inSection: "storage"),
            "file_system"
        )
        XCTAssertTrue(document.text.contains("[storage]"))
    }

    func testSettingTheOptionsOfASectionReplacesThem() {
        var document: INIDocument = INIDocument(text: Self.applicationConfig)
        document.setOptionKeys([".other"], inSection: "configuration_files")

        XCTAssertEqual(document.values(inSection: "configuration_files"), [".other"])
        XCTAssertFalse(document.text.contains(".testrc"))
        // The other sections are not touched
        XCTAssertEqual(document.values(inSection: "exclude"), [".testdir/cache", "*.log"])
    }

    func testRemovingASectionRemovesItsOptions() {
        var document: INIDocument = INIDocument(text: Self.applicationConfig)
        document.removeSection("exclude")

        XCTAssertFalse(document.hasSection("exclude"))
        XCTAssertFalse(document.text.contains(".testdir/cache"))
        XCTAssertTrue(document.hasSection("xdg_exclude"))
    }

    func testAddingASectionKeepsTheOthers() {
        var document: INIDocument = INIDocument(text: Self.applicationConfig)
        document.ensureSection("xdg_exclude")

        XCTAssertTrue(document.hasSection("xdg_exclude"))
        XCTAssertEqual(document.sectionNames.count, 5)
    }
}

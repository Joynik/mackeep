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
    func testCommentsAtEitherEndOfAValueAreSafe() {
        for marker in ["#", ";"] {
            let leading = INIDocument(
                text: "[s]\npath = \(marker)comment\n", stripsInlineComments: true)
            XCTAssertEqual(leading.value(forKey: "path", inSection: "s"), "")
            let trailing = INIDocument(
                text: "[s]\npath = /tmp/store \(marker)\n", stripsInlineComments: true)
            XCTAssertEqual(trailing.value(forKey: "path", inSection: "s"), "/tmp/store")
        }
    }

    func testInvalidStructureHasLineDiagnostics() {
        for text in [
            "name = App", "[application]\nname = App\n[application]",
            "[application]\nname = A\nname = B", "[application]\n[broken",
        ] {
            XCTAssertFalse(INIDocument(text: text).diagnostics.isEmpty, text)
        }
    }

    func testMainConfigOptionCaseAndNoValueCommentsFollowCLI() {
        let text =
            "[storage]\nPATH = /tmp/store # comment\n[applications_to_sync]\nVIM # comment\n[exclude]\nLibrary/Cache # comment\n"
        var document = INIDocument(text: text, stripsInlineComments: true)
        XCTAssertEqual(document.value(forKey: "path", inSection: "storage"), "/tmp/store")
        XCTAssertEqual(document.optionKeys(inSection: "applications_to_sync"), ["vim"])
        XCTAssertEqual(document.values(inSection: "exclude"), ["Library/Cache"])
        document.setValue("/new", forKey: "path", inSection: "storage")
        XCTAssertEqual(document.optionKeys(inSection: "storage"), ["path"])
        XCTAssertTrue(document.diagnostics.isEmpty)
    }

    func testMultilineValuesReadAndReplaceWithoutOrphanedLines() {
        var document = INIDocument(text: "[application]\nname = First\n  Second\n  Third\n")
        XCTAssertEqual(
            document.value(forKey: "name", inSection: "application"), "First\nSecond\nThird")
        XCTAssertTrue(document.diagnostics.isEmpty)
        document.setValue("New", forKey: "name", inSection: "application")
        XCTAssertEqual(document.text, "[application]\nname = New\n")
        XCTAssertFalse(INIDocument(text: "[s]\nno-value\n  continuation\n").diagnostics.isEmpty)
    }

    func testSettingAValueOnAValuelessOptionWritesADelimiter() {
        var document = INIDocument(text: "[storage]\npath\n")
        document.setValue("/tmp", forKey: "path", inSection: "storage")
        XCTAssertEqual(
            INIDocument(text: document.text).value(forKey: "path", inSection: "storage"), "/tmp")
    }

    func testWindowsLineEndingsArePreserved() {
        let text = "[application]\r\nname = App\r\n\r\n[configuration_files]\r\n.config/demo\r\n"
        var document = INIDocument(text: text)
        XCTAssertEqual(document.text, text)
        XCTAssertEqual(document.value(forKey: "name", inSection: "application"), "App")
        XCTAssertTrue(document.diagnostics.isEmpty)
        document.setValue("New", forKey: "name", inSection: "application")
        XCTAssertTrue(document.text.contains("name = New\r\n"))
    }

}

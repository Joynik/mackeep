import XCTest

@testable import MackeepDesktop

/// The tests of the editor of an application.
@MainActor
final class ApplicationEditorModelTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mackeep-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    /// The content of the config file of an application.
    nonisolated static let config: String = """
    # The name of the application
    [application]
    name = Test App

    [configuration_files]
    .testrc
    .testdir

    [exclude]
    .testdir/cache
    """

    /// Write a config file and return the editor.
    private func makeEditor(_ text: String = ApplicationEditorModelTests.config)
    throws -> (ApplicationEditorModel, URL) {
        let url: URL = directory.appendingPathComponent("test-app.cfg")
        try text.write(to: url, atomically: true, encoding: .utf8)
        let document: INIDocument = try INIFile.load(from: url)
        return (
            ApplicationEditorModel(
                appName: "test-app",
                url: url,
                document: document
            ),
            url
        )
    }

    func testTheConfigIsRead() throws {
        let (editor, _) = try makeEditor()

        XCTAssertEqual(editor.displayName, "Test App")
        XCTAssertEqual(editor.paths.map(\.path), [".testrc", ".testdir"])
        XCTAssertEqual(editor.excludes, [".testdir/cache"])
        XCTAssertTrue(editor.text.contains("[application]"))
        XCTAssertTrue(editor.text.contains("[configuration_files]"))
        XCTAssertTrue(editor.text.contains("[exclude]"))
        XCTAssertFalse(editor.text.contains("[xdg_configuration_files]"))
    }

    func testTheNameIsChanged() throws {
        let (editor, _) = try makeEditor()

        editor.displayName = "New Name"

        XCTAssertEqual(editor.displayName, "New Name")
        XCTAssertTrue(editor.text.contains("name = New Name"))
    }

    func testThePathIsRelativeToTheHomeFolder() throws {
        let (editor, _) = try makeEditor()
        let url: URL = URL(fileURLWithPath: EditorPath.homeDirectory.path)
            .appendingPathComponent(".newfile")

        editor.addPath(url.path, isXDG: false)

        XCTAssertEqual(editor.paths.map(\.path).last, ".newfile")
    }

    func testThePathIsWrittenAsItIs() throws {
        let (editor, _) = try makeEditor()

        editor.addPath(".config/git/config", isXDG: false)

        XCTAssertEqual(editor.paths.map(\.path).last, ".config/git/config")
    }

    func testTheDuplicatePathIsRefused() throws {
        let (editor, _) = try makeEditor()
        let url: URL = URL(fileURLWithPath: EditorPath.homeDirectory.path)
            .appendingPathComponent(".testrc")

        editor.addPath(url.path, isXDG: false)

        XCTAssertEqual(editor.paths.count, 2)
        XCTAssertTrue(editor.issues.contains { $0.severity == .warning })
    }

    func testTheAbsolutePathInTheHomeFolderIsCut() throws {
        let (editor, _) = try makeEditor()
        let url: URL = URL(fileURLWithPath: EditorPath.homeDirectory.path)
            .appendingPathComponent(".Test")

        editor.addPath(url.path, isXDG: false)

        XCTAssertEqual(editor.paths.map(\.path).last, ".Test")
    }

    func testTheExternalHomePathIsKeptAndRejectedWhenDisabled() throws {
        let (editor, _) = try makeEditor()

        editor.addPath("/.Test", isXDG: false)

        XCTAssertEqual(editor.paths.map(\.path).last, "/.Test")
        XCTAssertFalse(editor.canSave)
    }

    func testTheAbsolutePathInTheConfigFolderIsCut() throws {
        let (editor, _) = try makeEditor()
        let url: URL = URL(fileURLWithPath: EditorPath.homeDirectory.path)
            .appendingPathComponent(".config/git/config")

        editor.addPath(url.path, isXDG: true)

        XCTAssertEqual(editor.xdgPaths.map(\.path).last, "git/config")
    }

    func testTheExternalConfigPathIsKeptAndRejectedWhenDisabled() throws {
        let (editor, _) = try makeEditor()

        editor.addPath("/.config/git/config", isXDG: true)

        XCTAssertEqual(editor.xdgPaths.map(\.path).last, "/.config/git/config")
        XCTAssertFalse(editor.canSave)
    }

    func testTheNameIsRequired() throws {
        let (editor, _) = try makeEditor()

        editor.displayName = "   "

        XCTAssertFalse(editor.canSave)
        XCTAssertTrue(editor.issues.contains { $0.severity == .error })
    }

    func testTheFileIsSaved() throws {
        let (editor, url) = try makeEditor()

        editor.displayName = "New Name"
        try editor.save()

        let saved: INIDocument = try INIFile.load(from: url)
        XCTAssertEqual(saved.value(forKey: "name", inSection: "application"), "New Name")
        XCTAssertFalse(editor.hasUnsavedChanges)
        // The comments are kept
        XCTAssertTrue(saved.text.contains("# The name of the application"))
    }

    func testSavingAnEditorDoesNotChangeSelection() throws {
        _ = try makeEditor()
        let configURL: URL = directory.appendingPathComponent(".mackeep.cfg")
        try "[storage]\nengine = dropbox\n".write(
            to: configURL,
            atomically: true,
            encoding: .utf8
        )
        let config: MainConfig = try MainConfig.load(from: configURL)
        let model: ApplicationEditorModel = ApplicationEditorModel(
            appName: "test-app",
            url: directory.appendingPathComponent("test-app.cfg"),
            document: try INIFile.load(from: directory.appendingPathComponent("test-app.cfg")),
            mainConfig: config
        )

        try model.save()

        let saved: MainConfig = try MainConfig.load(from: configURL)
        XCTAssertEqual(saved.appsToSync, [])
        XCTAssertEqual(saved.appsToIgnore, [])
    }

    func testTheUndoGivesThePreviousVersion() throws {
        let (editor, _) = try makeEditor()

        editor.remember()
        editor.displayName = "New Name"
        XCTAssertTrue(editor.canUndo)

        editor.undo()

        XCTAssertEqual(editor.displayName, "Test App")
    }

    func testTheTextModeAndTheFormAreInSync() throws {
        let (editor, _) = try makeEditor()

        editor.text = "[application]\nname = From the text\n"

        XCTAssertEqual(editor.displayName, "From the text")

        editor.displayName = "From the form"
        XCTAssertTrue(editor.text.contains("name = From the form"))
    }

    func testTheIdentifierOfAnExistingApplicationIsRefused() throws {
        let model: ApplicationCreatorModel = ApplicationCreatorModel(directory: directory)
        model.name = "my-app"

        model.validate(existing: ["my-app"])

        XCTAssertFalse(model.canCreate)
        XCTAssertTrue(model.issues.contains { $0.severity == .error })
    }
    func testExternalPathIsAcceptedWhenEnabledInSharedConfig() throws {
        let mainURL = directory.appendingPathComponent("main.cfg")
        try "[security]\nallow_external_paths = true\n".write(to: mainURL, atomically: true, encoding: .utf8)
        let url = directory.appendingPathComponent("external.cfg")
        let editor = ApplicationEditorModel(
            appName: "external", url: url,
            document: INIDocument(text: "[application]\nname = External\n"),
            mainConfig: try MainConfig.load(from: mainURL)
        )
        editor.addPath("/Volumes/External/config", isXDG: false)
        XCTAssertEqual(editor.paths.first?.path, "/Volumes/External/config")
        XCTAssertTrue(editor.canSave)
    }

    func testExternalChangesRequireExplicitOverwrite() throws {
        let (editor, url) = try makeEditor()
        try "[application]\nname = External\n".write(to: url, atomically: true, encoding: .utf8)
        editor.displayName = "Local"
        XCTAssertTrue(editor.hasChangedOutside())
        XCTAssertThrowsError(try editor.save())
        try editor.save(overwrite: true)
        XCTAssertEqual(
            try INIFile.load(from: url).value(forKey: "name", inSection: "application"), "Local")
    }

    func testHomeAndXDGPathsAreDistinct() throws {
        let (editor, _) = try makeEditor()
        editor.addPath("demo/settings", isXDG: false)
        editor.addPath("demo/settings", isXDG: true)
        XCTAssertTrue(editor.canSave)
    }

}

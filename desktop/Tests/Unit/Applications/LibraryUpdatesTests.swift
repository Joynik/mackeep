import XCTest

@testable import MackeepDesktop

@MainActor
final class LibraryUpdatesTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mackeep-library-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func model() throws -> ApplicationsModel {
        let tool = directory.appendingPathComponent("mackeep-cli")
        try """
        #!/bin/sh
        set -eu
        printf '%s\\n' "$*" >> "$HOME/arguments"
        if [ -f "$HOME/fail" ]; then echo 'Offline' >&2; exit 1; fi
        case "$2 ${3-}" in
          'library check')
            if [ -f "$HOME/status.json" ]; then cat "$HOME/status.json"; exit; fi
            echo '{"schema_version":4,"revision":"abc","updates":[{"name":"vim","sha256":"123"}]}' ;;
          'library update')
            echo '{"schema_version":4,"revision":"abc","updates":[]}' ;;
          'library remove')
            [ "$4" = vim ] || exit 64
            if grep -qx vim "$HOME/.mackeep.cfg"; then echo 'Still selected' >&2; exit 1; fi
            touch "$HOME/removed-vim"
            echo '{"schema_version":4,"revision":"abc","updates":[],"new":[],"removed":[]}' ;;
          'list ')
            if [ -f "$HOME/removed-vim" ]; then echo '[]'; exit; fi
            echo '[{"schema_version":4,"name":"vim","display_name":"Vim","source":"builtin","cfg_path":"/library/vim.cfg","files":[],"xdg_files":[]}]' ;;
          'config ')
            printf '{"schema_version":4,"version":"0.24.0","config_file":"%s/.mackeep.cfg","custom_apps_dirs":[],"storage":{"engine":"file_system","path":"/tmp","directory":"Mackeep","resolved_backup_dir":"/tmp/Mackeep","exists":false},"apps_to_sync":[],"apps_to_ignore":[],"global_exclude":[]}' "$HOME" ;;
          *) exit 64 ;;
        esac
        """.write(to: tool, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
        try "[applications_to_sync]\n".write(
            to: directory.appendingPathComponent(".mackeep.cfg"), atomically: true, encoding: .utf8)
        return ApplicationsModel(command: MackeepCommand(path: tool.path, home: directory.path))
    }

    func testCheckSetsBadgeAndThrottlesRepeatedAutomaticChecks() async throws {
        let model = try model()
        await model.checkLibraryUpdates()
        await model.checkLibraryUpdates()
        XCTAssertEqual(model.libraryUpdates, ["vim"])
        XCTAssertNotNil(model.libraryCheckedAt)
        XCTAssertNil(model.libraryError)
        XCTAssertFalse(model.isCheckingLibrary)
        XCTAssertTrue(model.newLibraryDefinitions.isEmpty)
        XCTAssertTrue(model.removedLibraryDefinitions.isEmpty)
        let arguments = try String(
            contentsOf: directory.appendingPathComponent("arguments"), encoding: .utf8)
        XCTAssertEqual(arguments, "--json library check\n")
    }

    func testOfflineCheckPreservesKnownUpdates() async throws {
        let model = try model()
        await model.checkLibraryUpdates()
        try Data().write(to: directory.appendingPathComponent("fail"))
        await model.checkLibraryUpdates(force: true)
        XCTAssertEqual(model.libraryUpdates, ["vim"])
        XCTAssertNotNil(model.libraryError)
    }

    func testUpdateClearsBadgeAndReloadsDefinitions() async throws {
        let model = try model()
        await model.checkLibraryUpdates()
        await model.updateLibrary()
        XCTAssertTrue(model.libraryUpdates.isEmpty)
        XCTAssertNil(model.libraryError)
        XCTAssertFalse(model.isUpdatingLibrary)
        XCTAssertEqual(model.applications.map(\.name), ["vim"])
        XCTAssertFalse(try XCTUnwrap(model.applications.first).isCustom)
    }

    func testFailedUpdatePreservesBadge() async throws {
        let model = try model()
        await model.checkLibraryUpdates()
        try Data().write(to: directory.appendingPathComponent("fail"))
        await model.updateLibrary()
        XCTAssertEqual(model.libraryUpdates, ["vim"])
        XCTAssertNotNil(model.libraryError)
        XCTAssertFalse(model.isUpdatingLibrary)
    }

    private func writeExtendedStatus() throws {
        try """
        {"schema_version":4,"revision":"abc",
         "updates":[{"name":"newapp","sha256":"456"}],
         "new":[{"name":"newapp","display_name":"New App"}],"removed":["vim"]}
        """.write(
            to: directory.appendingPathComponent("status.json"), atomically: true, encoding: .utf8)
    }

    func testNewAndRemovedDefinitionsAreAvailableBeforeDownload() async throws {
        let model = try model()
        try writeExtendedStatus()
        await model.checkLibraryUpdates()
        XCTAssertEqual(model.libraryUpdates, ["newapp"])
        XCTAssertEqual(model.newLibraryDefinitions.map(\.name), ["newapp"])
        XCTAssertEqual(model.newLibraryDefinitions.first?.displayName, "New App")
        XCTAssertEqual(model.removedLibraryDefinitions, ["vim"])
        XCTAssertTrue(model.applications.isEmpty)
    }

    func testNewDefinitionCanBeDownloadedIndividually() async throws {
        let model = try model()
        try writeExtendedStatus()
        await model.checkLibraryUpdates()
        await model.updateLibrary(application: "newapp")
        let arguments = try String(
            contentsOf: directory.appendingPathComponent("arguments"), encoding: .utf8)
        XCTAssertTrue(arguments.contains("--json library update newapp\n"))
        XCTAssertNil(model.libraryError)
        XCTAssertTrue(model.newLibraryDefinitions.isEmpty)
    }

    func testRemovedDefinitionIsDeselectedBeforeRemovalWithoutDeletingSettings() async throws {
        let model = try model()
        let loaded = await model.reload()
        XCTAssertTrue(loaded)
        try writeExtendedStatus()
        await model.checkLibraryUpdates()
        let application = try XCTUnwrap(model.applications.first)
        model.addToTheList(application)
        try await model.flushSelection()
        let settings = directory.appendingPathComponent(".vimrc")
        try "personal settings".write(to: settings, atomically: true, encoding: .utf8)
        await model.removeLibraryDefinition(application)
        XCTAssertNil(model.libraryError)
        XCTAssertTrue(model.applications.isEmpty)
        XCTAssertFalse(model.isListed(application))
        XCTAssertTrue(model.removedLibraryDefinitions.isEmpty)
        XCTAssertEqual(try String(contentsOf: settings, encoding: .utf8), "personal settings")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("removed-vim").path))
    }

    func testDefinitionRemovalStopsIfSelectionCannotBeSaved() async throws {
        let model = try model()
        let loaded = await model.reload()
        XCTAssertTrue(loaded)
        try writeExtendedStatus()
        await model.checkLibraryUpdates()
        let application = try XCTUnwrap(model.applications.first)
        let parent = directory.appendingPathComponent("blocked")
        try Data().write(to: parent)
        model.setConfig(MainConfig(
            url: parent.appendingPathComponent("main.cfg"),
            document: INIDocument(text: "[applications_to_sync]\nvim\n")))
        await model.removeLibraryDefinition(application)
        XCTAssertNotNil(model.libraryError)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("removed-vim").path))
    }
}

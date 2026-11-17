import XCTest

@testable import MackeepDesktop

@MainActor
extension SettingsModelTests {
    func testTheExternalPathPolicyIsRead() async throws {
        let model = SettingsModel(
            command: try makeConfig(allowExternalPaths: true), capabilities: nil)
        model.load()
        try await waitForTheSettings(model)
        XCTAssertTrue(model.allowExternalPaths)
        XCTAssertTrue(model.supportsExternalPaths)
    }

    func testUnconfiguredStorageDoesNotShowAnInventedBackupPath() async throws {
        let model = SettingsModel(
            command: try makeConfig(engine: "unconfigured", path: ""), capabilities: nil)
        model.load()
        try await waitForTheSettings(model)
        XCTAssertEqual(model.engine, .unconfigured)
        XCTAssertEqual(model.backupDirectory, "—")
    }

    func testOlderCLIRequiresCLIUpdateAndBlocksOperations() {
        let model = SettingsModel(
            command: nil,
            capabilities: MackeepCapabilities(
                version: "0.25.0", supportsJSON: true, supportsExclusions: true),
            desktopVersion: "0.25.1")
        XCTAssertFalse(model.isToolSupported)
        XCTAssertThrowsError(try model.requireSupportedTool())
        XCTAssertEqual(
            model.toolCompatibilityMessage,
            L10n.string("settings.tool.updateCLI", "0.25.1", "0.25.0"))
    }

    func testOlderDesktopRequiresDesktopUpdate() {
        let model = SettingsModel(
            command: nil,
            capabilities: MackeepCapabilities(
                version: "0.10.0", supportsJSON: true, supportsExclusions: true),
            desktopVersion: "0.9.0")
        XCTAssertFalse(model.isToolSupported)
        XCTAssertEqual(
            model.toolCompatibilityMessage,
            L10n.string("settings.tool.updateDesktop", "0.9.0", "0.10.0"))
    }

    func testMatchingReleaseStillRequiresCompatibleJSON() {
        let model = SettingsModel(
            command: nil,
            capabilities: MackeepCapabilities(
                version: "0.25.1", supportsJSON: false, supportsExclusions: false),
            desktopVersion: "0.25.1")
        XCTAssertFalse(model.isToolSupported)
        XCTAssertThrowsError(try model.requireSupportedTool())
    }

    func testRecheckAcceptsUpdatedCLIWithoutCallingConfigForWrongVersion() async throws {
        let command = try makeConfig()
        let version = directory.appendingPathComponent("version")
        try "0.14.0".write(to: version, atomically: true, encoding: .utf8)
        try """
        #!/bin/sh
        set -eu
        printf '%s\\n' "$*" >> "$HOME/calls"
        case "$1" in
          --version) printf 'Mackeep %s\\n' "$(cat "$HOME/version")" ;;
          --json) cat "$CONFIG" ;;
          *) exit 64 ;;
        esac
        """.write(to: URL(fileURLWithPath: command.path), atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: command.path)
        let model = SettingsModel(command: command, capabilities: nil, desktopVersion: "0.15.1")
        model.refreshToolCompatibility()
        try await waitUntil("Initial compatibility check") { !model.isCheckingTool }
        XCTAssertFalse(model.isToolSupported)
        let calls = directory.appendingPathComponent("calls")
        XCTAssertEqual(try String(contentsOf: calls, encoding: .utf8), "--version\n")

        try "0.15.1".write(to: version, atomically: true, encoding: .utf8)
        model.refreshToolCompatibility()
        try await waitUntil("Updated CLI compatibility check") { !model.isCheckingTool }
        XCTAssertTrue(model.isToolSupported)
        XCTAssertNoThrow(try model.requireSupportedTool())
        XCTAssertEqual(
            try String(contentsOf: calls, encoding: .utf8),
            "--version\n--version\n--json config\n")
    }
}

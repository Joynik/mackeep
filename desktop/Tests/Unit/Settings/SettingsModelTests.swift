import XCTest

@testable import MackeepDesktop

/// The tests of the settings of Mackeep.
@MainActor
final class SettingsModelTests: XCTestCase {
    var directory: URL!
    private var cancellations: [CommandCancellation] = []

    override func setUpWithError() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mackeep-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        for token in cancellations { token.cancel() }
        cancellations.removeAll()
        try? FileManager.default.removeItem(at: directory)
    }

    /// A fake tool that answers the configuration of Mackeep.
    func makeTool() throws -> MackeepCommand {
        let url: URL = directory.appendingPathComponent("mackeep-cli")
        let script: String = """
            #!/bin/sh
            cat "$CONFIG"
            """
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: url.path
        )
        var command = MackeepCommand(path: url.path, home: directory.path)
        let token = CommandCancellation()
        cancellations.append(token)
        command.cancellation = token
        return command
    }

    /// Write the answer of the tool and return the command.
    func makeTool(config: String) throws -> MackeepCommand {
        var command: MackeepCommand = try makeTool()
        let path: URL = directory.appendingPathComponent("config.json")
        try config.write(to: path, atomically: true, encoding: .utf8)
        command.environment["CONFIG"] = path.path
        return command
    }

    /// The answer of the tool with the given values.
    func makeConfig(
        engine: String = "file_system",
        path: String = "/Users/user/dotfiles",
        directory: String = "Mackeep",
        allowExternalPaths: Bool = false,
        projectsEnabled: Bool = false
    ) throws -> MackeepCommand {
        try makeTool(
            config: """
                {
                  "schema_version": 4,
                  "version": "0.15.1",
                  "config_file": "\(self.directory.path)/.mackeep.cfg",
                  "custom_apps_dir": "/Users/user/.mackeep",
                  "custom_apps_dirs": ["/Users/user/.mackeep"],
                  "storage": {
                    "engine": "\(engine)",
                    "path": "\(path)",
                    "directory": "\(directory)",
                    "resolved_backup_dir": "\(path)/\(directory)",
                    "exists": true
                  },
                  "apps_to_sync": [],
                  "apps_to_ignore": [],
                  "global_exclude": ["**/.DS_Store"],
                  "global_xdg_exclude": [],
                  "allow_external_paths": \(allowExternalPaths),
                  "projects_enabled": \(projectsEnabled),
                  "storage_configured": \(engine != "unconfigured")
                }
                """)
    }

    func testDisablingProjectsKeepsDefinitionsAndApplicationPathPolicy() async throws {
        let command = try makeConfig(projectsEnabled: true)
        let model = SettingsModel(command: command, capabilities: nil)
        model.load()
        try await waitForTheSettings(model)
        XCTAssertTrue(model.projectsEnabled)
        let definitions = directory.appendingPathComponent(".mackeep.cfg.projects.json")
        let original = Data("retained project definitions".utf8)
        try original.write(to: definitions)
        model.projectsEnabled = false
        model.save()
        XCTAssertNil(model.presentedError)
        let config = try MainConfig.load(from: directory.appendingPathComponent(".mackeep.cfg"))
        XCTAssertEqual(config.document.value(forKey: "enabled", inSection: "projects"), "false")
        XCTAssertFalse(config.allowExternalPaths)
        XCTAssertEqual(try Data(contentsOf: definitions), original)
    }

    /// Wait for the model to finish the command it runs.
    func waitForTheSettings(_ model: SettingsModel) async throws {
        try await waitUntil("Settings loaded; error: \(String(describing: model.presentedError))") {
            !model.isLoading
        }
    }

    func testTheConfigurationIsRead() async throws {
        let command: MackeepCommand = try makeConfig()
        let model: SettingsModel = SettingsModel(command: command, capabilities: nil)

        model.load()
        try await waitForTheSettings(model)

        XCTAssertEqual(model.engine, .fileSystem)
        XCTAssertEqual(model.directory, "Mackeep")
        XCTAssertEqual(model.storagePath, "/Users/user/dotfiles")
        XCTAssertEqual(model.globalExclude, ["**/.DS_Store"])
        XCTAssertEqual(model.configFilePath, "\(self.directory.path)/.mackeep.cfg")
        XCTAssertEqual(model.customAppsDir, "/Users/user/.mackeep")
    }

    func testTheCustomAppsDirIsTakenFromTheOldAnswer() async throws {
        let command: MackeepCommand = try makeTool(
            config: """
                {
                  "schema_version": 4,
                  "version": "0.15.1",
                  "config_file": "\(self.directory.path)/.mackeep.cfg",
                  "custom_apps_dirs": ["/Users/user/.mackeep"],
                  "storage": {
                    "engine": "file_system",
                    "path": "/Users/user/dotfiles",
                    "directory": "Mackeep",
                    "resolved_backup_dir": "/Users/user/dotfiles/Mackeep",
                    "exists": true
                  },
                  "apps_to_sync": [],
                  "apps_to_ignore": [],
                  "global_exclude": [],
                  "global_xdg_exclude": []
                }
                """)
        let model: SettingsModel = SettingsModel(command: command, capabilities: nil)

        model.load()
        try await waitForTheSettings(model)

        XCTAssertEqual(model.customAppsDir, "/Users/user/.mackeep")
    }

    func testTheBackupFolderIsTakenFromTheTool() async throws {
        let command: MackeepCommand = try makeConfig()
        let model: SettingsModel = SettingsModel(command: command, capabilities: nil)

        model.load()
        try await waitForTheSettings(model)

        XCTAssertEqual(
            model.backupDirectory,
            "/Users/user/dotfiles/Mackeep"
        )
    }

    func testTheBackupFolderIsCountedWithoutTheTool() {
        let model: SettingsModel = SettingsModel(command: nil, capabilities: nil)

        model.engine = .fileSystem
        model.storagePath = "/Users/user/dotfiles"
        model.directory = "Mackeep"

        XCTAssertEqual(
            model.backupDirectory,
            "/Users/user/dotfiles/Mackeep"
        )

        model.engine = .dropbox
        XCTAssertTrue(
            model.backupDirectory.hasSuffix("/Dropbox/Mackeep")
        )
    }

    func testTheVersionIsTakenFromTheCapabilities() {
        let model = SettingsModel(command: nil, capabilities: nil, desktopVersion: "0.18.0")
        XCTAssertEqual(model.mackeepVersion, "")

        model.capabilities = MackeepCapabilities(
            version: "0.18.0",
            supportsJSON: true,
            supportsExclusions: true
        )

        XCTAssertEqual(model.mackeepVersion, "0.18.0")
        XCTAssertTrue(model.isToolKnown)
        XCTAssertTrue(model.isToolSupported)
    }

    func testTheGlobalExclusionsAreChanged() throws {
        let command: MackeepCommand = try makeTool(config: "{}")
        let model: SettingsModel = SettingsModel(command: command, capabilities: nil)

        model.addGlobalExclude("**/.DS_Store")
        model.addGlobalExclude("**/.DS_Store")
        model.addGlobalExclude("  ")

        XCTAssertEqual(model.globalExclude, ["**/.DS_Store"])

        model.removeGlobalExclude("**/.DS_Store")
        XCTAssertTrue(model.globalExclude.isEmpty)
    }

    func testTheAvailabilityOfTheStorage() {
        XCTAssertTrue(StorageEngine.fileSystem.isAvailable)

        // The folder of Dropbox is not there on a Mac without Dropbox
        let home: String = EditorPath.homeDirectory.path
        XCTAssertFalse(
            StorageEngine.dropbox.isAvailable
                && !FileManager.default.fileExists(
                    atPath: (home as NSString).appendingPathComponent("Dropbox")
                )
        )
    }
}

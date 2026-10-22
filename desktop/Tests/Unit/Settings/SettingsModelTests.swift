import XCTest

@testable import MackeepDesktop

/// The tests of the settings of Mackeep.
@MainActor
final class SettingsModelTests: XCTestCase {
    private var directory: URL!
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
    private func makeTool() throws -> MackeepCommand {
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
    private func makeTool(config: String) throws -> MackeepCommand {
        var command: MackeepCommand = try makeTool()
        let path: URL = directory.appendingPathComponent("config.json")
        try config.write(to: path, atomically: true, encoding: .utf8)
        command.environment["CONFIG"] = path.path
        return command
    }

    /// The answer of the tool with the given values.
    private func makeConfig(
        engine: String = "file_system",
        path: String = "/Users/user/dotfiles",
        directory: String = "Mackeep",
        allowExternalPaths: Bool = false
    ) throws -> MackeepCommand {
        try makeTool(config: """
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
          "storage_configured": \(engine != "unconfigured")
        }
        """)
    }

    /// Wait for the model to finish the command it runs.
    private func waitForTheSettings(_ model: SettingsModel) async throws {
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
        let command: MackeepCommand = try makeTool(config: """
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

    func testTheStorageIsWrittenInTheConfigFile() async throws {
        let configURL: URL = directory.appendingPathComponent(".mackeep.cfg")
        try "[storage]\nengine = file_system\npath = /Users/user/dotfiles\n".write(
            to: configURL,
            atomically: true,
            encoding: .utf8
        )

        // The tool answers the config file, the model writes it
        let command: MackeepCommand = try makeTool(config: """
        {
          "schema_version": 4,
          "version": "0.20.0",
          "config_file": "\(configURL.path)",
          "custom_apps_dir": "/Users/user/.mackeep",
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

        // The user changes the path of the storage and the name of the folder
        model.storagePath = "/Users/user/other"
        model.directory = "Backups"
        model.addGlobalExclude("**/*.log")
        model.save()

        // The values are in the config file
        let saved: MainConfig = try MainConfig.load(from: configURL)
        XCTAssertEqual(saved.storageEngine, "file_system")
        XCTAssertEqual(saved.storagePath, "/Users/user/other")
        XCTAssertEqual(saved.storageDirectory, "Backups")
        XCTAssertEqual(saved.globalExclude, ["**/*.log"])
    }

    func testTheBackupFolderIsTakenFromTheTool() async throws {        let command: MackeepCommand = try makeConfig()
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
        let model: SettingsModel = SettingsModel(command: nil, capabilities: nil)
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

    func testTheStorageIsWritten() throws {
        let configURL: URL = directory.appendingPathComponent(".mackeep.cfg")
        try "[storage]\nengine = dropbox\n".write(
            to: configURL,
            atomically: true,
            encoding: .utf8
        )
        let config: MainConfig = try MainConfig.load(from: configURL)

        config.setStorage(
            engine: "file_system",
            path: "/Users/user/dotfiles",
            directory: "Backups"
        )
        config.setGlobalExclude(["**/.DS_Store"])
        try config.save()

        let saved: MainConfig = try MainConfig.load(from: configURL)
        XCTAssertEqual(saved.storageEngine, "file_system")
        XCTAssertEqual(saved.storagePath, "/Users/user/dotfiles")
        XCTAssertEqual(saved.storageDirectory, "Backups")
        XCTAssertEqual(saved.globalExclude, ["**/.DS_Store"])
    }
    func testTheExternalPathPolicyIsRead() async throws {
        let model = SettingsModel(command: try makeConfig(allowExternalPaths: true), capabilities: nil)
        model.load()
        try await waitForTheSettings(model)
        XCTAssertTrue(model.allowExternalPaths)
        XCTAssertTrue(model.supportsExternalPaths)
    }

    func testUnconfiguredStorageDoesNotShowAnInventedBackupPath() async throws {
        let model = SettingsModel(command: try makeConfig(engine: "unconfigured", path: ""), capabilities: nil)
        model.load()
        try await waitForTheSettings(model)
        XCTAssertEqual(model.engine, .unconfigured)
        XCTAssertEqual(model.backupDirectory, "—")
    }

}

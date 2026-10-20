import XCTest

@testable import MackeepDesktop

/// The tests of the settings of Mackeep.
@MainActor
final class SettingsModelTests: XCTestCase {
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
        return MackeepCommand(path: url.path, home: directory.path)
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
        directory: String = "Mackeep"
    ) throws -> MackeepCommand {
        try makeTool(config: """
        {
          "schema_version": 1,
          "version": "0.15.1",
          "config_file": "/Users/user/.mackeep.cfg",
          "config_file_is_legacy": false,
          "custom_apps_dirs": ["/Users/user/.mackeep"],
          "legacy_custom_apps_dirs": [],
          "storage": {
            "engine": "\(engine)",
            "path": "\(path)",
            "directory": "\(directory)",
            "resolved_backup_dir": "\(path)/\(directory)",
            "exists": true,
            "using_legacy_directory": false
          },
          "apps_to_sync": [],
          "apps_to_ignore": [],
          "global_exclude": ["**/.DS_Store"],
          "global_xdg_exclude": []
        }
        """)
    }

    func testTheConfigurationIsRead() throws {
        let command: MackeepCommand = try makeConfig()
        let model: SettingsModel = SettingsModel(command: command, capabilities: nil)

        model.load()

        XCTAssertEqual(model.engine, .fileSystem)
        XCTAssertEqual(model.directory, "Mackeep")
        XCTAssertEqual(model.storagePath, "/Users/user/dotfiles")
        XCTAssertEqual(model.globalExclude, ["**/.DS_Store"])
        XCTAssertEqual(model.configFilePath, "/Users/user/.mackeep.cfg")
        XCTAssertEqual(model.customAppsDirs, ["/Users/user/.mackeep"])
    }

    func testTheBackupFolderIsTakenFromTheTool() throws {
        let command: MackeepCommand = try makeConfig()
        let model: SettingsModel = SettingsModel(command: command, capabilities: nil)

        model.load()

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
        let home: String = NSHomeDirectory()
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
}

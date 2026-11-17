import XCTest

@testable import MackeepDesktop

@MainActor
extension SettingsModelTests {
    func testTheStorageIsWrittenInTheConfigFile() async throws {
        let configURL: URL = directory.appendingPathComponent(".mackeep.cfg")
        try "[storage]\nengine = file_system\npath = /Users/user/dotfiles\n".write(
            to: configURL,
            atomically: true,
            encoding: .utf8
        )

        // The tool answers the config file, the model writes it
        let command: MackeepCommand = try makeTool(
            config: """
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

import XCTest

@testable import MackeepDesktop

/// The tests of the models of the JSON answers.
final class MackeepModelsTests: XCTestCase {
    /// The content of a file of the test bundle.
    private func fixture(_ name: String) throws -> Data {
        let url: URL = try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: name, withExtension: "json"),
            "The fixture \(name) is missing"
        )
        return try Data(contentsOf: url)
    }

    func testTheConfigIsDecoded() throws {
        let data: Data = try fixture("config")
        let config: MackeepConfig = try JSONDecoder().decode(MackeepConfig.self, from: data)

        XCTAssertEqual(config.schemaVersion, MackeepSchema.version)
        XCTAssertEqual(config.version, "0.15.1")
        XCTAssertEqual(config.configFile, "/Users/user/.mackeep.cfg")
        XCTAssertEqual(config.configFileIsLegacy, false)
        XCTAssertEqual(config.customAppsDirs.count, 2)
        XCTAssertEqual(config.legacyCustomAppsDirs?.count, 2)
        XCTAssertEqual(config.storage.engine, "file_system")
        XCTAssertEqual(config.storage.directory, "Mackeep")
        XCTAssertEqual(config.storage.resolvedBackupDir, "/Users/user/dotfiles/Mackeep")
        XCTAssertEqual(config.storage.exists, true)
        XCTAssertEqual(config.storage.usingLegacyDirectory, false)
        XCTAssertEqual(config.appsToSync, ["vim"])
        XCTAssertEqual(config.appsToIgnore, [])
        XCTAssertEqual(config.globalExclude, ["**/.DS_Store"])
    }

    func testTheListIsDecoded() throws {
        let data: Data = try fixture("list")
        let applications: [MackeepApplication] = try JSONDecoder().decode(
            [MackeepApplication].self,
            from: data
        )

        XCTAssertEqual(applications.count, 2)
        XCTAssertEqual(applications[0].name, "demo")
        XCTAssertEqual(applications[0].displayName, "Demo")
        XCTAssertEqual(applications[0].source, .custom)
        XCTAssertTrue(applications[0].isCustom)
        XCTAssertEqual(applications[0].files.first?.path, "appdir")
        XCTAssertEqual(applications[0].files.first?.isDir, true)
        XCTAssertEqual(applications[0].exclude, ["appdir/cache"])
        XCTAssertEqual(applications[1].source, .builtin)
        XCTAssertFalse(applications[1].isCustom)
    }

    func testThePlanIsDecoded() throws {
        let data: Data = try fixture("plan")
        let plan: MackeepPlan = try JSONDecoder().decode(MackeepPlan.self, from: data)

        XCTAssertEqual(plan.actions.count, 3)
        XCTAssertEqual(plan.actions[0].action, "skip_excluded")
        XCTAssertEqual(plan.actions[0].reason?.pattern, "appdir/cache")
        XCTAssertEqual(plan.actions[0].reason?.section, "exclude")
        XCTAssertEqual(plan.actions[1].sizeBytes, 42)
        XCTAssertEqual(plan.actions[2].wouldOverwrite, true)
        XCTAssertEqual(plan.summary.totalActions, 3)
        XCTAssertEqual(plan.summary.totalBytes, 42)
        XCTAssertEqual(plan.summary.files, 1)
        XCTAssertEqual(plan.summary.actions["skip_excluded"], 1)
    }

    func testAnOldAnswerIsStillDecoded() throws {
        // The answer of a version of Mackeep without the legacy paths
        let json: String = """
        {
          "schema_version": 1,
          "version": "0.13.0",
          "config_file": "/Users/user/.mackeep.cfg",
          "custom_apps_dirs": [],
          "storage": {
            "engine": "dropbox",
            "path": "/Users/user/Dropbox",
            "directory": "Mackeep",
            "resolved_backup_dir": "/Users/user/Dropbox/Mackeep",
            "exists": false
          },
          "apps_to_sync": [],
          "apps_to_ignore": [],
          "global_exclude": []
        }
        """
        let config: MackeepConfig = try JSONDecoder().decode(
            MackeepConfig.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(config.version, "0.13.0")
        XCTAssertNil(config.configFileIsLegacy)
        XCTAssertNil(config.legacyCustomAppsDirs)
        XCTAssertNil(config.storage.usingLegacyDirectory)
    }

    func testTheEventsAreDecoded() throws {
        let lines: [String] = [
            #"{"schema_version": 1, "event": "start", "app": "demo", "action": "backup"}"#,
            #"{"schema_version": 1, "event": "file", "app": "demo", "action": "copy", "src": "/a", "dst": "/b", "size_bytes": 3}"#,
            #"{"schema_version": 1, "event": "done", "app": "demo", "action": "backup", "files": 1, "bytes": 3, "skipped": 0}"#,
        ]
        let decoder: JSONDecoder = JSONDecoder()
        var events: [MackeepEvent] = []
        for line in lines {
            events.append(
                try decoder.decode(MackeepEvent.self, from: Data(line.utf8))
            )
        }

        XCTAssertEqual(events[0].event, "start")
        XCTAssertEqual(events[0].app, "demo")
        XCTAssertEqual(events[1].sizeBytes, 3)
        XCTAssertEqual(events[2].files, 1)
        XCTAssertEqual(events[2].bytes, 3)
        XCTAssertEqual(events[2].skipped, 0)
    }
}

import XCTest

@testable import MackeepDesktop

/// The tests of the backup section.
private let backupModelToolScript = """
    #!/bin/sh
    set -eu
    printf '%s\n' "$*" >> "$HOME/arguments"
    [ "$1" = "--json" ] || exit 64
    action="$2"
    shift 2
    if [ "$action" = "config" ]; then
      [ "$#" -eq 0 ] || exit 64
      cat "$CONFIG"
      exit
    fi
    case "$action" in backup|restore) ;; *) exit 64 ;; esac
    preview=0
    force=0
    scoped=0
    for argument in "$@"; do
      case "$argument" in
        --dry-run) preview=$((preview + 1));;
        --force) force=$((force + 1));;
        demo) scoped=$((scoped + 1));;
        *) exit 64;;
      esac
    done
    [ "$scoped" -le 1 ] && [ "$preview" -le 1 ] && [ "$force" -le 1 ] || exit 64
    if [ "$preview" -eq 1 ]; then
      [ "$force" -eq 0 ] || exit 64
      cat "$PLAN"
      exit
    fi
    if [ "$action" = "restore" ]; then
      [ "$force" -eq 1 ] || exit 64
    else
      [ "$force" -eq 0 ] || exit 64
    fi
    printf '{"schema_version":4,"event":"start","app":"demo","action":"%s"}\n' "$action"
    echo '{"schema_version":4,"event":"file","app":"demo","action":"copy",\
    "src":"/a/b.txt","dst":"/c/b.txt","size_bytes":12}'
    printf '{"schema_version":4,"event":"done","app":"demo","action":"%s",\
    "files":1,"bytes":12,"skipped":0}\n' "$action"
    """

@MainActor
final class BackupModelTests: XCTestCase {
    var directory: URL!

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

    /// A fake tool that answers the commands of the backup.
    func makeTool(
        plan: String = """
        {
          "schema_version": 4,
          "actions": [
            {
              "app": "demo", "action": "copy", "src": "/a/b.txt",
              "dst": "/c/b.txt", "size_bytes": 12
            }
          ],
          "summary": {"apps": ["demo"], "actions": {"copy": 1},
                        "total_actions": 1, "total_bytes": 12, "files": 1}
        }
        """
    ) throws -> MackeepCommand {
        let url: URL = directory.appendingPathComponent("mackeep-cli")
        let script = backupModelToolScript
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: url.path
        )
        try plan.write(
            to: directory.appendingPathComponent("plan.json"),
            atomically: true,
            encoding: .utf8
        )
        var command = MackeepCommand(path: url.path, home: directory.path)
        let fixture = URL(fileURLWithPath: MackeepCommandTests.fixtureDirectory)
            .appendingPathComponent("config.json")
        var config = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: fixture)) as? [String: Any])
        config["supports_safe_cancellation"] = true
        let configURL = directory.appendingPathComponent("config.json")
        try JSONSerialization.data(withJSONObject: config).write(to: configURL)
        command.environment["CONFIG"] = configURL.path
        command.environment["PLAN"] = directory.appendingPathComponent("plan.json").path
        return command
    }

    /// Wait for the model to finish the command it runs.
    func waitForThePlan(_ model: BackupModel) async throws {
        do {
            try await waitUntil(
                "Backup stopped; error: \(String(describing: model.presentedError))"
            ) {
                !model.isRunning
            }
        } catch {
            model.cancel()
            throw error
        }
    }

    func testThePlanIsRead() async throws {
        var command: MackeepCommand = try makeTool()
        command.environment["PLAN"] = directory.appendingPathComponent("plan.json").path
        let model: BackupModel = BackupModel(
            command: command,
            historyStore: HistoryStore(url: directory.appendingPathComponent("history.json"))
        )

        model.dryRun()
        try await waitForThePlan(model)

        XCTAssertNotNil(model.plan)
        XCTAssertEqual(model.plan?.actions.count, 1)
        XCTAssertEqual(model.visibleActions.count, 1)
        XCTAssertEqual(model.summary?.totalBytes, 12)
    }

    func testOverwriteRowsAreHiddenForBackupAndCombinedForRestore() async throws {
        let plan = """
            {"schema_version":4,"actions":[
              {"app":"demo","action":"copy","src":"/a","dst":"/b","size_bytes":12},
              {"app":"demo","action":"conflict","src":"/a","dst":"/b","size_bytes":12},
              {"app":"demo","action":"conflict","src":"/c","dst":"/d","size_bytes":3,"would_overwrite":true}
            ],"summary":{"apps":["demo"],"actions":{"copy":1,"conflict":2},
            "total_actions":3,"total_bytes":15,"files":2}}
            """
        let model = BackupModel(
            command: try makeTool(plan: plan),
            historyStore: HistoryStore(url: directory.appendingPathComponent("history.json")))
        model.dryRun()
        try await waitForThePlan(model)
        XCTAssertEqual(model.visibleActions.map(\.action), ["copy"])
        XCTAssertFalse(model.availableFilters.contains(.conflict))
        XCTAssertFalse(model.willOverwrite(try XCTUnwrap(model.visibleActions.first)))
        model.dryRunRestore()
        try await waitForThePlan(model)
        XCTAssertEqual(model.visibleActions.map(\.action), ["copy", "copy"])
        XCTAssertTrue(model.visibleActions.allSatisfy { model.willOverwrite($0) })
        model.filter = .copy
        XCTAssertEqual(model.visibleActions.count, 2)
    }

    func testExecutionOverwriteFlagReachesTheTableRow() throws {
        let event = try JSONDecoder().decode(
            MackeepEvent.self,
            from: Data(
                """
                {"schema_version":4,"event":"file","app":"demo",
                "action":"copy","src":"/a","dst":"/b","would_overwrite":true}
                """.utf8))
        XCTAssertEqual(event.actionRow?.wouldOverwrite, true)
    }

    func testTheFilterKeepsTheActions() async throws {
        var command: MackeepCommand = try makeTool()
        command.environment["PLAN"] = directory.appendingPathComponent("plan.json").path
        let model: BackupModel = BackupModel(
            command: command,
            historyStore: HistoryStore(url: directory.appendingPathComponent("history.json"))
        )
        model.dryRun()
        try await waitForThePlan(model)

        model.filter = .copy
        XCTAssertEqual(model.visibleActions.count, 1)

        model.filter = .conflict
        XCTAssertEqual(model.visibleActions.count, 0)
    }

    func testTheHistoryIsKept() throws {
        let store: HistoryStore = HistoryStore(
            url: directory.appendingPathComponent("history.json")
        )
        let record: RunRecord = RunRecord(
            command: "backup",
            application: "demo",
            succeeded: true,
            files: 2,
            bytes: 42
        )

        try store.append(record)
        let loaded: [RunRecord] = try store.load()

        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.command, "backup")
        XCTAssertEqual(loaded.first?.files, 2)
        XCTAssertEqual(loaded.first?.bytes, 42)
    }
    func testRunTotalsIncludeEveryApplication() async throws {
        let command = try makeTool()
        let toolURL = URL(fileURLWithPath: command.path)
        var script = try String(contentsOf: toolURL, encoding: .utf8)
        script += "\necho '{\"schema_version\":4,\"event\":\"start\",\"app\":\"second\"}'\n"
        script +=
            "\necho '{\"schema_version\":4,\"event\":\"done\",\"app\":\"second\","
            + "\"action\":\"backup\",\"files\":2,\"bytes\":8}'\n"
        try script.write(to: toolURL, atomically: true, encoding: .utf8)
        let model = BackupModel(
            command: command,
            historyStore: HistoryStore(url: directory.appendingPathComponent("run-history.json"))
        )
        model.backup()
        try await waitForThePlan(model)
        XCTAssertEqual(model.history.first?.files, 3)
        XCTAssertEqual(model.history.first?.bytes, 20)
    }

    func testExecutionRowsComeFromEventsAndAreReplacedByAPreview() async throws {
        var command = try makeTool()
        command.environment["PLAN"] = directory.appendingPathComponent("plan.json").path
        let model = BackupModel(
            command: command,
            historyStore: HistoryStore(url: directory.appendingPathComponent("history.json")))

        model.backup()
        try await waitForThePlan(model)
        XCTAssertEqual(model.displayedCommand, "backup")
        XCTAssertFalse(model.isPreview)
        XCTAssertEqual(model.executionActions.first?.src, "/a/b.txt")
        XCTAssertEqual(model.summary?.totalActions, 1)
        XCTAssertEqual(model.summary?.totalBytes, 12)
        XCTAssertEqual(model.lastRun?.succeeded, true)
        model.filter = .conflict
        XCTAssertTrue(model.visibleActions.isEmpty)

        model.dryRunRestore()
        try await waitForThePlan(model)
        XCTAssertEqual(model.displayedCommand, "restore")
        XCTAssertTrue(model.isPreview)
        XCTAssertNil(model.lastRun)
        XCTAssertEqual(model.visibleActions.count, 1)

        model.restore()
        try await waitForThePlan(model)
        XCTAssertEqual(model.displayedCommand, "restore")
        XCTAssertFalse(model.isPreview)
        XCTAssertEqual(model.executionActions.count, 1)
        XCTAssertEqual(model.lastRun?.command, "restore")
    }
}

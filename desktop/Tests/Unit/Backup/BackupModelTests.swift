import XCTest

@testable import MackeepDesktop

/// The tests of the backup section.
@MainActor
final class BackupModelTests: XCTestCase {
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

    /// A fake tool that answers the commands of the backup.
    private func makeTool(
        plan: String = """
        {
          "schema_version": 4,
          "actions": [
            {"app": "demo", "action": "copy", "src": "/a/b.txt", "dst": "/c/b.txt", "size_bytes": 12}
          ],
          "summary": {"apps": ["demo"], "actions": {"copy": 1}, "total_actions": 1, "total_bytes": 12, "files": 1}
        }
        """
    ) throws -> MackeepCommand {
        let url: URL = directory.appendingPathComponent("mackeep-cli")
        let script: String = """
        #!/bin/sh
        if [ "$2" = "config" ]; then
          cat "$CONFIG"
          exit 0
        fi
        if [ "$4" = "--dry-run" ] || [ "$3" = "--dry-run" ]; then
          cat "$PLAN"
          exit 0
        fi
        echo '{"schema_version": 4, "event": "start", "app": "demo", "action": "backup"}'
        echo '{"schema_version": 4, "event": "file", "app": "demo", "action": "copy", "src": "/a/b.txt", "dst": "/c/b.txt", "size_bytes": 12}'
        echo '{"schema_version": 4, "event": "done", "app": "demo", "action": "backup", "files": 1, "bytes": 12, "skipped": 0}'
        """
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
        let fixture = MackeepCommandTests.fixtureDirectory + "/config.json"
        command.environment["CONFIG"] = fixture
        return command
    }

    /// Wait for the model to finish the command it runs.
    private func waitForThePlan(_ model: BackupModel) async {
        while model.isRunning {
            try? await Task.sleep(for: .milliseconds(10))
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
        await waitForThePlan(model)

        XCTAssertNotNil(model.plan)
        XCTAssertEqual(model.plan?.actions.count, 1)
        XCTAssertEqual(model.visibleActions.count, 1)
        XCTAssertEqual(model.summary?.totalBytes, 12)
    }

    func testTheFilterKeepsTheActions() async throws {
        var command: MackeepCommand = try makeTool()
        command.environment["PLAN"] = directory.appendingPathComponent("plan.json").path
        let model: BackupModel = BackupModel(
            command: command,
            historyStore: HistoryStore(url: directory.appendingPathComponent("history.json"))
        )
        model.dryRun()
        await waitForThePlan(model)

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

        store.append(record)
        let loaded: [RunRecord] = store.load()

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
        script += "\necho '{\"schema_version\":4,\"event\":\"done\",\"app\":\"second\",\"action\":\"backup\",\"files\":2,\"bytes\":8}'\n"
        try script.write(to: toolURL, atomically: true, encoding: .utf8)
        let model = BackupModel(
            command: command,
            historyStore: HistoryStore(url: directory.appendingPathComponent("run-history.json"))
        )
        model.backup()
        await waitForThePlan(model)
        XCTAssertEqual(model.history.first?.files, 3)
        XCTAssertEqual(model.history.first?.bytes, 20)
    }

    func testPreparingAPlanClearsThePreviousExecutionLog() async throws {
        var command = try makeTool()
        command.environment["PLAN"] = directory.appendingPathComponent("plan.json").path
        let model = BackupModel(
            command: command,
            historyStore: HistoryStore(url: directory.appendingPathComponent("history.json")))
        model.backup()
        await waitForThePlan(model)
        XCTAssertFalse(model.log.isEmpty)
        model.dryRun()
        await waitForThePlan(model)
        XCTAssertTrue(model.log.isEmpty)
        XCTAssertNotNil(model.plan)
    }

    func testFailedPreparationNeverStartsAnOperation() async throws {
        let command = try makeTool()
        let model = BackupModel(
            command: command,
            historyStore: HistoryStore(url: directory.appendingPathComponent("history.json")),
            prepare: { throw CocoaError(.fileWriteNoPermission) })
        model.backup()
        await waitForThePlan(model)
        XCTAssertNotNil(model.presentedError)
        XCTAssertTrue(model.history.isEmpty)
        XCTAssertTrue(model.log.isEmpty)
    }

    func testFailedRestorePreviewClearsAnEarlierPlan() async throws {
        var command = try makeTool()
        command.environment["PLAN"] = directory.appendingPathComponent("plan.json").path
        let model = BackupModel(
            command: command,
            historyStore: HistoryStore(url: directory.appendingPathComponent("history.json")))
        model.dryRun()
        await waitForThePlan(model)
        XCTAssertNotNil(model.plan)
        try FileManager.default.removeItem(at: directory.appendingPathComponent("plan.json"))
        model.dryRunRestore()
        XCTAssertNil(model.plan)
        await waitForThePlan(model)
        XCTAssertNil(model.plannedCommand)
        XCTAssertNotNil(model.presentedError)
        model.restore()
        XCTAssertFalse(model.isRunning)
    }

}

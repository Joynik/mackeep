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
          "schema_version": 1,
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
        if [ "$4" = "--dry-run" ] || [ "$3" = "--dry-run" ]; then
          cat "$PLAN"
          exit 0
        fi
        echo '{"schema_version": 1, "event": "start", "app": "demo", "action": "backup"}'
        echo '{"schema_version": 1, "event": "file", "app": "demo", "action": "copy", "src": "/a/b.txt", "dst": "/c/b.txt", "size_bytes": 12}'
        echo '{"schema_version": 1, "event": "done", "app": "demo", "action": "backup", "files": 1, "bytes": 12, "skipped": 0}'
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
        return MackeepCommand(path: url.path, home: directory.path)
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
            historyStore: HistoryStore()
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
            historyStore: HistoryStore()
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
}

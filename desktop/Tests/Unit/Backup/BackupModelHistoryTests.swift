import XCTest

@testable import MackeepDesktop

@MainActor
extension BackupModelTests {
    func testHistoryIsClearedFromTheModelAndDisk() throws {
        let store = HistoryStore(url: directory.appendingPathComponent("history.json"))
        try store.append(RunRecord(command: "backup", succeeded: true))
        let model = BackupModel(command: nil, historyStore: store)
        XCTAssertEqual(model.history.count, 1)

        model.clearHistory()

        XCTAssertTrue(model.history.isEmpty)
        XCTAssertTrue(try store.load().isEmpty)
        XCTAssertNil(model.presentedError)
        model.clearHistory()
        XCTAssertNil(model.presentedError)
    }

    func testLargeRunsKeepFullTotalsWhenTheTableIsTruncated() async throws {
        let command = try makeTool()
        let tool = URL(fileURLWithPath: command.path)
        var script = try String(contentsOf: tool, encoding: .utf8)
        script +=
            "\n" + """
                echo '{"schema_version":4,"event":"start","app":"large"}'
                i=0
                while [ $i -lt 5010 ]; do
                  printf '{"schema_version":4,"event":"file",\
                "app":"large","action":"copy","src":"/file-%s","size_bytes":1}\\n' "$i"
                  i=$((i + 1))
                done
                echo '{"schema_version":4,"event":"done","app":"large","files":5010,"bytes":5010}'
                """ + "\n"
        try script.write(to: tool, atomically: true, encoding: .utf8)
        let model = BackupModel(
            command: command,
            historyStore: HistoryStore(url: directory.appendingPathComponent("history.json")))

        model.backup()
        try await waitForThePlan(model)

        XCTAssertNil(model.presentedError)
        XCTAssertEqual(model.executionActions.count, BackupModel.actionLimit)
        XCTAssertEqual(model.summary?.totalActions, 5011)
        XCTAssertEqual(model.summary?.truncated, true)
        XCTAssertEqual(model.lastRun?.files, 5011)
        XCTAssertEqual(model.lastRun?.bytes, 5022)
    }

    func testFailedHistoryCleanupPreservesRecordsAndUnexpectedContents() throws {
        let url = directory.appendingPathComponent("history.json")
        let store = HistoryStore(url: url)
        try store.append(RunRecord(command: "backup", succeeded: true))
        let model = BackupModel(command: nil, historyStore: store)
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        let unexpected = url.appendingPathComponent("keep.txt")
        try "Keep".write(to: unexpected, atomically: true, encoding: .utf8)

        model.clearHistory()

        XCTAssertEqual(model.history.count, 1)
        XCTAssertNotNil(model.presentedError)
        XCTAssertTrue(FileManager.default.fileExists(atPath: unexpected.path))
    }

    func testExecutionRowsPreserveStaleRemovalFlags() throws {
        let json = """
            {"schema_version":4,"event":"file","app":"demo","action":"stale_in_backup",
            "src":"/old","will_remove":true}
            """
        let event = try JSONDecoder().decode(MackeepEvent.self, from: Data(json.utf8))
        XCTAssertEqual(event.actionRow?.willRemove, true)
        XCTAssertEqual(event.actionRow?.src, "/old")
    }
}

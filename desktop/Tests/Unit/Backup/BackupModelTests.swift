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
        set -eu
        printf '%s\\n' "$*" >> "$HOME/arguments"
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
        printf '{"schema_version":4,"event":"start","app":"demo","action":"%s"}\\n' "$action"
        echo '{"schema_version":4,"event":"file","app":"demo","action":"copy","src":"/a/b.txt","dst":"/c/b.txt","size_bytes":12}'
        printf '{"schema_version":4,"event":"done","app":"demo","action":"%s","files":1,"bytes":12,"skipped":0}\\n' "$action"
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
    private func waitForThePlan(_ model: BackupModel) async throws {
        do {
            try await waitUntil("Backup stopped; error: \(String(describing: model.presentedError))") {
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
        try await waitForThePlan(model)
        XCTAssertEqual(model.history.first?.files, 3)
        XCTAssertEqual(model.history.first?.bytes, 20)
    }

    func testPreparingAPlanClearsPreviousExecutionResults() async throws {
        var command = try makeTool()
        command.environment["PLAN"] = directory.appendingPathComponent("plan.json").path
        let model = BackupModel(
            command: command,
            historyStore: HistoryStore(url: directory.appendingPathComponent("history.json")))
        model.backup()
        try await waitForThePlan(model)
        XCTAssertFalse(model.executionActions.isEmpty)
        model.dryRun()
        try await waitForThePlan(model)
        XCTAssertTrue(model.executionActions.isEmpty)
        XCTAssertNotNil(model.plan)
    }

    func testFailedPreparationNeverStartsAnOperation() async throws {
        let command = try makeTool()
        let model = BackupModel(
            command: command,
            historyStore: HistoryStore(url: directory.appendingPathComponent("history.json")),
            prepare: { throw CocoaError(.fileWriteNoPermission) })
        model.backup()
        try await waitForThePlan(model)
        XCTAssertNotNil(model.presentedError)
        XCTAssertTrue(model.history.isEmpty)
        XCTAssertTrue(model.executionActions.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("arguments").path))
    }

    func testFailedRestorePreviewClearsAnEarlierPlan() async throws {
        var command = try makeTool()
        command.environment["PLAN"] = directory.appendingPathComponent("plan.json").path
        let model = BackupModel(
            command: command,
            historyStore: HistoryStore(url: directory.appendingPathComponent("history.json")))
        model.dryRun()
        try await waitForThePlan(model)
        XCTAssertNotNil(model.plan)
        try FileManager.default.removeItem(at: directory.appendingPathComponent("plan.json"))
        model.dryRunRestore()
        XCTAssertNil(model.plan)
        try await waitForThePlan(model)
        XCTAssertNil(model.plannedCommand)
        XCTAssertNotNil(model.presentedError)
        model.restore()
        XCTAssertFalse(model.isRunning)
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

    func testHistoryIsClearedFromTheModelAndDisk() {
        let store = HistoryStore(url: directory.appendingPathComponent("history.json"))
        store.append(RunRecord(command: "backup", succeeded: true))
        let model = BackupModel(command: nil, historyStore: store)
        XCTAssertEqual(model.history.count, 1)

        model.clearHistory()

        XCTAssertTrue(model.history.isEmpty)
        XCTAssertTrue(store.load().isEmpty)
        XCTAssertNil(model.presentedError)
        model.clearHistory()
        XCTAssertNil(model.presentedError)
    }

    func testLargeRunsKeepFullTotalsWhenTheTableIsTruncated() async throws {
        let command = try makeTool()
        let tool = URL(fileURLWithPath: command.path)
        var script = try String(contentsOf: tool, encoding: .utf8)
        script += "\n" + #"""
        echo '{"schema_version":4,"event":"start","app":"large"}'
        i=0
        while [ $i -lt 5010 ]; do
          printf '{"schema_version":4,"event":"file","app":"large","action":"copy","src":"/file-%s","size_bytes":1}\n' "$i"
          i=$((i + 1))
        done
        echo '{"schema_version":4,"event":"done","app":"large","files":5010,"bytes":5010}'
        """# + "\n"
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
        store.append(RunRecord(command: "backup", succeeded: true))
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
        let json = #"{"schema_version":4,"event":"file","app":"demo","action":"stale_in_backup","src":"/old","will_remove":true}"#
        let event = try JSONDecoder().decode(MackeepEvent.self, from: Data(json.utf8))
        XCTAssertEqual(event.actionRow?.willRemove, true)
        XCTAssertEqual(event.actionRow?.src, "/old")
    }

    func testScopedCommandsKeepTheirArgumentsAndConfirmedRestore() async throws {
        let command = try makeTool()
        let model = BackupModel(
            command: command,
            historyStore: HistoryStore(url: directory.appendingPathComponent("history.json")))
        model.dryRun(application: "demo")
        try await waitForThePlan(model)
        model.backup(application: "demo")
        try await waitForThePlan(model)
        model.dryRunRestore(application: "demo")
        try await waitForThePlan(model)
        model.restore(application: "demo")
        try await waitForThePlan(model)
        XCTAssertNil(model.presentedError)
        let arguments = try String(
            contentsOf: directory.appendingPathComponent("arguments"), encoding: .utf8)
            .split(separator: "\n").map(String.init)
        XCTAssertEqual(arguments, [
            "--json backup demo --dry-run", "--json config", "--json backup demo",
            "--json restore demo --dry-run", "--json config", "--json restore demo --force",
        ])
        XCTAssertEqual(model.history.map(\.command).sorted(), ["backup", "restore"])
        XCTAssertTrue(model.history.allSatisfy(\.succeeded))
    }

    func testCancelledPreparationNeverLaunchesThePreview() async throws {
        let command = try makeTool()
        var entered = false
        var resume: CheckedContinuation<Void, Never>?
        let model = BackupModel(
            command: command,
            historyStore: HistoryStore(url: directory.appendingPathComponent("history.json")),
            prepare: {
                entered = true
                await withCheckedContinuation { resume = $0 }
            })
        model.dryRun()
        try await waitUntil("Preparation started") { entered }
        model.cancel()
        resume?.resume()
        try await waitForThePlan(model)
        XCTAssertNil(model.plan)
        XCTAssertNil(model.plannedCommand)
        XCTAssertNil(model.presentedError)
        XCTAssertTrue(model.history.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("arguments").path))
    }

    func testCancellationDuringStreamingRecordsAnUnsuccessfulCompletedRun() async throws {
        let command = try makeTool()
        let tool = URL(fileURLWithPath: command.path)
        var script = try String(contentsOf: tool, encoding: .utf8)
        let insertion = """
        trap 'echo "{\"schema_version\":4,\"event\":\"done\",\"app\":\"demo\",\"files\":1,\"bytes\":12}"; exit 130' USR1
        echo $$ > "$HOME/pid"
        touch "$HOME/stream-started"
        i=0
        while [ "$i" -lt 500 ]; do
          sleep 0.01
          i=$((i + 1))
        done
        exit 75
        """
        let completion = try XCTUnwrap(script.range(of: #"printf '{"schema_version":4,"event":"done""#))
        script.replaceSubrange(completion.lowerBound..<script.endIndex, with: insertion + "\n")
        try script.write(to: tool, atomically: true, encoding: .utf8)
        let model = BackupModel(
            command: command,
            historyStore: HistoryStore(url: directory.appendingPathComponent("history.json")))
        model.backup()
        try await waitUntil("Stream process started") {
            FileManager.default.fileExists(atPath: directory.appendingPathComponent("stream-started").path)
        }
        XCTAssertTrue(model.canCancel)
        model.cancel()
        try await waitForThePlan(model)
        XCTAssertFalse(model.canCancel)
        XCTAssertEqual(model.lastRun?.succeeded, false)
        XCTAssertEqual(model.history.first?.succeeded, false)
        XCTAssertEqual(model.history.first?.message, L10n.string("backup.cancelled"))
        XCTAssertNil(model.presentedError)
        let pid = try XCTUnwrap(Int32(String(
            contentsOf: directory.appendingPathComponent("pid"), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)))
        XCTAssertEqual(kill(pid, 0), -1, "Cancelled child must have exited")
        XCTAssertEqual(errno, ESRCH)
    }

    func testRealCLIReportsUninitializedStorageThenRoundTripsSelectedData() async throws {
        let root = INICompatibilityTests.repository
        let python = root.appendingPathComponent(".venv/bin/python")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: python.path), "Run uv sync before Swift integration tests")
        let launcher = directory.appendingPathComponent("real-cli")
        func quoted(_ text: String) -> String { "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        try "#!/bin/sh\nexec \(quoted(python.path)) -m mackeep_cli \"$@\"\n".write(
            to: launcher, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: launcher.path)
        let definitions = directory.appendingPathComponent(".mackeep")
        let storage = directory.appendingPathComponent("storage")
        let local = directory.appendingPathComponent("app")
        for folder in [definitions, storage, local] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        let config = directory.appendingPathComponent(".mackeep.cfg")
        try "[storage]\nengine = file_system\npath = \(storage.path)\n[applications_to_sync]\n".write(
            to: config, atomically: true, encoding: .utf8)
        try "[application]\nname = Demo\n[configuration_files]\napp\n[exclude]\napp/cache\n".write(
            to: definitions.appendingPathComponent("demo.cfg"), atomically: true, encoding: .utf8)
        try "[application]\nname = Ignored\n[configuration_files]\nignored\n".write(
            to: definitions.appendingPathComponent("ignored.cfg"), atomically: true, encoding: .utf8)
        let bytes = Data([0, 255, 65, 10])
        try bytes.write(to: local.appendingPathComponent("settings"))
        try Data("local cache".utf8).write(to: local.appendingPathComponent("cache"))
        try Data("unselected".utf8).write(to: directory.appendingPathComponent("ignored"))
        var command = MackeepCommand(path: launcher.path, home: directory.path)
        command.environment["PYTHONPATH"] = root.appendingPathComponent("src").path
        let applications = try command.runJSON(["--json", "list"], as: [MackeepApplication].self)
        let selection = ApplicationsModel(command: nil)
        selection.setApplications(applications)
        selection.setConfig(try MainConfig.load(from: config))
        selection.setEnabled(true, for: try XCTUnwrap(applications.first { $0.name == "demo" }))
        let model = BackupModel(
            command: command,
            historyStore: HistoryStore(url: directory.appendingPathComponent("history.json")),
            prepare: { try await selection.flushSelection() })
        // JSON backup declines creating storage unless it has been explicitly provisioned.
        model.backup()
        try await waitForThePlan(model)
        XCTAssertNotNil(model.presentedError)
        XCTAssertEqual(model.lastRun?.succeeded, false)
        XCTAssertEqual(try MainConfig.load(from: config).appsToSync, ["demo"])
        XCTAssertEqual(try Data(contentsOf: local.appendingPathComponent("settings")), bytes)
        let backup = storage.appendingPathComponent("Mackeep")
        XCTAssertFalse(FileManager.default.fileExists(atPath: backup.path))
        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: false)
        model.backup()
        try await waitForThePlan(model)
        XCTAssertNil(model.presentedError)
        XCTAssertEqual(model.lastRun?.succeeded, true)
        XCTAssertEqual(model.lastRun?.files, 1)
        XCTAssertEqual(model.lastRun?.bytes, bytes.count)
        XCTAssertEqual(try Data(contentsOf: backup.appendingPathComponent("app/settings")), bytes)
        XCTAssertFalse(FileManager.default.fileExists(atPath: backup.appendingPathComponent("ignored").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: backup.appendingPathComponent("app/cache").path))
        try Data("changed".utf8).write(to: local.appendingPathComponent("settings"))
        model.dryRunRestore()
        try await waitForThePlan(model)
        XCTAssertEqual(model.plannedCommand, "restore")
        XCTAssertTrue(model.plan?.actions.contains { $0.action == "conflict" } == true)
        model.restore()
        try await waitForThePlan(model)
        XCTAssertNil(model.presentedError)
        XCTAssertEqual(model.lastRun?.succeeded, true)
        XCTAssertEqual(try Data(contentsOf: local.appendingPathComponent("settings")), bytes)
        XCTAssertEqual(try String(contentsOf: local.appendingPathComponent("cache"), encoding: .utf8), "local cache")
        XCTAssertEqual(model.history.count, 3)
        XCTAssertEqual(model.history.filter(\.succeeded).count, 2)
        XCTAssertEqual(model.lastRun?.bytes, bytes.count)
    }

    func testHistoryKeepsOnlyTheNewestFiftyRecordsInDateOrder() {
        let store = HistoryStore(url: directory.appendingPathComponent("history.json"))
        let records = (0..<55).map { index in
            RunRecord(date: Date(timeIntervalSince1970: Double(index)), command: "backup", succeeded: true, files: index)
        }
        for record in records.reversed() { store.append(record) }
        XCTAssertEqual(store.load().map(\.files), Array((5..<55).reversed()))
    }
}

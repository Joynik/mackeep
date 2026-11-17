import XCTest

@testable import MackeepDesktop

@MainActor
extension BackupModelTests {
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
            contentsOf: directory.appendingPathComponent("arguments"), encoding: .utf8
        )
        .split(separator: "\n").map(String.init)
        XCTAssertEqual(
            arguments,
            [
                "--json config", "--json backup demo --dry-run", "--json config",
                "--json backup demo",
                "--json config", "--json restore demo --dry-run", "--json config",
                "--json restore demo --dry-run", "--json restore demo --force"
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
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("arguments").path))
    }

    func testTerminationDuringStreamingWaitsForTheChildToExit() async throws {
        let command = try makeTool()
        let tool = URL(fileURLWithPath: command.path)
        var script = try String(contentsOf: tool, encoding: .utf8)
        let insertion = """
            trap 'echo "{\"schema_version\":4,\"event\":\"done\",\"app\":\"demo\",\"files\":1,\"bytes\":12}"; \
              exit 130' USR1
            echo $$ > "$HOME/pid"
            touch "$HOME/stream-started"
            i=0
            while [ "$i" -lt 500 ]; do
              sleep 0.01
              i=$((i + 1))
            done
            exit 75
            """
        let completion = try XCTUnwrap(
            script.range(of: #"printf '{"schema_version":4,"event":"done""#))
        script.replaceSubrange(completion.lowerBound..<script.endIndex, with: insertion + "\n")
        try script.write(to: tool, atomically: true, encoding: .utf8)
        let model = BackupModel(
            command: command,
            historyStore: HistoryStore(url: directory.appendingPathComponent("history.json")))
        model.backup()
        try await waitUntil("Stream process started") {
            FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("stream-started").path)
        }
        XCTAssertTrue(model.canCancel)
        await model.stopForTermination()
        XCTAssertFalse(model.isRunning)
        XCTAssertFalse(model.canCancel)
        XCTAssertEqual(model.lastRun?.succeeded, false)
        XCTAssertEqual(model.history.first?.succeeded, false)
        XCTAssertEqual(model.history.first?.message, L10n.string("backup.cancelled"))
        XCTAssertNil(model.presentedError)
        let pid = try XCTUnwrap(
            Int32(
                String(
                    contentsOf: directory.appendingPathComponent("pid"), encoding: .utf8
                )
                .trimmingCharacters(in: .whitespacesAndNewlines)))
        XCTAssertEqual(kill(pid, 0), -1, "Cancelled child must have exited")
        XCTAssertEqual(errno, ESRCH)
    }

    func testRealCLIReportsUninitializedStorageThenRoundTripsSelectedData() async throws {
        let root = INICompatibilityTests.repository
        let python = root.appendingPathComponent(".venv/bin/python")
        XCTAssertTrue(
            FileManager.default.isExecutableFile(atPath: python.path),
            "Run uv sync before Swift integration tests")
        let launcher = directory.appendingPathComponent("real-cli")
        func quoted(_ text: String) -> String {
            "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
        }
        try "#!/bin/sh\nexec \(quoted(python.path)) -m mackeep_cli \"$@\"\n".write(
            to: launcher, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: launcher.path)
        let definitions = directory.appendingPathComponent(".mackeep")
        let storage = directory.appendingPathComponent("storage")
        let local = directory.appendingPathComponent("app")
        for folder in [definitions, storage, local] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        let config = directory.appendingPathComponent(".mackeep.cfg")
        try "[storage]\nengine = file_system\npath = \(storage.path)\n[applications_to_sync]\n"
            .write(
                to: config, atomically: true, encoding: .utf8)
        try "[application]\nname = Demo\n[configuration_files]\napp\n[exclude]\napp/cache\n".write(
            to: definitions.appendingPathComponent("demo.cfg"), atomically: true, encoding: .utf8)
        try "[application]\nname = Ignored\n[configuration_files]\nignored\n".write(
            to: definitions.appendingPathComponent("ignored.cfg"), atomically: true, encoding: .utf8
        )
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
        try await assertRealCLIRoundTrip(
            model: model, config: config, storage: storage, local: local, bytes: bytes)
    }

    func testHistoryKeepsOnlyTheNewestFiftyRecordsInDateOrder() throws {
        let store = HistoryStore(url: directory.appendingPathComponent("history.json"))
        let records = (0..<55).map { index in
            RunRecord(
                date: Date(timeIntervalSince1970: Double(index)), command: "backup",
                succeeded: true, files: index)
        }
        for record in records.reversed() { try store.append(record) }
        XCTAssertEqual(try store.load().map(\.files), Array((5..<55).reversed()))
    }

    private func assertRealCLIRoundTrip(
        model: BackupModel, config: URL, storage: URL, local: URL, bytes: Data
    ) async throws {
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
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: backup.appendingPathComponent("ignored").path))
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: backup.appendingPathComponent("app/cache").path))
        let updatedBytes = Data("updated snapshot".utf8)
        try updatedBytes.write(to: local.appendingPathComponent("settings"))
        model.backup()
        try await waitForThePlan(model)
        XCTAssertEqual(model.lastRun?.succeeded, true)
        XCTAssertEqual(
            try Data(contentsOf: backup.appendingPathComponent("app/settings")), updatedBytes)
        try Data("local changes".utf8).write(to: local.appendingPathComponent("settings"))
        model.dryRunRestore()
        try await waitForThePlan(model)
        XCTAssertEqual(model.plannedCommand, "restore")
        XCTAssertTrue(model.plan?.actions.contains { $0.action == "conflict" } == true)
        model.restore()
        try await waitForThePlan(model)
        XCTAssertNil(model.presentedError)
        XCTAssertEqual(model.lastRun?.succeeded, true)
        XCTAssertEqual(try Data(contentsOf: local.appendingPathComponent("settings")), updatedBytes)
        XCTAssertEqual(
            try String(contentsOf: local.appendingPathComponent("cache"), encoding: .utf8),
            "local cache")
        XCTAssertEqual(model.history.count, 4)
        XCTAssertEqual(model.history.filter(\.succeeded).count, 3)
        XCTAssertEqual(model.lastRun?.bytes, updatedBytes.count)
    }
}

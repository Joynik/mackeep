import AppKit
import XCTest

@testable import MackeepDesktop

@MainActor
final class DesktopSafetyTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mackeep-safety-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    }

    override func tearDownWithError() throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        try FileManager.default.removeItem(at: directory)
    }

    func testDamagedHistoryIsPreservedBeforeReplacement() throws {
        let file = directory.appendingPathComponent("history.json")
        let damaged = Data("{broken history".utf8)
        try damaged.write(to: file)
        let store = HistoryStore(url: file)
        XCTAssertThrowsError(try store.load())
        let model = BackupModel(command: nil, historyStore: store)
        XCTAssertNotNil(model.presentedError)
        XCTAssertEqual(try Data(contentsOf: file), damaged)
        let record = RunRecord(date: Date(timeIntervalSince1970: 1_700_000_000),
                               command: "backup", succeeded: true)
        let recovery = try XCTUnwrap(store.append(record))
        XCTAssertEqual(try Data(contentsOf: recovery), damaged)
        XCTAssertEqual(try store.load(), [record])
        for path in [file, recovery] {
            let attributes = try FileManager.default.attributesOfItem(atPath: path.path)
            XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        }
        try Data("another damaged history".utf8).write(to: file)
        let next = try XCTUnwrap(store.append(record))
        XCTAssertNotEqual(next, recovery)
        XCTAssertEqual(try Data(contentsOf: recovery), damaged)
        XCTAssertEqual(try String(contentsOf: next, encoding: .utf8), "another damaged history")
    }

    func testHistoryWriteFailurePreservesPreviousRecords() throws {
        let file = directory.appendingPathComponent("history.json")
        let store = HistoryStore(url: file)
        try store.append(RunRecord(command: "backup", succeeded: true))
        let original = try Data(contentsOf: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        XCTAssertThrowsError(try store.append(RunRecord(command: "restore", succeeded: false)))
        XCTAssertEqual(try Data(contentsOf: file), original)
    }

    func testHistoryDoesNotReplaceSymlinksOrDirectories() throws {
        let target = directory.appendingPathComponent("keep")
        try Data("keep".utf8).write(to: target)
        let file = directory.appendingPathComponent("history.json")
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: target)
        let store = HistoryStore(url: file)
        XCTAssertThrowsError(try store.append(RunRecord(command: "backup", succeeded: true)))
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "keep")
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        let nested = file.appendingPathComponent("keep")
        try Data("nested".utf8).write(to: nested)
        XCTAssertThrowsError(try store.append(RunRecord(command: "backup", succeeded: true)))
        XCTAssertEqual(try String(contentsOf: nested, encoding: .utf8), "nested")
    }

    private func realCommand() throws -> MackeepCommand {
        let root = INICompatibilityTests.repository
        let launcher = directory.appendingPathComponent("real-cli")
        let python = root.appendingPathComponent(".venv/bin/python")
        func quoted(_ text: String) -> String { "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        try "#!/bin/sh\nexec \(quoted(python.path)) -m mackeep_cli \"$@\"\n".write(
            to: launcher, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: launcher.path)
        for name in [".mackeep", "storage/Mackeep"] {
            try FileManager.default.createDirectory(
                at: directory.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        try "[storage]\nengine = file_system\npath = \(directory.path)/storage\n[applications_to_sync]\ndemo\n".write(
            to: directory.appendingPathComponent(".mackeep.cfg"), atomically: true, encoding: .utf8)
        try "[application]\nname = Demo\n[configuration_files]\napp\n".write(
            to: directory.appendingPathComponent(".mackeep/demo.cfg"), atomically: true, encoding: .utf8)
        try Data("local data".utf8).write(to: directory.appendingPathComponent("app"))
        try Data("backup data".utf8).write(to: directory.appendingPathComponent("storage/Mackeep/app"))
        var command = MackeepCommand(path: launcher.path, home: directory.path)
        command.environment["PYTHONPATH"] = root.appendingPathComponent("src").path
        return command
    }

    func testRealCLIHistoryIsMergedWithoutDuplicatingDesktopRecords() throws {
        let command = try realCommand()
        _ = try command.run(["backup", "--summary"])
        let file = directory.appendingPathComponent("Library/Application Support/Mackeep/history.json")
        let store = HistoryStore(url: file)
        var records = try store.load()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.command, "backup")
        XCTAssertEqual(records.first?.files, 1)
        XCTAssertEqual(records.first?.bytes, 10)
        XCTAssertEqual(records.first?.succeeded, true)
        try store.append(RunRecord(command: "restore", succeeded: true))
        records = try store.load()
        XCTAssertEqual(records.count, 2)
        try store.append(RunRecord(command: "backup", succeeded: false))
        XCTAssertEqual(try store.load().count, 3)
        let model = BackupModel(command: nil, historyStore: store)
        XCTAssertEqual(model.history.count, 3)
        model.clearHistory()
        XCTAssertTrue(model.history.isEmpty)
        XCTAssertTrue(try store.load().isEmpty)
    }

    func testChangedRestoreConfigurationRequiresAnotherConfirmation() async throws {
        let command = try realCommand()
        var preparations = 0
        let config = directory.appendingPathComponent(".mackeep.cfg")
        let model = BackupModel(
            command: command,
            historyStore: HistoryStore(url: directory.appendingPathComponent("history.json")),
            prepare: {
                preparations += 1
                if preparations == 2 {
                    let text = try String(contentsOf: config, encoding: .utf8)
                    try (text + "\n[exclude]\napp\n").write(to: config, atomically: true, encoding: .utf8)
                }
            })
        model.dryRunRestore()
        try await waitUntil("Restore preview") { !model.isRunning }
        XCTAssertEqual(model.plan?.summary.actions["conflict"], 1)
        model.restore()
        try await waitUntil("Changed preview") { !model.isRunning }
        XCTAssertNotNil(model.presentedError)
        XCTAssertTrue(model.isPreview)
        XCTAssertEqual(model.plannedCommand, "restore")
        XCTAssertNil(model.lastRun)
        XCTAssertTrue(model.history.isEmpty)
        XCTAssertEqual(try String(contentsOf: directory.appendingPathComponent("app"), encoding: .utf8), "local data")
        model.restore()
        try await waitUntil("Confirmed updated plan") { !model.isRunning }
        XCTAssertNil(model.presentedError)
        XCTAssertEqual(model.lastRun?.succeeded, true)
        XCTAssertEqual(try String(contentsOf: directory.appendingPathComponent("app"), encoding: .utf8), "local data")
    }

    func testRestoreCannotUseAnotherApplicationScope() async throws {
        let command = try realCommand()
        let model = BackupModel(
            command: command,
            historyStore: HistoryStore(url: directory.appendingPathComponent("history.json")))
        model.dryRunRestore(application: "demo")
        try await waitUntil("Scoped restore preview") { !model.isRunning }
        model.restore()
        XCTAssertFalse(model.isRunning)
        XCTAssertNil(model.lastRun)
        XCTAssertEqual(try String(contentsOf: directory.appendingPathComponent("app"), encoding: .utf8), "local data")
    }

    func testTerminationWaitsForPreparationAndNeverStartsTheCLI() async throws {
        let command = try realCommand()
        var entered = false
        var resume: CheckedContinuation<Void, Never>?
        let model = BackupModel(
            command: command,
            historyStore: HistoryStore(url: directory.appendingPathComponent("history.json")),
            prepare: {
                entered = true
                await withCheckedContinuation { resume = $0 }
            })
        model.backup()
        try await waitUntil("Preparation entered") { entered }
        var requested = false
        var stopped = false
        let stop = Task {
            requested = true
            await model.stopForTermination()
            stopped = true
        }
        try await waitUntil("Termination requested") { requested }
        XCTAssertTrue(model.isRunning)
        XCTAssertFalse(stopped)
        resume?.resume()
        try await waitUntil("Termination finished") { stopped && !model.isRunning }
        await stop.value
        XCTAssertNil(model.lastRun)
        XCTAssertTrue(model.history.isEmpty)
        XCTAssertEqual(try String(contentsOf: directory.appendingPathComponent("storage/Mackeep/app"), encoding: .utf8), "backup data")
        XCTAssertEqual(MackeepAppDelegate().applicationShouldTerminate(NSApplication.shared), .terminateNow)
    }

    func testChangedApplicationRulesRefreshTheRestorePlan() async throws {
        let command = try realCommand()
        let model = BackupModel(
            command: command,
            historyStore: HistoryStore(url: directory.appendingPathComponent("history.json")))
        model.dryRunRestore()
        try await waitUntil("Original restore plan") { !model.isRunning }
        let original = model.plan
        try "[application]\nname = Demo\n[configuration_files]\nother\n".write(
            to: directory.appendingPathComponent(".mackeep/demo.cfg"), atomically: true, encoding: .utf8)
        model.restore()
        try await waitUntil("Changed rules checked") { !model.isRunning }
        XCTAssertNotEqual(model.plan, original)
        XCTAssertNotNil(model.presentedError)
        XCTAssertNil(model.lastRun)
        XCTAssertEqual(try String(contentsOf: directory.appendingPathComponent("app"), encoding: .utf8), "local data")
    }

    func testHistoryFailureIsVisibleWithoutMisreportingTheBackup() async throws {
        let command = try realCommand()
        let parent = directory.appendingPathComponent("history")
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
        let file = parent.appendingPathComponent("history.json")
        let store = HistoryStore(url: file)
        try store.append(RunRecord(command: "restore", succeeded: true))
        let previous = try Data(contentsOf: file)
        let model = BackupModel(command: command, historyStore: store)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: parent.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: parent.path) }
        model.backup()
        try await waitUntil("Backup with unwritable history") { !model.isRunning }
        XCTAssertEqual(model.lastRun?.succeeded, true)
        XCTAssertNotNil(model.presentedError)
        XCTAssertEqual(model.history.count, 1)
        XCTAssertEqual(try Data(contentsOf: file), previous)
        XCTAssertEqual(try String(contentsOf: directory.appendingPathComponent("storage/Mackeep/app"), encoding: .utf8), "local data")
    }

    func testClosingConfirmationDuringPreparationDoesNotRestore() async throws {
        let command = try realCommand()
        var preparations = 0
        var resume: CheckedContinuation<Void, Never>?
        var entered = false
        let model = BackupModel(
            command: command,
            historyStore: HistoryStore(url: directory.appendingPathComponent("history.json")),
            prepare: {
                preparations += 1
                if preparations == 2 {
                    entered = true
                    await withCheckedContinuation { resume = $0 }
                }
            })
        model.dryRunRestore()
        try await waitUntil("Confirmation plan") { !model.isRunning }
        model.restore()
        try await waitUntil("Restore preparation") { entered }
        model.cancel()
        resume?.resume()
        try await waitUntil("Preparation cancelled") { !model.isRunning }
        XCTAssertNil(model.lastRun)
        XCTAssertNil(model.presentedError)
        XCTAssertEqual(try String(contentsOf: directory.appendingPathComponent("app"), encoding: .utf8), "local data")
    }
}

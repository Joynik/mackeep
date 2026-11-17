import XCTest

@testable import MackeepDesktop

@MainActor
extension DesktopSafetyTests {
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
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o700], ofItemAtPath: parent.path)
        }
        model.backup()
        try await waitUntil("Backup with unwritable history") { !model.isRunning }
        XCTAssertEqual(model.lastRun?.succeeded, true)
        XCTAssertNotNil(model.presentedError)
        XCTAssertEqual(model.history.count, 1)
        XCTAssertEqual(try Data(contentsOf: file), previous)
        XCTAssertEqual(
            try String(
                contentsOf: directory.appendingPathComponent("storage/Mackeep/app"), encoding: .utf8
            ), "local data")
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
        XCTAssertEqual(
            try String(contentsOf: directory.appendingPathComponent("app"), encoding: .utf8),
            "local data")
    }
}

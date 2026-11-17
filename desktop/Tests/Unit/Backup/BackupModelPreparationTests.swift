import XCTest

@testable import MackeepDesktop

@MainActor
extension BackupModelTests {
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
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("arguments").path))
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
}

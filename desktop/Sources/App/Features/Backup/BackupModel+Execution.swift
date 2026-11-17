import Foundation

private struct BackupExecutionResult: Sendable {
    let actions: [MackeepAction]
    let summary: MackeepSummary
    let message: String?
}

extension BackupModel {
    /// Persist selection first; a failed save must never launch filesystem work.
    func run(command name: String, application: String?) {
        guard let command, !isRunning else { return }
        guard canRun(command: name, application: application) else { return }

        let confirmedPlan = plan
        let confirmedConfig = plannedConfig
        beginOperation()
        presentedError = nil
        isStopping = false
        canCancel = false
        if name != "restore" { resetResults(command: name, preview: false) }

        Task {
            defer { finishOperation() }
            do {
                try await performRun(
                    command: command, name: name, application: application,
                    confirmedPlan: confirmedPlan, confirmedConfig: confirmedConfig)
            } catch is CancellationError {
            } catch {
                present(error)
            }
        }
    }

    private func canRun(command: String, application: String?) -> Bool {
        guard command == "restore" else { return true }
        return plannedCommand == "restore" && plan != nil && plannedApplication == application
    }

    private func performRun(
        command: MackeepCommand, name: String, application: String?,
        confirmedPlan: MackeepPlan?, confirmedConfig: MackeepConfig?
    ) async throws {
        try await prepare()
        try checkForStop()
        let config = try await loadConfig(using: command)
        try checkForStop()

        if name == "restore" {
            let currentPlan = try await loadRestorePlan(using: command, application: application)
            try checkForStop()
            guard
                acceptRestorePlan(
                    currentPlan, config: config, confirmedPlan: confirmedPlan,
                    confirmedConfig: confirmedConfig)
            else { return }
            resetResults(command: name, preview: false)
        }

        await executeCommand(
            command: command, config: config, name: name, application: application)
    }

    private func checkForStop() throws {
        if terminationRequested || stopRequested { throw CancellationError() }
    }

    private func loadConfig(using command: MackeepCommand) async throws -> MackeepConfig {
        try await Task.detached {
            try command.runJSON(["--json", "config"], as: MackeepConfig.self)
        }.value
    }

    private func loadRestorePlan(
        using command: MackeepCommand, application: String?
    ) async throws -> MackeepPlan {
        var previewCommand = command
        let previewToken = CommandCancellation()
        previewCommand.cancellation = previewToken
        cancellation = previewToken
        canCancel = true
        var arguments = ["--json", "restore"]
        if let application { arguments.append(application) }
        arguments.append("--dry-run")

        let current = try await Task.detached {
            try previewCommand.runJSON(arguments, as: MackeepPlan.self)
        }.value
        if terminationRequested || stopRequested || previewToken.isCancelled {
            throw CancellationError()
        }
        return current
    }

    private func acceptRestorePlan(
        _ current: MackeepPlan, config: MackeepConfig,
        confirmedPlan: MackeepPlan?, confirmedConfig: MackeepConfig?
    ) -> Bool {
        guard config != confirmedConfig || current != confirmedPlan else { return true }
        plan = current
        plannedConfig = config
        presentedError = AppError(
            title: L10n.string("backup.restore.title"),
            message: L10n.string("backup.restore.changed"))
        return false
    }

    private func executeCommand(
        command: MackeepCommand, config: MackeepConfig, name: String, application: String?
    ) async {
        let token = CommandCancellation(signal: SIGUSR1)
        cancellation = token
        canCancel = config.supportsSafeCancellation == true
        let arguments = commandArguments(name: name, application: application)
        let allowEmpty = allowsEmptySelection(config: config, application: application)
        let (events, continuation) = AsyncStream<MackeepEvent>.makeStream(
            bufferingPolicy: .bufferingNewest(256))
        let updates = Task {
            for await event in events { handle(event) }
        }
        var cancellableCommand = command
        cancellableCommand.cancellation = token
        let result = await Task.detached {
            Self.execute(
                command: cancellableCommand, arguments: arguments, allowEmpty: allowEmpty,
                continuation: continuation)
        }.value
        await updates.value
        apply(result, token: token, name: name, application: application)
    }

    private func commandArguments(name: String, application: String?) -> [String] {
        var arguments = ["--json", name]
        if let application { arguments.append(application) }
        // The user has confirmed replacement in the restore sheet.
        if name == "restore" { arguments.append("--force") }
        return arguments
    }

    private func allowsEmptySelection(config: MackeepConfig, application: String?) -> Bool {
        application == nil && config.appsToSync.isEmpty
            && (try? MainConfig.load(from: URL(fileURLWithPath: config.configFile)))?
                .document.hasSection("applications_to_sync") == true
    }

    private func apply(
        _ result: BackupExecutionResult, token: CommandCancellation,
        name: String, application: String?
    ) {
        executionActions = result.actions
        executionSummary = result.summary
        let message = token.isCancelled ? L10n.string("backup.cancelled") : result.message
        let record = RunRecord(
            command: name, application: application,
            succeeded: message == nil, files: result.summary.files ?? 0,
            bytes: result.summary.totalBytes, message: message)
        lastRun = record
        persist(record)
        presentExecutionError(message, token: token)
        Notifier.notify(
            title: L10n.string(message == nil ? "backup.done.title" : "backup.failed.title"),
            message: message ?? L10n.string("backup.done.message"))
        plannedCommand = nil
        plan = nil
    }

    private func persist(_ record: RunRecord) {
        do {
            let recovery = try historyStore.append(record)
            history = try historyStore.load()
            if let recovery {
                presentedError = AppError(
                    title: L10n.string("error.history.title"),
                    message: L10n.string("history.recovered", recovery.path))
            }
        } catch {
            presentHistoryError(error)
        }
    }

    private func presentExecutionError(_ message: String?, token: CommandCancellation) {
        guard let message, !token.isCancelled else { return }
        presentedError = AppError(
            title: L10n.string("error.backup.title"), message: message)
    }

    /// Collect complete totals outside the bounded UI stream.
    nonisolated private static func execute(
        command: MackeepCommand, arguments: [String], allowEmpty: Bool,
        continuation: AsyncStream<MackeepEvent>.Continuation
    ) -> BackupExecutionResult {
        defer { continuation.finish() }
        var rows: [MackeepAction] = []
        var counts: [String: Int] = [:]
        var apps: Set<String> = []
        var files = 0
        var bytes = 0
        var message: String?
        do {
            try command.streamEvents(arguments, allowEmpty: allowEmpty) { event in
                if let app = event.app { apps.insert(app) }
                if let row = event.actionRow {
                    counts[row.action, default: 0] += 1
                    if rows.count < actionLimit { rows.append(row) }
                }
                if event.event == "done" {
                    files += event.files ?? 0
                    bytes += event.bytes ?? 0
                }
                continuation.yield(event)
            }
        } catch is CancellationError { message = "cancelled" } catch {
            message = error.localizedDescription
        }
        let total = counts.values.reduce(0, +)
        return BackupExecutionResult(
            actions: rows,
            summary: MackeepSummary(
                apps: apps.sorted(), actions: counts, totalActions: total,
                totalBytes: bytes, files: files, truncated: total > actionLimit,
                limit: actionLimit),
            message: message)
    }

    /// Live rows may be coalesced; execution replaces them with the collected result.
    private func handle(_ event: MackeepEvent) {
        if let row = event.actionRow, executionActions.count < Self.actionLimit {
            executionActions.append(row)
        }
    }
}

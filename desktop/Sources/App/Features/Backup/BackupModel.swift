import Foundation

/// The model of the backup section.
@Observable
@MainActor
final class BackupModel {
    /// The filter of the plan.
    enum PlanFilter: String, CaseIterable, Identifiable {
        /// Every action.
        case all

        /// The files that are copied.
        case copy

        /// The paths that are excluded.
        case skipped

        /// The files that are missing.
        case missing

        /// The files that are already there.
        case conflict

        /// The files of the backup that are now excluded.
        case stale

        var id: String { rawValue }

        /// The title of the filter.
        var title: String {
            switch self {
            case .all: L10n.string("backup.filter.all")
            case .copy: L10n.string("backup.filter.copy")
            case .skipped: L10n.string("backup.filter.skipped")
            case .missing: L10n.string("backup.filter.missing")
            case .conflict: L10n.string("backup.filter.conflict")
            case .stale: L10n.string("backup.filter.stale")
            }
        }

        /// Whether an action is shown by the filter.
        func matches(_ action: MackeepAction) -> Bool {
            switch self {
            case .all: true
            case .copy: action.action == "copy"
            case .skipped: action.action == "skip_excluded"
            case .missing: action.action == "skip_missing"
            case .conflict: action.action == "conflict"
            case .stale: action.action == "stale_in_backup"
            }
        }
    }

    /// The plan of the last dry-run.
    private(set) var plan: MackeepPlan?

    /// The filter of the plan.
    var filter: PlanFilter = .all

    /// Execution rows are bounded; final totals include every event.
    nonisolated static let actionLimit = 5000
    private(set) var executionActions: [MackeepAction] = []
    private(set) var executionSummary: MackeepSummary?
    private(set) var lastRun: RunRecord?
    private(set) var displayedCommand: String?
    private(set) var isPreview = true

    /// Whether a command is running.
    private(set) var isRunning: Bool = false

    /// The error shown to the user, when there is one.
    var presentedError: AppError?

    /// The runs of Mackeep, the most recent first.
    private(set) var history: [RunRecord] = []

    /// The command line tool of Mackeep.
    private let command: MackeepCommand?

    /// The history of the runs.
    private let historyStore: HistoryStore

    /// The token of the running command.
    private var cancellation: CommandCancellation?
    private(set) var plannedCommand: String?
    private(set) var canCancel = false
    private(set) var isStopping = false
    private var plannedApplication: String?
    private var plannedConfig: MackeepConfig?
    private var activity: NSObjectProtocol?
    private var terminationRequested = false
    private var stopRequested = false
    private var terminationWaiters: [CheckedContinuation<Void, Never>] = []
    private let prepare: @MainActor () async throws -> Void

    init(
        command: MackeepCommand?,
        historyStore: HistoryStore? = nil,
        prepare: @escaping @MainActor () async throws -> Void = {}
    ) {
        self.command = command
        self.prepare = prepare
        self.historyStore = historyStore ?? HistoryStore()
        loadHistory()
    }

    /// The actions of the plan, after the filter.
    var visibleActions: [MackeepAction] {
        (plan?.actions ?? executionActions).filter { filter.matches($0) }
    }

    /// The summary of the plan.
    var summary: MackeepSummary? { plan?.summary ?? executionSummary }

    /// Read the history.
    func loadHistory() {
        do { history = try historyStore.load() }
        catch { presentHistoryError(error) }
    }

    /// Clear persisted history and update the table only after success.
    func clearHistory() {
        do {
            try historyStore.clear()
            history = try historyStore.load()
            presentedError = nil
        } catch { presentHistoryError(error) }
    }

    private func presentHistoryError(_ error: Error) {
        presentedError = AppError(
            title: L10n.string("error.history.title"), message: error.localizedDescription)
    }

    private func beginOperation() {
        isRunning = true
        ProcessInfo.processInfo.disableSuddenTermination()
        ProcessInfo.processInfo.disableAutomaticTermination("Mackeep operation")
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled], reason: "Mackeep operation")
    }

    private func finishOperation() {
        isRunning = false
        canCancel = false
        cancellation = nil
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
        ProcessInfo.processInfo.enableAutomaticTermination("Mackeep operation")
        ProcessInfo.processInfo.enableSuddenTermination()
        let waiters = terminationWaiters
        terminationWaiters = []
        terminationRequested = false
        stopRequested = false
        for waiter in waiters { waiter.resume() }
    }

    /// Wait for preparation to stop or for the CLI to reach a safe transaction boundary.
    func stopForTermination() async {
        guard isRunning else { return }
        await withCheckedContinuation { waiter in
            terminationWaiters.append(waiter)
            terminationRequested = true
            cancel()
        }
    }

    private func resetResults(command: String, preview: Bool) {
        displayedCommand = command
        isPreview = preview
        plan = nil
        executionActions = []
        executionSummary = nil
        lastRun = nil
        filter = .all
    }

    /// Compute the plan of a backup, without doing it.
    ///
    /// The work is done out of the main thread, so the window stays alive.
    ///
    /// - Parameter application: The application, when there is one.
    func dryRun(application: String? = nil) {
        computePlan(of: "backup", application: application)
    }

    /// Compute the plan of a restore, without doing it.
    ///
    /// The work is done out of the main thread, so the window stays alive.
    ///
    /// - Parameter application: The application, when there is one.
    func dryRunRestore(application: String? = nil) {
        computePlan(of: "restore", application: application)
    }

    /// Compute the plan of a command, without doing it.
    ///
    /// - Parameters:
    ///   - action: The action of the command, "backup" or "restore".
    ///   - application: The application, when there is one.
    private func computePlan(of action: String, application: String?) {
        guard var command, !isRunning else { return }
        let token = CommandCancellation()
        command.cancellation = token
        cancellation = token
        beginOperation()
        presentedError = nil
        canCancel = true
        isStopping = false
        resetResults(command: action, preview: true)
        plannedCommand = nil
        var arguments = ["--json", action]
        if let application { arguments.append(application) }
        arguments.append("--dry-run")
        Task {
            defer { finishOperation() }
            do {
                try await prepare()
                try Task.checkCancellation()
                if token.isCancelled || terminationRequested { throw CancellationError() }
                let (config, plan) = try await Task.detached(priority: .userInitiated) {
                    let config = try command.runJSON(["--json", "config"], as: MackeepConfig.self)
                    let plan = try command.runJSON(arguments, as: MackeepPlan.self)
                    return (config, plan)
                }.value
                if !token.isCancelled {
                    self.plan = plan
                    plannedCommand = action
                    plannedApplication = application
                    plannedConfig = config
                }
            } catch is CancellationError {} catch { present(error) }
        }
    }

    /// Back up the files.
    ///
    /// - Parameter application: The application, when there is one.
    func backup(application: String? = nil) {
        run(command: "backup", application: application)
    }

    /// Restore the files.
    ///
    /// - Parameter application: The application, when there is one.
    func restore(application: String? = nil) {
        run(command: "restore", application: application)
    }

    /// Stop the command that is running.
    func cancel() {
        guard isRunning, canCancel || cancellation == nil else { return }
        stopRequested = true
        isStopping = true
        if canCancel { cancellation?.cancel() }
    }

    private func present(_ error: Error) {
        presentedError = AppError(
            title: L10n.string("error.backup.title"), message: error.localizedDescription)
    }

    /// Persist selection first; a failed save must never launch filesystem work.
    private func run(command name: String, application: String?) {
        guard let command, !isRunning else { return }
        if name == "restore" {
            guard plannedCommand == "restore", plan != nil,
                  plannedApplication == application else { return }
        }
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
                try await prepare()
                if terminationRequested || stopRequested { throw CancellationError() }
                let config = try await Task.detached {
                    try command.runJSON(["--json", "config"], as: MackeepConfig.self)
                }.value
                if terminationRequested || stopRequested { throw CancellationError() }
                if name == "restore" {
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
                    if config != confirmedConfig || current != confirmedPlan {
                        plan = current
                        plannedConfig = config
                        presentedError = AppError(
                            title: L10n.string("backup.restore.title"),
                            message: L10n.string("backup.restore.changed"))
                        return
                    }
                    resetResults(command: name, preview: false)
                }
                let token = CommandCancellation(signal: SIGUSR1)
                cancellation = token
                canCancel = config.supportsSafeCancellation == true
                var arguments = ["--json", name]
                if let application { arguments.append(application) }
                // The user has confirmed replacement in the restore sheet.
                if name == "restore" { arguments.append("--force") }
                let allowEmpty =
                    application == nil && config.appsToSync.isEmpty
                    && (try? MainConfig.load(from: URL(fileURLWithPath: config.configFile)))?
                        .document.hasSection("applications_to_sync") == true
                let (events, continuation) = AsyncStream<MackeepEvent>.makeStream(
                    bufferingPolicy: .bufferingNewest(256))
                let updates = Task {
                    for await event in events { handle(event) }
                }
                let result = await Task.detached {
                    var command = command
                    command.cancellation = token
                    return Self.execute(
                        command: command, arguments: arguments, allowEmpty: allowEmpty,
                        continuation: continuation)
                }.value
                await updates.value
                executionActions = result.actions
                executionSummary = result.summary
                let message = token.isCancelled ? L10n.string("backup.cancelled") : result.message
                let record = RunRecord(
                    command: name, application: application,
                    succeeded: message == nil, files: result.summary.files ?? 0,
                    bytes: result.summary.totalBytes, message: message)
                lastRun = record
                do {
                    let recovery = try historyStore.append(record)
                    history = try historyStore.load()
                    if let recovery {
                        presentedError = AppError(
                            title: L10n.string("error.history.title"),
                            message: L10n.string("history.recovered", recovery.path))
                    }
                } catch { presentHistoryError(error) }
                if let message, !token.isCancelled {
                    presentedError = AppError(
                        title: L10n.string("error.backup.title"), message: message)
                }
                Notifier.notify(
                    title: L10n.string(
                        message == nil ? "backup.done.title" : "backup.failed.title"),
                    message: message ?? L10n.string("backup.done.message"))
                plannedCommand = nil
                plan = nil
            } catch is CancellationError {} catch { present(error) }
        }
    }

    /// Collect complete totals outside the bounded UI stream.
    nonisolated private static func execute(
        command: MackeepCommand, arguments: [String], allowEmpty: Bool,
        continuation: AsyncStream<MackeepEvent>.Continuation
    ) -> (actions: [MackeepAction], summary: MackeepSummary, message: String?) {
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
        return (
            rows,
            MackeepSummary(
                apps: apps.sorted(), actions: counts, totalActions: total, totalBytes: bytes,
                files: files, truncated: total > actionLimit, limit: actionLimit),
            message)
    }

    /// Live rows may be coalesced; execution replaces them with the collected result.
    private func handle(_ event: MackeepEvent) {
        if let row = event.actionRow, executionActions.count < Self.actionLimit {
            executionActions.append(row)
        }
    }
}

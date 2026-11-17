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
    var plan: MackeepPlan?

    /// The filter of the plan.
    var filter: PlanFilter = .all

    /// Execution rows are bounded; final totals include every event.
    nonisolated static let actionLimit = 5000
    var executionActions: [MackeepAction] = []
    var executionSummary: MackeepSummary?
    var lastRun: RunRecord?
    private(set) var displayedCommand: String?
    private(set) var isPreview = true

    /// Whether a command is running.
    private(set) var isRunning: Bool = false

    /// The error shown to the user, when there is one.
    var presentedError: AppError?

    /// The runs of Mackeep, the most recent first.
    var history: [RunRecord] = []

    /// The command line tool of Mackeep.
    let command: MackeepCommand?

    /// The history of the runs.
    let historyStore: HistoryStore

    /// The token of the running command.
    var cancellation: CommandCancellation?
    var plannedCommand: String?
    var canCancel = false
    var isStopping = false
    var plannedApplication: String?
    var plannedConfig: MackeepConfig?
    var activity: NSObjectProtocol?
    var terminationRequested = false
    var stopRequested = false
    private var terminationWaiters: [CheckedContinuation<Void, Never>] = []
    let prepare: @MainActor () async throws -> Void

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
        let actions = plan?.actions ?? executionActions
        func key(_ action: MackeepAction) -> String { "\(action.app)|\(action.src)|\(action.dst)" }
        func shouldShowOriginal(_ action: MackeepAction) -> Bool {
            displayedCommand != "restore" || action.action != "copy"
                || !overwrites.contains(key(action))
        }
        let copies = Set(actions.filter { $0.action == "copy" }.map(key))
        let overwrites = Set(actions.filter { $0.action == "conflict" }.map(key))
        return actions.compactMap { action in
            if action.action == "conflict" {
                guard displayedCommand == "restore", isPreview,
                    !copies.contains(key(action))
                else { return nil }
            } else if shouldShowOriginal(action) {
                return action
            }
            return MackeepAction(
                app: action.app, action: "copy", src: action.src, dst: action.dst,
                sizeBytes: action.sizeBytes, reason: action.reason, wouldOverwrite: true,
                willRemove: action.willRemove)
        }.filter { filter.matches($0) }
    }

    /// Overwrites are warnings attached to copy rows, never separate actions.
    var availableFilters: [PlanFilter] { PlanFilter.allCases.filter { $0 != .conflict } }

    func willOverwrite(_ action: MackeepAction) -> Bool {
        guard displayedCommand == "restore", action.action == "copy" else { return false }
        return action.wouldOverwrite == true
    }

    /// The summary of the plan.
    var summary: MackeepSummary? { plan?.summary ?? executionSummary }

    /// Read the history.
    func loadHistory() {
        do { history = try historyStore.load() } catch { presentHistoryError(error) }
    }

    /// Clear persisted history and update the table only after success.
    func clearHistory() {
        do {
            try historyStore.clear()
            history = try historyStore.load()
            presentedError = nil
        } catch { presentHistoryError(error) }
    }

    func presentHistoryError(_ error: Error) {
        presentedError = AppError(
            title: L10n.string("error.history.title"), message: error.localizedDescription)
    }

    func beginOperation() {
        isRunning = true
        ProcessInfo.processInfo.disableSuddenTermination()
        ProcessInfo.processInfo.disableAutomaticTermination("Mackeep operation")
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled], reason: "Mackeep operation")
    }

    func finishOperation() {
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

    func resetResults(command: String, preview: Bool) {
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

    func present(_ error: Error) {
        presentedError = AppError(
            title: L10n.string("error.backup.title"), message: error.localizedDescription)
    }
}

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

    /// The lines of the log of the running command.
    private(set) var log: [String] = []

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
    private let prepare: @MainActor () async throws -> Void

    init(
        command: MackeepCommand?,
        historyStore: HistoryStore = HistoryStore(),
        prepare: @escaping @MainActor () async throws -> Void = {}
    ) {
        self.command = command
        self.prepare = prepare
        self.historyStore = historyStore
        self.history = historyStore.load()
    }

    /// The actions of the plan, after the filter.
    var visibleActions: [MackeepAction] {
        (plan?.actions ?? []).filter { filter.matches($0) }
    }

    /// The summary of the plan.
    var summary: MackeepSummary? { plan?.summary }

    /// Read the history.
    func loadHistory() {
        history = historyStore.load()
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
        isRunning = true
        presentedError = nil
        canCancel = true
        isStopping = false
        plan = nil
        plannedCommand = nil
        log = []
        filter = .all
        var arguments = ["--json", action]
        if let application { arguments.append(application) }
        arguments.append("--dry-run")
        Task {
            defer { isRunning = false; canCancel = false; cancellation = nil }
            do {
                try await prepare()
                try Task.checkCancellation()
                let plan = try await Task.detached(priority: .userInitiated) {
                    try command.runJSON(arguments, as: MackeepPlan.self)
                }.value
                if !token.isCancelled { self.plan = plan; plannedCommand = action }
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
        guard canCancel else { return }
        isStopping = true
        cancellation?.cancel()
    }

    private func present(_ error: Error) {
        presentedError = AppError(
            title: L10n.string("error.backup.title"), message: error.localizedDescription)
    }

    /// Persist selection first; a failed save must never launch filesystem work.
    private func run(command name: String, application: String?) {
        guard let command, !isRunning else { return }
        if name == "restore", plannedCommand != "restore" || plan == nil { return }
        isRunning = true
        presentedError = nil
        isStopping = false
        canCancel = false
        log = []
        Task {
            defer { isRunning = false; canCancel = false; cancellation = nil }
            do {
                try await prepare()
                let config = try await Task.detached {
                    try command.runJSON(["--json", "config"], as: MackeepConfig.self)
                }.value
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
                let result = await Task.detached { () -> (Int, Int, String?) in
                    var files = 0
                    var bytes = 0
                    defer { continuation.finish() }
                    do {
                        var command = command
                        command.cancellation = token
                        try command.streamEvents(arguments, allowEmpty: allowEmpty) { event in
                            if event.event == "done" {
                                files += event.files ?? 0; bytes += event.bytes ?? 0
                            }
                            continuation.yield(event)
                        }
                        return (files, bytes, nil)
                    } catch is CancellationError { return (files, bytes, "cancelled") } catch {
                        return (files, bytes, error.localizedDescription)
                    }
                }.value
                await updates.value
                let message = token.isCancelled ? L10n.string("backup.cancelled") : result.2
                let record = RunRecord(
                    command: name, application: application,
                    succeeded: message == nil, files: result.0, bytes: result.1, message: message)
                historyStore.append(record)
                loadHistory()
                if let message, !token.isCancelled {
                    presentedError = AppError(
                        title: L10n.string("error.backup.title"), message: message)
                }
                Notifier.notify(
                    title: L10n.string(
                        result.2 == nil ? "backup.done.title" : "backup.failed.title"),
                    message: message ?? L10n.string("backup.done.message"))
                plannedCommand = nil
                plan = nil
            } catch { present(error) }
        }
    }

    /// Take an event of the running command.
    private func handle(_ event: MackeepEvent) {
        if log.count >= 2000 { log.removeFirst(256) }
        switch event.event {
        case "start":
            log.append(L10n.string("backup.log.start", event.app ?? ""))
        case "file":
            let name: String = (event.src ?? "").split(separator: "/").last
                .map(String.init) ?? ""
            log.append(
                L10n.string("backup.log.file", event.action ?? "", name)
            )
        case "done":
            log.append(
                L10n.string(
                    "backup.log.done",
                    event.files ?? 0,
                    event.bytes ?? 0
                )
            )
        case "error":
            log.append(L10n.string("backup.log.error", event.message ?? ""))
        default:
            break
        }
    }
}

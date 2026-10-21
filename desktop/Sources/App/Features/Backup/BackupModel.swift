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

    init(
        command: MackeepCommand?,
        historyStore: HistoryStore = HistoryStore()
    ) {
        self.command = command
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
        guard let command else { return }

        var arguments: [String] = ["--json", action]
        if let application { arguments.append(application) }
        arguments.append("--dry-run")

        isRunning = true

        Task { [weak self] in
            let result: Result<MackeepPlan, Error> = await Task.detached(
                priority: .userInitiated
            ) {
                do {
                    return .success(
                        try command.runJSON(arguments, as: MackeepPlan.self)
                    )
                } catch {
                    return .failure(error)
                }
            }.value

            self?.isRunning = false

            switch result {
            case .success(let plan):
                self?.plan = plan
            case .failure(let error):
                self?.presentedError = AppError(
                    title: L10n.string("error.backup.title"),
                    message: "\(error)"
                )
            }
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
        cancellation?.cancel()
    }

    /// Run a command of Mackeep, and follow its progress.
    private func run(command name: String, application: String?) {
        guard let command, !isRunning else { return }

        var arguments: [String] = ["--json", name]
        if let application { arguments.append(application) }

        let token: CommandCancellation = CommandCancellation()
        cancellation = token
        isRunning = true
        log = []

        Task { [weak self] in
            let counters: Counters = Counters()
            var message: String?

            do {
                try await Task.detached { [weak self] in
                    var command: MackeepCommand = command
                    command.cancellation = token
                    try command.streamEvents(arguments) { event in
                        Task { @MainActor in
                            self?.handle(event, counters: counters)
                        }
                    }
                }.value
            } catch {
                message = "\(error)"
            }

            let succeeded: Bool = message == nil
            let record: RunRecord = RunRecord(
                command: name,
                application: application,
                succeeded: succeeded,
                files: counters.files,
                bytes: counters.bytes,
                message: message
            )

            await MainActor.run {
                self?.isRunning = false
                self?.cancellation = nil
                self?.historyStore.append(record)
                self?.loadHistory()
                if let message {
                    self?.presentedError = AppError(
                        title: L10n.string("error.backup.title"),
                        message: message
                    )
                }
            }

            Notifier.notify(
                title: succeeded
                    ? L10n.string("backup.done.title")
                    : L10n.string("backup.failed.title"),
                message: succeeded
                    ? L10n.string("backup.done.message")
                    : (message ?? "")
            )
        }
    }

    /// The counters of a run.
    final class Counters: @unchecked Sendable {
        /// The number of files that were copied.
        var files: Int = 0

        /// The number of bytes that were copied.
        var bytes: Int = 0
    }

    /// Take an event of the running command.
    private func handle(_ event: MackeepEvent, counters: Counters) {
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
            counters.files = event.files ?? 0
            counters.bytes = event.bytes ?? 0
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

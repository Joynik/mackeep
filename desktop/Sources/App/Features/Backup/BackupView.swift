import SwiftUI

/// The backup section: the plan of the runs, the runs and their history.
struct BackupView: View {
    /// The model of the section.
    @Bindable var model: BackupModel

    /// Whether the confirmation of the restore is shown.
    @State private var showsRestoreConfirmation = false

    /// Whether the history is shown.
    @State private var showsHistory = false

    var body: some View {
        VStack(spacing: 0) {
            actions
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle(L10n.string("section.backup.title"))
        .appError($model.presentedError)
        // The controls of the window have the same height, so they line up.
        .appControlSize()
        .sheet(isPresented: $showsRestoreConfirmation) {
            RestoreConfirmationView(model: model)
        }
        .sheet(isPresented: $showsHistory) {
            HistoryView(model: model)
        }
        .onAppear {
            model.loadHistory()
        }
    }

    /// The buttons of the section.
    private var actions: some View {
        HStack(spacing: 12) {
            Button {
                model.dryRun()
            } label: {
                Label(L10n.string("backup.dryRun"), systemImage: "list.bullet.clipboard")
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(model.isRunning)

            Button {
                model.backup()
            } label: {
                Label(L10n.string("backup.run"), systemImage: "arrow.up.circle")
            }
            .keyboardShortcut("b", modifiers: .command)
            .disabled(model.isRunning)

            Button {
                showsRestoreConfirmation = true
            } label: {
                Label(L10n.string("backup.restore"), systemImage: "arrow.down.circle")
            }
            .disabled(model.isRunning)

            if model.isRunning && model.canCancel {
                Button(role: .destructive) {
                    model.cancel()
                } label: {
                    Label(L10n.string("backup.cancel"), systemImage: "stop.circle")
                }
                .disabled(model.isStopping)
                if model.isStopping { Text(L10n.string("backup.stopping")).font(.caption) }
            }

            Spacer(minLength: 12)

            Button {
                showsHistory = true
            } label: {
                Label(L10n.string("backup.history"), systemImage: "clock.arrow.circlepath")
            }

            FieldInfoLabel(
                title: L10n.string("backup.mode.title"),
                hint: L10n.string("backup.mode.hint"), iconOnly: true)
        }
        .padding(12)
    }


    /// The latest preview or execution report.
    @ViewBuilder
    private var content: some View {
        if model.displayedCommand != nil {
            report
        } else {
            empty
        }
    }

    /// The empty state of the section.
    private var empty: some View {
        ContentUnavailableView {
            Label {
                Text(L10n.string("backup.empty.title"))
            } icon: {
                Image(systemName: "arrow.triangle.2.circlepath")
            }
        } description: {
            Text(L10n.string("backup.empty.message"))
        }
    }

    /// Plans and execution results use the same table, with an explicit operation heading.
    private var report: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                let operation = model.displayedCommand == "restore"
                    ? L10n.string("backup.command.restore") : L10n.string("backup.command.backup")
                Text(model.isPreview ? L10n.string("backup.result.preview", operation) : operation)
                    .font(.headline)
                if model.isRunning { ProgressView().controlSize(.small) }
                if let record = model.lastRun {
                    Label(
                        L10n.string(record.succeeded
                                    ? "backup.history.success" : "backup.history.failure"),
                        systemImage: record.succeeded
                            ? "checkmark.circle" : "exclamationmark.triangle")
                        .foregroundStyle(record.succeeded ? Color.green : Color.red)
                }
                Spacer()
            }
            .padding(12)

            if let message = model.lastRun?.message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
            }

            HStack {
                Picker("", selection: $model.filter) {
                    ForEach(model.availableFilters) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 160)
                .labelsHidden()

                if let summary: MackeepSummary = model.summary {
                    Text(
                        L10n.string(
                            "backup.summary",
                            summary.totalActions,
                            summary.files ?? 0,
                            ByteCountFormatter.string(
                                fromByteCount: Int64(summary.totalBytes),
                                countStyle: .file
                            )
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            if model.summary?.truncated == true {
                Text(L10n.string("backup.result.truncated"))
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
            PlanTableView(
                actions: model.visibleActions, isPreview: model.isPreview,
                willOverwrite: model.willOverwrite)
        }
    }

}

/// The table of the actions of a plan.
struct PlanTableView: View {
    /// The actions.
    let actions: [MackeepAction]
    var isPreview = true
    var willOverwrite: (MackeepAction) -> Bool = { _ in false }

    var body: some View {
        Table(actions) {
            TableColumn(L10n.string("backup.table.application")) { action in
                Text(action.app)
                    .font(.callout.monospaced())
            }
            TableColumn(L10n.string("backup.table.action")) { action in
                HStack(spacing: 6) {
                    Label {
                        Text(action.willRemove == true
                             ? L10n.string(isPreview
                                           ? "backup.action.removeStale" : "backup.action.removedStale")
                             : actionTitle(action.action))
                    } icon: {
                        Image(systemName: icon(for: action.action))
                            .foregroundStyle(color(for: action.action))
                    }
                    .font(.callout)
                    if willOverwrite(action) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .help(L10n.string(isPreview
                                             ? "backup.action.willOverwrite" : "backup.action.overwritten"))
                            .accessibilityLabel(L10n.string(isPreview
                                             ? "backup.action.willOverwrite" : "backup.action.overwritten"))
                    }
                }
            }
            TableColumn(L10n.string("backup.table.file")) { action in
                Text(action.src)
                    .font(.caption.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(action.reason?.pattern ?? "")
            }
            TableColumn(L10n.string("backup.table.size")) { action in
                Text(
                    ByteCountFormatter.string(
                        fromByteCount: Int64(action.sizeBytes ?? 0),
                        countStyle: .file
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    /// Translate protocol action codes without changing the CLI contract.
    private func actionTitle(_ action: String) -> String {
        switch action {
        case "copy": L10n.string(isPreview ? "backup.action.copy" : "backup.action.copied")
        case "skip_excluded": L10n.string("backup.action.skipExcluded")
        case "skip_missing": L10n.string("backup.action.skipMissing")
        case "conflict": L10n.string("backup.action.conflict")
        case "stale_in_backup": L10n.string("backup.filter.stale")
        default: action
        }
    }

    /// The symbol of a kind of action.
    private func icon(for action: String) -> String {
        switch action {
        case "copy": "checkmark.circle"
        case "skip_excluded": "minus.circle"
        case "skip_missing": "questionmark.circle"
        case "conflict": "exclamationmark.triangle"
        case "stale_in_backup": "clock.badge.exclamationmark"
        default: "circle"
        }
    }

    /// The color of a kind of action.
    private func color(for action: String) -> Color {
        switch action {
        case "copy": .green
        case "conflict": .orange
        case "stale_in_backup": .yellow
        default: .secondary
        }
    }
}

/// The sheet that confirms a restore.
struct RestoreConfirmationView: View {
    /// The model of the backup section.
    @Bindable var model: BackupModel

    /// The environment of the sheet.
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.string("backup.restore.title"))
                .font(.title3.weight(.semibold))

            Label(
                L10n.string("backup.restore.warning"),
                systemImage: "exclamationmark.triangle"
            )
            .foregroundStyle(.orange)

            if let summary: MackeepSummary = model.summary {
                Text(
                    L10n.string(
                        "backup.summary",
                        summary.totalActions,
                        summary.files ?? 0,
                        ByteCountFormatter.string(
                            fromByteCount: Int64(summary.totalBytes),
                            countStyle: .file
                        )
                    )
                )
                .font(.callout)
            }

            Text(L10n.string("backup.restore.overwrites", model.summary?.actions["conflict"] ?? 0))
                .font(.callout)
            if model.isRunning { ProgressView() }
            if model.summary?.truncated == true {
                Text(L10n.string("backup.plan.truncated")).foregroundStyle(.orange)
            }
            Text(L10n.string("backup.result.preview", L10n.string("backup.command.restore")))
                .font(.headline)
            PlanTableView(actions: model.visibleActions, willOverwrite: model.willOverwrite)
                .frame(minHeight: 260)

            HStack {
                Spacer()
                Button(L10n.string("backup.restore.cancel"), role: .cancel) {
                    dismiss()
                }
                Button(L10n.string("backup.restore.confirm")) {
                    model.restore()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(model.isRunning || model.plannedCommand != "restore" || model.plan == nil)
            }
        }
        .appError($model.presentedError)
        .onChange(of: model.isPreview) { _, preview in if !preview { dismiss() } }
        .onDisappear { if model.isPreview { model.cancel() } }
        .padding(20)
        .frame(width: 720, height: 560)
        .onAppear {
            model.dryRunRestore()
        }
    }
}

/// The sheet that shows the history of the runs.
struct HistoryView: View {
    /// The model of the backup section.
    @Bindable var model: BackupModel

    /// The environment of the sheet.
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.string("backup.history.title"))
                    .font(.title3.weight(.semibold))
                Spacer()
                Button(role: .destructive) {
                    model.clearHistory()
                } label: {
                    Label(L10n.string("backup.history.clear"), systemImage: "trash")
                }
                .disabled(model.history.isEmpty)
            }

            if model.history.isEmpty {
                Text(L10n.string("backup.history.empty"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                Table(model.history) {
                    TableColumn(L10n.string("backup.history.date")) { record in
                        Text(record.date, format: .dateTime.day().month().year().hour().minute())
                            .monospacedDigit()
                    }
                    .width(min: 140, ideal: 160)
                    TableColumn(L10n.string("backup.history.operation")) { record in
                        Text(record.command == "backup"
                             ? L10n.string("backup.command.backup")
                             : record.command == "restore"
                                ? L10n.string("backup.command.restore") : record.command)
                    }
                    .width(min: 100, ideal: 120)
                    TableColumn(L10n.string("backup.table.application")) { record in
                        Text(record.application ?? L10n.string("backup.history.allApplications"))
                            .lineLimit(1)
                            .help(record.application ?? L10n.string("backup.history.allApplications"))
                    }
                    .width(min: 100, ideal: 140)
                    TableColumn(L10n.string("backup.history.result")) { record in
                        Label(
                            L10n.string(record.succeeded
                                        ? "backup.history.success" : "backup.history.failure"),
                            systemImage: record.succeeded
                                ? "checkmark.circle" : "exclamationmark.triangle"
                        )
                        .foregroundStyle(record.succeeded ? Color.green : Color.red)
                        .help(record.message ?? "")
                    }
                    .width(min: 100, ideal: 120)
                    TableColumn(L10n.string("backup.history.files")) { record in
                        Text(record.files, format: .number)
                            .monospacedDigit()
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .width(70)
                    TableColumn(L10n.string("backup.table.size")) { record in
                        Text(ByteCountFormatter.string(
                            fromByteCount: Int64(record.bytes), countStyle: .file))
                            .monospacedDigit()
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .width(min: 80, ideal: 100)
                    TableColumn(L10n.string("backup.history.details")) { record in
                        Text(record.message ?? "—")
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .help(record.message ?? "")
                    }
                    .width(min: 120, ideal: 180)
                }
                .tableStyle(.inset(alternatesRowBackgrounds: true))
                .border(Color(nsColor: .separatorColor))
            }

            HStack {
                Spacer()
                Button(L10n.string("backup.restore.cancel"), role: .cancel) {
                    dismiss()
                }
            }
        }
        .appError($model.presentedError)
        .padding(20)
        .frame(width: 1000, height: 480)
        .onAppear { model.loadHistory() }
    }
}

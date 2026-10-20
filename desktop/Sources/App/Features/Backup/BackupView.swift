import SwiftUI

/// The backup section: the plan of the runs, the runs and their history.
struct BackupView: View {
    /// The model of the section.
    @Bindable var model: BackupModel

    /// Whether the confirmation of the restore is shown.
    @State private var showsRestoreConfirmation = false

    /// Whether the history is shown.
    @State private var showsHistory = false

    /// Whether the advanced settings are shown.
    @State private var showsAdvanced = false

    var body: some View {
        VStack(spacing: 0) {
            actions
            Divider()
            content
        }
        .navigationTitle(L10n.string("section.backup.title"))
        .sheet(isPresented: $showsRestoreConfirmation) {
            RestoreConfirmationView(model: model)
        }
        .sheet(isPresented: $showsHistory) {
            HistoryView(model: model)
        }
        .sheet(isPresented: $showsAdvanced) {
            AdvancedView()
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

            if model.isRunning {
                Button(role: .destructive) {
                    model.cancel()
                } label: {
                    Label(L10n.string("backup.cancel"), systemImage: "stop.circle")
                }
            }

            Spacer(minLength: 12)

            Button {
                showsHistory = true
            } label: {
                Label(L10n.string("backup.history"), systemImage: "clock.arrow.circlepath")
            }

            Button {
                showsAdvanced = true
            } label: {
                Label(L10n.string("backup.advanced"), systemImage: "ellipsis.circle")
            }
        }
        .padding(12)
    }


    /// The plan of the run, or the log of the running command.
    @ViewBuilder
    private var content: some View {
        if model.isRunning || !model.log.isEmpty {
            log
        } else if model.plan != nil {
            plan
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

    /// The table of the actions of the plan.
    private var plan: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("", selection: $model.filter) {
                    ForEach(BackupModel.PlanFilter.allCases) { filter in
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

            PlanTableView(actions: model.visibleActions)
        }
    }

    /// The log of the running command.
    private var log: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(model.log.enumerated()), id: \.offset) { index, line in
                        Text(line)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .id(index)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            }
            .onChange(of: model.log.count) {
                proxy.scrollTo(model.log.count - 1, anchor: .bottom)
            }
        }
    }
}

/// The table of the actions of a plan.
struct PlanTableView: View {
    /// The actions.
    let actions: [MackeepAction]

    var body: some View {
        Table(actions) {
            TableColumn(L10n.string("backup.table.application")) { action in
                Text(action.app)
                    .font(.callout.monospaced())
            }
            TableColumn(L10n.string("backup.table.action")) { action in
                Label {
                    Text(action.action)
                } icon: {
                    Image(systemName: icon(for: action.action))
                        .foregroundStyle(color(for: action.action))
                }
                .font(.callout)
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

            PlanTableView(actions: model.visibleActions)
                .frame(minHeight: 260)

            HStack {
                Spacer()
                Button(L10n.string("backup.restore.cancel"), role: .cancel) {
                    dismiss()
                }
                Button(L10n.string("backup.restore.confirm")) {
                    model.restore()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
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
            Text(L10n.string("backup.history.title"))
                .font(.title3.weight(.semibold))

            if model.history.isEmpty {
                Text(L10n.string("backup.history.empty"))
                    .foregroundStyle(.secondary)
            } else {
                List(model.history) { record in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(record.command)
                                .font(.callout.weight(.semibold))
                            if let application: String = record.application {
                                Text(application)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(record.date.formatted(date: .abbreviated, time: .standard))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let message: String = record.message {
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }

            HStack {
                Spacer()
                Button(L10n.string("backup.restore.cancel"), role: .cancel) {
                    dismiss()
                }
            }
        }
        .padding(20)
        .frame(width: 560, height: 480)
    }
}

/// The sheet with the modes that are not used often.
struct AdvancedView: View {
    /// The environment of the sheet.
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.string("backup.advanced.title"))
                .font(.title3.weight(.semibold))

            Label(
                L10n.string("backup.advanced.warning"),
                systemImage: "exclamationmark.triangle"
            )
            .foregroundStyle(.orange)

            Text(L10n.string("backup.advanced.explanation"))
                .font(.callout)

            HStack {
                Spacer()
                Button(L10n.string("backup.restore.cancel"), role: .cancel) {
                    dismiss()
                }
            }
        }
        .padding(20)
        .frame(width: 520)
    }
}

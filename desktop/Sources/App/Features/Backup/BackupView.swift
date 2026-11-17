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
                let operation =
                    model.displayedCommand == "restore"
                    ? L10n.string("backup.command.restore") : L10n.string("backup.command.backup")
                Text(model.isPreview ? L10n.string("backup.result.preview", operation) : operation)
                    .font(.headline)
                if model.isRunning { ProgressView().controlSize(.small) }
                if let record = model.lastRun {
                    Label(
                        L10n.string(
                            record.succeeded
                                ? "backup.history.success" : "backup.history.failure"),
                        systemImage: record.succeeded
                            ? "checkmark.circle" : "exclamationmark.triangle"
                    )
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

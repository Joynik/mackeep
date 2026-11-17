import SwiftUI

/// The independently updatable library of application definitions.
struct LibraryView: View {
    @Bindable var model: ApplicationsModel
    @Environment(AppEnvironment.self) private var environment
    @State private var searchText = ""
    @State private var showsInstalled = false
    @State private var definitionToRemove: MackeepApplication?

    private var isBusy: Bool { model.isCheckingLibrary || model.isUpdatingLibrary }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                TextField(L10n.string("applications.search.placeholder"), text: $searchText)
                    .textFieldStyle(AppFieldStyle())
                    .frame(minWidth: 100, idealWidth: 180, maxWidth: 220)
                    .accessibilityLabel(L10n.string("applications.search.placeholder"))
                Toggle(
                    L10n.string("filter.applications.installed"),
                    isOn: $showsInstalled
                )
                .toggleStyle(.switch)
                .appSwitchSize()
                .fixedSize()
                Button {
                    Task { await model.updateLibrary() }
                } label: {
                    HStack(spacing: 6) {
                        Label(
                            L10n.string("applications.library.update"),
                            systemImage: "arrow.down.circle"
                        )
                        if !model.libraryUpdates.isEmpty {
                            Text(model.libraryUpdates.count, format: .number)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(width: 20, height: 20)
                                .background(.blue, in: Circle())
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                    }
                }
                .fixedSize()
                .disabled(isBusy || model.libraryUpdates.isEmpty || environment.backup.isRunning)
                .accessibilityIdentifier("applications.library.update")
                Button {
                    Task { await model.checkLibraryUpdates(force: true) }
                } label: {
                    Label(
                        L10n.string("applications.library.checkUpdates"),
                        systemImage: "arrow.clockwise"
                    )
                }
                .fixedSize()
                .disabled(isBusy)
                .help(L10n.string("applications.library.checkUpdates"))
                .accessibilityLabel(L10n.string("applications.library.checkUpdates"))
                .accessibilityIdentifier("applications.library.checkUpdates")
            }
            .appControlSize()
            .padding(16)
            Divider()

            List {
                ForEach(availableNew) { definition in
                    newDefinitionRow(definition)
                }
                ForEach(available, id: \.name) { application in
                    LibraryDefinitionRow(
                        application: application,
                        model: model,
                        isBusy: isBusy,
                        isBackupRunning: environment.backup.isRunning,
                        onRemove: { definitionToRemove = application }
                    )
                }
            }
            .listStyle(.plain)
            .contentMargins(.horizontal, 0, for: .scrollContent)
            .overlay {
                if available.isEmpty && availableNew.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
            }
            Divider()
            libraryStatus
        }
        .frame(minWidth: 820, minHeight: 420)
        .accessibilityIdentifier("applications.library.window")
        .confirmationDialog(
            L10n.string(
                "applications.library.removeConfirm", definitionToRemove?.displayName ?? ""),
            isPresented: Binding(
                get: { definitionToRemove != nil },
                set: { if !$0 { definitionToRemove = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(L10n.string("applications.library.removeDefinition"), role: .destructive) {
                if let definition = definitionToRemove {
                    Task { await model.removeLibraryDefinition(definition) }
                }
                definitionToRemove = nil
            }
            .disabled(isBusy || environment.backup.isRunning)
            Button(L10n.string("editor.create.cancel"), role: .cancel) {
                definitionToRemove = nil
            }
        } message: {
            Text(L10n.string("applications.library.removeExplanation"))
        }
        .task {
            guard !EditorPath.isTesting else { return }
            await model.checkLibraryUpdates()
        }
    }

    private func newDefinitionRow(_ definition: NewLibraryDefinition) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "macwindow")
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                    .accessibilityHidden(true)
                Text(definition.displayName)
                Spacer()
                Label(L10n.string("applications.library.new"), systemImage: "sparkle")
                    .foregroundStyle(.tint)
                    .accessibilityIdentifier("applications.library.new")
                Button {
                    Task { await model.updateLibrary(application: definition.name) }
                } label: {
                    Label(
                        L10n.string("applications.library.download"),
                        systemImage: "arrow.down.circle")
                }
                .disabled(isBusy || environment.backup.isRunning)
                .accessibilityIdentifier("applications.library.download")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            Divider()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
    }

    private var libraryStatus: some View {
        HStack(spacing: 8) {
            if isBusy {
                ProgressView().controlSize(.small)
                Text(
                    L10n.string(
                        model.isUpdatingLibrary
                            ? "applications.library.updating" : "applications.library.checking"
                    ))
            } else if let error = model.libraryError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            } else if let checkedAt = model.libraryCheckedAt {
                Text(L10n.string("applications.library.checked"))
                Text(checkedAt, style: .time)
            }
            Spacer(minLength: 0)
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(12)
    }

    /// Installation cannot be inferred until a new definition's paths are downloaded.
    private var availableNew: [NewLibraryDefinition] {
        guard !showsInstalled else { return [] }
        let knownNames = Set(model.applications.map(\.name))
        return model.newLibraryDefinitions
            .filter { !knownNames.contains($0.name) }
            .filter {
                searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText)
                    || $0.displayName.localizedCaseInsensitiveContains(searchText)
            }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    private var available: [MackeepApplication] {
        model.applications
            .filter { !$0.isCustom }
            .filter { application in
                if showsInstalled && !model.isInstalled(application) { return false }
                guard !searchText.isEmpty else { return true }
                return application.name.localizedCaseInsensitiveContains(searchText)
                    || application.displayName.localizedCaseInsensitiveContains(searchText)
            }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }
}

/// A row of the list of the applications.
struct ApplicationRow: View {
    /// The application.
    let application: MackeepApplication

    /// The model of the list.
    let model: ApplicationsModel

    /// Open the editor without delaying clicks on the toggle.
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Toggle(
                "",
                isOn: Binding(
                    get: { model.isEnabled(application) },
                    set: { model.setEnabled($0, for: application) }
                )
            )
            .labelsHidden()
            .appSwitchSize()
            .accessibilityLabel(
                L10n.string("applications.sync.label", application.displayName)
            )

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(application.displayName)
                        .font(.body)
                    Text(application.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("applications.list.item")

                Spacer(minLength: 8)

                if let error: String = application.error {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .help(error)
                        .accessibilityLabel(L10n.string("applications.error.label"))
                }

                if model.isInstalled(application) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.tint)
                        .help(L10n.string("applications.installed.label"))
                        .accessibilityLabel(L10n.string("applications.installed.label"))
                }

                Image(systemName: application.isCustom ? "person.crop.circle" : "shippingbox")
                    .foregroundStyle(.secondary)
                    .help(
                        application.isCustom
                            ? L10n.string("applications.source.custom")
                            : L10n.string("applications.source.builtin")
                    )
                    .accessibilityLabel(
                        application.isCustom
                            ? L10n.string("applications.source.custom")
                            : L10n.string("applications.source.builtin")
                    )
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2, perform: onEdit)
        }
        .padding(.vertical, 2)
    }
}

private struct LibraryDefinitionRow: View {
    let application: MackeepApplication
    let model: ApplicationsModel
    let isBusy: Bool
    let isBackupRunning: Bool
    let onRemove: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "macwindow")
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                    .accessibilityHidden(true)
                Text(application.displayName)
                Spacer()
                if model.removedLibraryDefinitions.contains(application.name) {
                    Label(
                        L10n.string("applications.library.removed"),
                        systemImage: "minus.circle"
                    )
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("applications.library.removed")
                } else if model.libraryUpdates.contains(application.name) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.callout)
                        .foregroundStyle(.blue)
                        .help(L10n.string("applications.library.updateAvailable"))
                        .accessibilityLabel(L10n.string("applications.library.updateAvailable"))
                        .accessibilityIdentifier("applications.library.updateAvailable")
                }
                if model.isInstalled(application) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                        .help(L10n.string("applications.installed.label"))
                        .accessibilityLabel(L10n.string("applications.installed.label"))
                }
                if model.isListed(application) {
                    Label(L10n.string("applications.library.added"), systemImage: "checkmark")
                        .foregroundStyle(.green)
                        .frame(width: 132, height: AppControl.height)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                } else if !model.removedLibraryDefinitions.contains(application.name) {
                    Button {
                        model.addToTheList(application)
                    } label: {
                        Label(L10n.string("applications.library.addOne"), systemImage: "plus")
                            .foregroundStyle(.blue)
                            .frame(width: 132, height: AppControl.height)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("applications.library.add")
                }
                if model.removedLibraryDefinitions.contains(application.name) {
                    Button(L10n.string("applications.library.removeDefinition")) {
                        onRemove()
                    }
                    .disabled(isBusy || isBackupRunning)
                    .accessibilityIdentifier("applications.library.removeDefinition")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            Divider()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
    }
}

import SwiftUI

/// The sheet that is shown above the list of the applications.
enum ApplicationsSheet: Identifiable {
    /// The sheet that creates an application, or that copies one.
    case creator(ApplicationCreatorModel)

    var id: String {
        switch self {
        case .creator(let model): "creator-\(model.id)"
        }
    }
}

/// The list of the applications of Mackeep.
struct ApplicationsView: View {
    /// The model of the list.
    @Bindable var model: ApplicationsModel

    /// Opens the window of the editor.
    @Environment(\.openWindow) private var openWindow

    /// The sheet that is shown.
    @State private var sheet: ApplicationsSheet?

    /// The application that is deleted, when the confirmation is shown.
    @State private var applicationToDelete: MackeepApplication?

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            list
        }
        .navigationTitle(L10n.string("section.applications.title"))
        .appError($model.presentedError)
        .sheet(item: $sheet) { presented in
            switch presented {
            case .creator(let creator):
                ApplicationCreatorView(
                    model: creator,
                    existing: Set(model.applications.map(\.name)),
                    onCreate: { name in
                        sheet = nil
                        Task {
                            if await model.reload() {
                                model.selection = name
                                openWindow(value: name)
                            }
                        }
                    }
                )
            }
        }
        .task {
            guard !EditorPath.isTesting else { return }
            await model.checkLibraryUpdates()
        }
        .onChange(of: model.copyRequest) { _, application in
            guard let application: MackeepApplication = application else { return }
            openTheCopy(of: application)
        }
        .confirmationDialog(
            L10n.string("applications.delete.confirm", model.selectedApplication?.displayName ?? ""),
            isPresented: Binding(
                get: { applicationToDelete != nil },
                set: { if !$0 { applicationToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(L10n.string("applications.delete"), role: .destructive) {
                if let application: MackeepApplication = applicationToDelete {
                    model.delete(application)
                }
                applicationToDelete = nil
            }
            Button(L10n.string("editor.create.cancel"), role: .cancel) {
                applicationToDelete = nil
            }
        }
    }

    /// The tools of the list.
    private var toolbar: some View {
        VStack(spacing: 13) {
            HStack(spacing: 8) {
                TextField(
                    L10n.string("applications.search.placeholder"),
                    text: $model.searchText
                )
                .textFieldStyle(AppFieldStyle())
                .frame(maxWidth: .infinity)
                .accessibilityLabel(L10n.string("applications.search.placeholder"))

                Picker("", selection: $model.filter) {
                    ForEach(ApplicationFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 200)
                // The menu of macOS has a big padding inside, it is taken
                // away, so the filter stands right next to the search
                .padding(.leading, -32)
                .accessibilityLabel(L10n.string("applications.filter.label"))
            }
            HStack(spacing: 12) {
                Button {
                    openWindow(id: "library")
                } label: {
                    HStack(spacing: 6) {
                        Label(
                            L10n.string("applications.library.button"),
                            systemImage: "books.vertical"
                        )
                        if !model.libraryUpdates.isEmpty {
                            Text(model.libraryUpdates.count, format: .number)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .foregroundStyle(.white)
                                .background(.tint, in: Capsule())
                                .accessibilityLabel(
                                    L10n.string("applications.library.updateAvailable")
                                )
                                .accessibilityIdentifier("applications.library.badge")
                        }
                    }
                }
                .help(L10n.string("applications.library.button"))
                .accessibilityLabel(L10n.string("applications.library.button"))
                .accessibilityIdentifier("applications.library.button")

                Button {
                    sheet = .creator(
                        ApplicationCreatorModel(directory: model.customAppsDirectory)
                    )
                } label: {
                    Label(
                        L10n.string("applications.create.add"),
                        systemImage: "plus.square"
                    )
                }
                .help(L10n.string("applications.create.add"))
                .accessibilityIdentifier("applications.create.button")

                Button {
                    copySelected()
                } label: {
                    Label(
                        L10n.string("applications.copy"),
                        systemImage: "doc.on.doc"
                    )
                }
                .help(L10n.string("applications.copy"))
                .disabled(model.selectedApplication == nil)

                Button {
                    deleteSelected()
                } label: {
                    Label(
                        L10n.string("applications.delete"),
                        systemImage: "trash"
                    )
                }
                .help(L10n.string("applications.delete"))
                .disabled(model.selectedApplication == nil)

                Spacer(minLength: 8)
            }
        }
        // The controls of the panel have the same height, so they line up.
        .appControlSize()
        .padding(12)
    }

    /// Copy the selected application, so it can be changed.
    private func copySelected() {
        guard let application: MackeepApplication = model.selectedApplication else {
            return
        }
        openTheCopy(of: application)
    }

    /// Delete the selected application.
    ///
    /// The applications of the user are deleted with their config file, the
    /// ones of the library are only removed from the list.
    private func deleteSelected() {
        guard let application: MackeepApplication = model.selectedApplication else {
            return
        }

        if application.isCustom {
            // The file is deleted, the user is asked first
            applicationToDelete = application
            return
        }

        model.delete(application)
    }

    /// Open the sheet that copies an application.
    ///
    /// - Parameter application: The application that is copied.
    private func openTheCopy(of application: MackeepApplication) {
        let copy: ApplicationCreatorModel = ApplicationCreatorModel(
            directory: model.customAppsDirectory,
            source: application
        )
        copy.name = "\(application.name)-copy"
        copy.displayName = "\(application.displayName) (copy)"
        sheet = .creator(copy)
    }

    /// The list of the applications.
    private var list: some View {
        List(selection: $model.selection) {
            if model.visibleApplications.isEmpty {
                ContentUnavailableView {
                    Label {
                        Text(L10n.string("applications.list.empty"))
                    } icon: {
                        Image(systemName: "square.grid.2x2")
                    }
                } description: {
                    Text(L10n.string("applications.list.empty.hint"))
                }
                .listRowSeparator(.hidden)
            }

            Section {
                ForEach(model.visibleApplications) { application in
                    ApplicationRow(application: application, model: model) {
                        edit(application)
                    }
                        .tag(application.name)
                        .contextMenu {
                            if application.isCustom {
                                Button(L10n.string("applications.edit")) {
                                    edit(application)
                                }
                            }
                            Button(L10n.string("applications.copy")) {
                                model.selection = application.name
                                copySelected()
                            }
                            Button(
                                L10n.string("applications.delete"),
                                role: .destructive
                            ) {
                                model.selection = application.name
                                deleteSelected()
                            }
                        }
                }
            } header: {
                Text(
                    L10n.string(
                        "applications.count",
                        model.visibleApplications.count
                    )
                )
            }
        }
        .listStyle(.inset)
    }

    /// Open the editor of an application.
    ///
    /// The applications of the library cannot be changed, they have to be
    /// copied first.
    ///
    /// - Parameter application: The application.
    private func edit(_ application: MackeepApplication) {
        guard application.isCustom else { return }
        openWindow(value: application.name)
    }
}

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
                    Label(
                        L10n.string("applications.library.update"),
                        systemImage: "arrow.down.circle"
                    )
                }
                .disabled(isBusy || model.libraryUpdates.isEmpty || environment.backup.isRunning)
                .accessibilityIdentifier("applications.library.update")
                Button {
                    Task { await model.checkLibraryUpdates(force: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
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
                    definitionRow(application)
                }
            }
            .listStyle(.inset)
            .overlay {
                if available.isEmpty && availableNew.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
            }
            Divider()
            libraryStatus
        }
        .frame(minWidth: 720, minHeight: 420)
        .accessibilityIdentifier("applications.library.window")
        .confirmationDialog(
            L10n.string("applications.library.removeConfirm", definitionToRemove?.displayName ?? ""),
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

    private func newDefinitionRow(_ definition: LibraryStatus.NewDefinition) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "app.dashed")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(definition.displayName)
            Spacer()
            Label(L10n.string("applications.library.new"), systemImage: "sparkle")
                .foregroundStyle(.tint)
                .accessibilityIdentifier("applications.library.new")
            Button {
                Task { await model.updateLibrary(application: definition.name) }
            } label: {
                Label(L10n.string("applications.library.download"), systemImage: "arrow.down.circle")
            }
            .disabled(isBusy || environment.backup.isRunning)
            .accessibilityIdentifier("applications.library.download")
        }
        .padding(.vertical, 6)
    }

    private func definitionRow(_ application: MackeepApplication) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "app.dashed")
                .foregroundStyle(.secondary)
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
                Label(
                    L10n.string("applications.library.updateAvailable"),
                    systemImage: "arrow.down.circle.fill"
                )
                .font(.callout)
                .foregroundStyle(.tint)
                .accessibilityIdentifier("applications.library.updateAvailable")
            }
            if model.isInstalled(application) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .help(L10n.string("applications.installed.label"))
                    .accessibilityLabel(L10n.string("applications.installed.label"))
            }
            if model.isListed(application) {
                Text(L10n.string("applications.library.added"))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 80, alignment: .trailing)
            } else if !model.removedLibraryDefinitions.contains(application.name) {
                Button {
                    model.addToTheList(application)
                } label: {
                    Label(L10n.string("applications.library.addOne"), systemImage: "plus")
                }
                .accessibilityIdentifier("applications.library.add")
            }
            if model.removedLibraryDefinitions.contains(application.name) {
                Button(L10n.string("applications.library.removeDefinition")) {
                    definitionToRemove = application
                }
                .disabled(isBusy || environment.backup.isRunning)
                .accessibilityIdentifier("applications.library.removeDefinition")
            }
        }
        .padding(.vertical, 6)
    }

    private var libraryStatus: some View {
        HStack(spacing: 8) {
            if isBusy {
                ProgressView().controlSize(.small)
                Text(L10n.string(
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
    private var availableNew: [LibraryStatus.NewDefinition] {
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
private struct ApplicationRow: View {
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

import SwiftUI

/// The list of the applications of Mackeep.
struct ApplicationsView: View {
    /// The model of the list.
    @Bindable var model: ApplicationsModel

    /// Opens the window of the editor.
    @Environment(\.openWindow) private var openWindow

    /// Whether the sheet of the creation is shown.
    @State private var showsCreator = false

    /// Whether the sheet of the library is shown.
    @State private var showsLibrary = false

    /// The model of the creation.
    @State private var creator: ApplicationCreatorModel?

    /// The application that is deleted, when the confirmation is shown.
    @State private var applicationToDelete: MackeepApplication?

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            list
        }
        .navigationTitle(L10n.string("section.applications.title"))
        .sheet(isPresented: $showsCreator) {
            if let creator {
                ApplicationCreatorView(
                    model: creator,
                    existing: Set(model.applications.map(\.name)),
                    onCreate: { name in
                        showsCreator = false
                        model.load()
                        if let editor: ApplicationEditorModel = model.editor(for: name) {
                            openWindow(value: name)
                            _ = editor
                        }
                    }
                )
            }
        }
        .sheet(isPresented: $showsLibrary) {
            LibraryView(model: model)
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
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                TextField(
                    L10n.string("applications.search.placeholder"),
                    text: $model.searchText
                )
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel(L10n.string("applications.search.placeholder"))

                Picker("", selection: $model.filter) {
                    ForEach(ApplicationFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 200)
                .accessibilityLabel(L10n.string("applications.filter.label"))
            }

            HStack(spacing: 8) {
                Button {
                    showsLibrary = true
                } label: {
                    Image(systemName: "books.vertical")
                }
                .help(L10n.string("applications.library.add"))
                .accessibilityLabel(L10n.string("applications.library.add"))
                .accessibilityIdentifier("applications.library.button")

                Button {
                    creator = ApplicationCreatorModel(
                        directory: model.customAppsDirectory
                    )
                    showsCreator = true
                } label: {
                    Label(
                        L10n.string("applications.create.add"),
                        systemImage: "plus.square"
                    )
                }
                .help(L10n.string("applications.create.add"))

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

                Spacer(minLength: 8)
            }
        }
        .padding(12)
    }

    /// Copy the selected application, so it can be changed.
    private func copySelected() {
        guard let application: MackeepApplication = model.selectedApplication else {
            return
        }
        openTheCopy(of: application)
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
        creator = copy
        showsCreator = true
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
                    ApplicationRow(application: application, model: model)
                        .tag(application.name)
                        .onTapGesture(count: 2) {
                            edit(application)
                        }
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
                            if application.isCustom {
                                Button(L10n.string("applications.delete"), role: .destructive) {
                                    applicationToDelete = application
                                }
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

/// The library of the applications of Mackeep.
private struct LibraryView: View {
    /// The model of the list.
    @Bindable var model: ApplicationsModel

    /// The text of the search.
    @State private var searchText: String = ""

    /// Whether only the applications installed on this Mac are shown.
    @State private var showsInstalled = false

    /// Whether the sheet is shown.
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.string("applications.library.title"))
                .font(.title3.weight(.semibold))
                .accessibilityIdentifier("applications.library.title")

            HStack(spacing: 8) {
                TextField(
                    L10n.string("applications.search.placeholder"),
                    text: $searchText
                )
                .textFieldStyle(.roundedBorder)

                Toggle(
                    L10n.string("filter.applications.installed"),
                    isOn: $showsInstalled
                )
                .toggleStyle(.switch)
                .fixedSize()
            }

            List(available, id: \.name) { application in
                HStack {
                    Text(application.displayName)
                    Spacer()
                    if model.isInstalled(application) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.tint)
                            .help(L10n.string("applications.installed.label"))
                            .accessibilityLabel(
                                L10n.string("applications.installed.label")
                            )
                    }
                    if model.isListed(application) {
                        Text(L10n.string("applications.library.added"))
                            .foregroundStyle(.secondary)
                    } else {
                        Button(L10n.string("applications.library.addOne")) {
                            model.addToTheList(application)
                        }
                        .buttonStyle(.link)
                        .accessibilityIdentifier("applications.library.add")
                    }
                }
            }
            .frame(minHeight: 320)

            HStack {
                Spacer()
                Button(L10n.string("applications.library.close")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("applications.library.close")
            }
        }
        .padding(20)
        .frame(width: 520, height: 480)
    }

    /// The applications of the library.
    private var available: [MackeepApplication] {
        model.applications
            .filter { !$0.isCustom }
            .filter { application in
                if showsInstalled && !model.isInstalled(application) { return false }
                guard !searchText.isEmpty else { return true }
                return application.name.localizedCaseInsensitiveContains(searchText)
                    || application.displayName.localizedCaseInsensitiveContains(searchText)
            }
    }
}

/// A row of the list of the applications.
private struct ApplicationRow: View {
    /// The application.
    let application: MackeepApplication

    /// The model of the list.
    let model: ApplicationsModel

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
            .accessibilityLabel(
                L10n.string("applications.sync.label", application.displayName)
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(application.displayName)
                    .font(.body)
                Text(application.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityIdentifier("applications.list.item")

            Spacer(minLength: 8)

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
        .padding(.vertical, 2)
    }
}

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
            L10n.string(
                "applications.delete.confirm", model.selectedApplication?.displayName ?? ""),
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

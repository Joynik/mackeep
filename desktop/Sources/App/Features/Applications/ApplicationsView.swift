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
                .frame(width: 140)
                .accessibilityLabel(L10n.string("applications.filter.label"))

                Picker("", selection: $model.sort) {
                    ForEach(ApplicationSort.allCases) { sort in
                        Text(sort.title).tag(sort)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 140)
                .accessibilityLabel(L10n.string("applications.sort.label"))
            }

            HStack(spacing: 8) {
                Button {
                    showsLibrary = true
                } label: {
                    Label(
                        L10n.string("applications.library.add"),
                        systemImage: "tray.full"
                    )
                }
                .help(L10n.string("applications.library.add"))

                Button {
                    creator = ApplicationCreatorModel(
                        directory: URL(fileURLWithPath: NSHomeDirectory())
                            .appendingPathComponent(".mackeep")
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
                    copyBuiltin()
                } label: {
                    Label(
                        L10n.string("applications.copyBuiltin"),
                        systemImage: "doc.on.doc"
                    )
                }
                .help(L10n.string("applications.copyBuiltin"))

                Spacer(minLength: 8)

                Picker("", selection: $model.mode) {
                    Text(L10n.string("applications.mode.allExcept")).tag(SyncMode.allExceptUnchecked)
                    Text(L10n.string("applications.mode.onlyChecked")).tag(SyncMode.onlyChecked)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel(L10n.string("applications.mode.label"))
            }
        }
        .padding(12)
    }

    /// Copy the config file of a built-in application, so it can be changed.
    private func copyBuiltin() {
        guard
            let application: MackeepApplication = model.selectedApplication,
            application.source == .builtin
        else {
            return
        }
        do {
            let directory: URL = URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent(".mackeep")
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let source: URL = URL(fileURLWithPath: application.cfgPath)
            let destination: URL = directory.appendingPathComponent(
                "\(application.name).cfg"
            )
            guard !FileManager.default.fileExists(atPath: destination.path) else {
                return
            }
            try FileManager.default.copyItem(at: source, to: destination)
            model.load()
            openWindow(value: application.name)
        } catch {
            model.presentedError = AppError(
                title: L10n.string("error.save.title"),
                message: "\(error)"
            )
        }
    }

    /// The list of the applications.
    private var list: some View {
        List(selection: $model.selection) {
            Section {
                ForEach(model.visibleApplications) { application in
                    ApplicationRow(application: application, model: model)
                        .tag(application.name)
                        .onTapGesture(count: 2) {
                            openWindow(value: application.name)
                        }
                        .contextMenu {
                            Button(L10n.string("applications.edit")) {
                                openWindow(value: application.name)
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
}

/// The applications of the database of Mackeep that are not synced yet.
private struct LibraryView: View {
    /// The model of the list.
    @Bindable var model: ApplicationsModel

    /// The text of the search.
    @State private var searchText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.string("applications.library.title"))
                .font(.title3.weight(.semibold))

            TextField(
                L10n.string("applications.search.placeholder"),
                text: $searchText
            )
            .textFieldStyle(.roundedBorder)

            List(available, id: \.name) { application in
                HStack {
                    Text(application.displayName)
                    Spacer()
                    Button(L10n.string("applications.library.add")) {
                        add(application)
                    }
                    .buttonStyle(.link)
                }
            }
            .frame(minHeight: 320)

            HStack {
                Spacer()
                Button(L10n.string("editor.create.cancel"), role: .cancel) {}
            }
        }
        .padding(20)
        .frame(width: 460, height: 460)
    }

    /// The applications that can be added.
    private var available: [MackeepApplication] {
        model.applications
            .filter { $0.source == .builtin }
            .filter { !model.isSynced($0) }
            .filter { application in
                guard !searchText.isEmpty else { return true }
                return application.name.localizedCaseInsensitiveContains(searchText)
                    || application.displayName.localizedCaseInsensitiveContains(searchText)
            }
    }

    /// Add an application to the applications that are synced.
    private func add(_ application: MackeepApplication) {
        model.setSynced(true, for: application)
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
                    get: { model.isSynced(application) },
                    set: { model.setSynced($0, for: application) }
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

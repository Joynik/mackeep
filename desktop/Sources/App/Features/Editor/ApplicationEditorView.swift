import SwiftUI

/// The editor of the config file of an application.
struct ApplicationEditorView: View {
    /// The model of the editor.
    @Bindable var model: ApplicationEditorModel
    @Environment(AppEnvironment.self) private var environment

    /// The error shown to the user, when there is one.
    @State private var presentedError: AppError?

    /// Whether the file was changed by something else.
    @State private var showsReloadAlert = false

    /// Whether the window of the search is shown.
    @State private var showsSearch = false

    /// The model of the search of the files.
    @State private var search = ApplicationSearchModel()

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            content
            Divider()
            footer
        }
        .frame(minWidth: 720, minHeight: 520)
        .disabled(environment.backup.isRunning)
        .navigationTitle(model.title)
        // The controls of the window have the same height, so they line up.
        .appControlSize()
        .appError($presentedError)
        .sheet(isPresented: $showsSearch) {
            ApplicationSearchView(model: search, editor: model)
                .onAppear {
                    setThePathsOfTheSearch()
                    search.start()
                }
                .onDisappear { search.cancel() }
        }
        .alert(
            L10n.string("editor.reload.title"),
            isPresented: $showsReloadAlert
        ) {
            Button(L10n.string("editor.reload.reload")) {
                reload()
            }
            Button(L10n.string("editor.reload.overwrite"), role: .destructive) {
                save(overwrite: true)
            }
            Button(L10n.string("editor.reload.cancel"), role: .cancel) {
                showsReloadAlert = false
            }
        } message: {
            Text(L10n.string("editor.reload.message"))
        }
        .onAppear { model.validate() }
        .onReceive(
            NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
        ) { _ in
            model.validate()
            if model.hasChangedOutside() { showsReloadAlert = true }
        }
    }

    /// The tools of the editor.
    private var toolbar: some View {
        HStack(spacing: 8) {
            Button {
                openTheSearch()
            } label: {
                Label(
                    L10n.string("editor.search.button"),
                    systemImage: "magnifyingglass"
                )
            }
            .help(L10n.string("editor.search.button"))
            .padding(.leading, 24)

            Spacer(minLength: 12)

            Picker("", selection: $model.isTextMode) {
                Text(L10n.string("editor.mode.form")).tag(false)
                Text(L10n.string("editor.mode.text")).tag(true)
            }
            .pickerStyle(.segmented)
            .frame(width: 200)
            .labelsHidden()
        }
        .padding(12)
        .onChange(of: model.paths) {
            if showsSearch { setThePathsOfTheSearch() }
        }
        .onChange(of: model.xdgPaths) {
            if showsSearch { setThePathsOfTheSearch() }
        }
    }

    /// Open the window that finds the files of the application.
    private func openTheSearch() {
        // The folders of the application are searched, they are read here,
        // the paths of the application are not changed when the window opens.
        showsSearch = true
    }

    /// Tell the search which files of the application it has to look at.
    private func setThePathsOfTheSearch() {
        search.setPaths(
            model.paths,
            xdgPaths: model.xdgPaths,
            name: model.displayName,
            identifier: model.appName
        )
    }

    /// The form or the text of the config file.
    @ViewBuilder
    private var content: some View {
        if model.isTextMode {
            textEditor
        } else {
            form
        }
    }

    /// The form of the config file.
    private var form: some View {
        Form {
            Section {
                HStack(alignment: .center, spacing: 16) {
                    FieldInfoLabel(
                        title: L10n.string("editor.create.name.placeholder"),
                        hint: L10n.string("editor.name.placeholder"))
                    LeadingTextField(
                        text: Binding(
                            get: { model.displayName },
                            set: { newValue in
                                model.remember()
                                model.displayName = newValue
                            }
                        )
                    )
                    .appFieldStyle()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel(L10n.string("editor.create.name.placeholder"))
                }
            } header: {
                BlockHeader(
                    title: L10n.string("editor.section.application"),
                    description: L10n.string("editor.section.application.description")
                )
            }

            Section {
                PathEditorView(
                    title: L10n.string("editor.paths.title"),
                    paths: Binding(
                        get: { model.paths },
                        set: { newValue in
                            model.remember()
                            model.paths = newValue
                        }
                    ),
                    isXDG: false,
                    onAdd: { path in
                        model.remember()
                        model.addPath(path, isXDG: false)
                    },
                    onRemove: { path in
                        model.remember()
                        model.removePath(path)
                    }
                )
            } header: {
                BlockHeader(
                    title: L10n.string("editor.section.configurationFiles"),
                    description: L10n.string(
                        "editor.section.configurationFiles.description"
                    )
                )
            }

            Section {
                PathEditorView(
                    title: L10n.string("editor.paths.title"),
                    paths: Binding(
                        get: { model.xdgPaths },
                        set: { newValue in
                            model.remember()
                            model.xdgPaths = newValue
                        }
                    ),
                    isXDG: true,
                    onAdd: { path in
                        model.remember()
                        model.addPath(path, isXDG: true)
                    },
                    onRemove: { path in
                        model.remember()
                        model.removePath(path)
                    }
                )
            } header: {
                BlockHeader(
                    title: L10n.string("editor.section.xdgConfigurationFiles"),
                    description: L10n.string(
                        "editor.section.xdgConfigurationFiles.description"
                    )
                )
            }

            Section {
                ExclusionsEditorView(
                    paths: model.paths,
                    patterns: Binding(
                        get: { model.excludes },
                        set: { newValue in
                            model.remember()
                            model.setExcludes(newValue, isXDG: false)
                        }
                    ),
                    isXDG: false,
                    globalPatterns: model.globalExcludes(isXDG: false)
                )
            } header: {
                BlockHeader(
                    title: L10n.string("editor.section.exclude"),
                    description: L10n.string("editor.section.exclude.description")
                )
            }

            Section {
                ExclusionsEditorView(
                    paths: model.xdgPaths,
                    patterns: Binding(
                        get: { model.xdgExcludes },
                        set: { newValue in
                            model.remember()
                            model.setExcludes(newValue, isXDG: true)
                        }
                    ),
                    isXDG: true,
                    globalPatterns: model.globalExcludes(isXDG: true)
                )
            } header: {
                BlockHeader(
                    title: L10n.string("editor.section.xdgExclude"),
                    description: L10n.string("editor.section.xdgExclude.description")
                )
            }
        }
        .formStyle(.grouped)
    }

    /// The text of the config file.
    private var textEditor: some View {
        VStack(spacing: 0) {
            TextEditor(text: Binding(
                get: { model.text },
                set: { newValue in
                    model.remember()
                    model.text = newValue
                }
            ))
            .font(.body.monospaced())
            .padding(8)
            .accessibilityLabel(L10n.string("editor.text.label"))
        }
    }

    /// The bottom bar of the editor.
    private var footer: some View {
        HStack(spacing: 12) {
            if !model.issues.isEmpty {
                Label(
                    L10n.string(
                        "editor.issues.count",
                        model.issues.count
                    ),
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }

            Spacer(minLength: 12)

            if model.hasUnsavedChanges {
                Text(L10n.string("editor.unsaved"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button(L10n.string("editor.undo")) {
                model.undo()
            }
            .keyboardShortcut("z", modifiers: .command)
            .disabled(!model.canUndo)

            Button(L10n.string("editor.save")) {
                save()
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(!model.canSave)
        }
        .padding(12)
    }

    /// Write the config file.
    private func save(overwrite: Bool = false) {
        if !overwrite && model.hasChangedOutside() { showsReloadAlert = true; return }
        do {
            try model.save(overwrite: overwrite)
        } catch {
            presentedError = AppError(
                title: L10n.string("error.save.title"),
                message: error.localizedDescription
            )
        }
    }

    /// Read the config file again.
    private func reload() {
        do {
            try model.reload()
        } catch {
            presentedError = AppError(
                title: L10n.string("error.load.title"),
                message: error.localizedDescription
            )
        }
    }
}

/// The title of a block of the config file, with its description.
struct BlockHeader: View {
    /// The title of the block.
    let title: String

    /// What the block does, in a few words.
    let description: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .textCase(nil)
    }
}

/// The list of the paths of an application.
struct PathEditorView: View {
    /// The title of the list.
    let title: String

    /// The paths.
    @Binding var paths: [EditorPath]

    /// Whether the paths are the XDG ones.
    let isXDG: Bool

    /// The callback called when a path is added.
    let onAdd: (String) -> Void

    /// The callback called when a path is removed.
    let onRemove: (EditorPath) -> Void

    /// The path that is written.
    @State private var newPath: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }

            if paths.isEmpty {
                Text(L10n.string("editor.paths.empty"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(paths) { path in
                    HStack(spacing: 8) {
                        Image(systemName: path.exists
                            ? (path.url.hasDirectoryPath ? "folder" : "doc")
                            : "questionmark.folder")
                            .foregroundStyle(path.exists ? Color.secondary : Color.orange)

                        Text(path.path)
                            .font(.callout.monospaced())
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Spacer(minLength: 8)

                        Button {
                            onRemove(path)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help(L10n.string("editor.paths.remove"))
                    }
                }
            }

            Divider()

            HStack(spacing: 16) {
                FieldInfoLabel(
                    title: L10n.string("editor.paths.label"),
                    hint: L10n.string("editor.paths.placeholder"))
                TextField(
                    "",
                    text: $newPath
                )
                .textFieldStyle(AppFieldStyle())
                .accessibilityLabel(L10n.string("editor.paths.label"))
                .font(.callout.monospaced())
                .lineLimit(1)
                .onSubmit {
                    add()
                }

                Button(L10n.string("editor.paths.add")) {
                    add()
                }
                .disabled(newPath.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    /// Add the path that is written.
    private func add() {
        let path: String = newPath.trimmingCharacters(in: .whitespaces)
        guard !path.isEmpty else { return }
        onAdd(path)
        newPath = ""
    }
}

import SwiftUI
import UniformTypeIdentifiers

/// The editor of the config file of an application.
struct ApplicationEditorView: View {
    /// The model of the editor.
    @Bindable var model: ApplicationEditorModel

    /// The error shown to the user, when there is one.
    @State private var presentedError: AppError?

    /// Whether the file was changed by something else.
    @State private var showsReloadAlert = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            content
            Divider()
            footer
        }
        .frame(minWidth: 720, minHeight: 520)
        .navigationTitle(model.title)
        .alert(
            L10n.string("editor.reload.title"),
            isPresented: $showsReloadAlert
        ) {
            Button(L10n.string("editor.reload.reload")) {
                reload()
            }
            Button(L10n.string("editor.reload.cancel"), role: .cancel) {}
        } message: {
            Text(L10n.string("editor.reload.message"))
        }
        .onAppear {
            model.validate()
        }
    }

    /// The tools of the editor.
    private var toolbar: some View {
        HStack(spacing: 8) {
            ForEach(EditorSection.allCases) { section in
                Button {
                    model.remember()
                    model.addSection(section)
                } label: {
                    Text("[\(section.rawValue)]")
                        .font(.callout.monospaced())
                }
                .buttonStyle(.bordered)
                .disabled(model.sections.contains(section))
            }

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
            Section(L10n.string("editor.section.application")) {
                TextField(
                    L10n.string("editor.name.placeholder"),
                    text: Binding(
                        get: { model.displayName },
                        set: { newValue in
                            model.remember()
                            model.displayName = newValue
                        }
                    )
                )
            }

            Section(L10n.string("editor.section.configurationFiles")) {
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
                    onAdd: { url in
                        model.remember()
                        model.addPath(url, isXDG: false)
                    },
                    onRemove: { path in
                        model.remember()
                        model.removePath(path)
                    }
                )
            }

            Section(L10n.string("editor.section.xdgConfigurationFiles")) {
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
                    onAdd: { url in
                        model.remember()
                        model.addPath(url, isXDG: true)
                    },
                    onRemove: { path in
                        model.remember()
                        model.removePath(path)
                    }
                )
            }

            Section(L10n.string("editor.section.exclude")) {
                ExclusionsEditorView(
                    paths: model.paths,
                    patterns: Binding(
                        get: { model.excludes },
                        set: { newValue in
                            model.remember()
                            model.setExcludes(newValue, isXDG: false)
                        }
                    ),
                    isXDG: false
                )
            }

            Section(L10n.string("editor.section.xdgExclude")) {
                ExclusionsEditorView(
                    paths: model.xdgPaths,
                    patterns: Binding(
                        get: { model.xdgExcludes },
                        set: { newValue in
                            model.remember()
                            model.setExcludes(newValue, isXDG: true)
                        }
                    ),
                    isXDG: true
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
    private func save() {
        do {
            try model.save()
        } catch {
            presentedError = AppError(
                title: L10n.string("error.save.title"),
                message: "\(error)"
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
                message: "\(error)"
            )
        }
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
    let onAdd: (URL) -> Void

    /// The callback called when a path is removed.
    let onRemove: (EditorPath) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    choose()
                } label: {
                    Label(
                        L10n.string("editor.paths.add"),
                        systemImage: "plus"
                    )
                }
                .buttonStyle(.link)
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
        }
    }

    /// Ask for a file or a folder.
    private func choose() {
        let panel: NSOpenPanel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory())
        if panel.runModal() == .OK, let url: URL = panel.url {
            onAdd(url)
        }
    }
}

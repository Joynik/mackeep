import AppKit
import SwiftUI

/// The application editor form, using project-relative paths instead of HOME/XDG.
struct ProjectEditorView: View {
    let model: ProjectsModel
    @State var project: MackeepProject
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    HStack(alignment: .center, spacing: 16) {
                        FieldInfoLabel(
                            title: L10n.string("projects.name"),
                            hint: L10n.string("editor.name.placeholder"))
                        LeadingTextField(text: $project.name)
                            .appFieldStyle()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityLabel(L10n.string("projects.name"))
                    }
                    HStack(alignment: .center, spacing: 16) {
                        FieldInfoLabel(
                            title: L10n.string("projects.root"),
                            hint: L10n.string("projects.paths.help"))
                        LeadingTextField(text: $project.root)
                            .appFieldStyle()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityLabel(L10n.string("projects.root"))
                        Button {
                            chooseRoot()
                        } label: {
                            Image(systemName: "folder")
                        }
                        .help(L10n.string("projects.chooseRoot"))
                    }
                } header: {
                    BlockHeader(
                        title: L10n.string("section.projects.title"),
                        description: L10n.string("projects.paths.help"))
                }
                Section {
                    PathEditorView(
                        title: L10n.string("editor.paths.title"),
                        paths: Binding(get: { paths }, set: { project.files = $0.map(\.path) }),
                        isXDG: false,
                        onAdd: { path in
                            if !project.files.contains(path) { project.files.append(path) }
                        },
                        onRemove: { path in project.files.removeAll { $0 == path.path } })
                } header: {
                    BlockHeader(
                        title: L10n.string("editor.section.configurationFiles"),
                        description: L10n.string("projects.paths.help"))
                }
                Section {
                    ExclusionsEditorView(
                        paths: paths, patterns: $project.exclude, isXDG: false,
                        projectRoot: root)
                } header: {
                    BlockHeader(
                        title: L10n.string("editor.section.exclude"),
                        description: L10n.string("projects.paths.help"))
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack(spacing: 12) {
                Spacer(minLength: 12)
                Button(L10n.string("editor.create.cancel"), role: .cancel) { dismiss() }
                Button(L10n.string("editor.save")) {
                    Task { if await model.save(project) { dismiss() } }
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!model.canSave(project) || model.isWorking)
            }
            .padding(12)
        }
        .frame(minWidth: 720, minHeight: 520)
        .navigationTitle(L10n.string("projects.editor.title"))
        .appControlSize()
        .disabled(model.isWorking)
        .appError(Binding(get: { model.presentedError }, set: { model.presentedError = $0 }))
    }

    private var root: URL { URL(fileURLWithPath: project.root, isDirectory: true) }

    private var paths: [EditorPath] {
        project.files.map { EditorPath(path: $0, projectRoot: root) }
    }

    private func chooseRoot() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { project.root = url.path }
    }
}

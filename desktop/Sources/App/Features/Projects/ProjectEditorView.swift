import AppKit
import SwiftUI

/// Project paths are relative to one user-selected root, never HOME or XDG.
struct ProjectEditorView: View {
    let model: ProjectsModel
    @State var project: MackeepProject
    @State private var files = ""
    @State private var exclusions = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.string("projects.editor.title"))
                .font(.title3.weight(.semibold))
            Form {
                TextField(L10n.string("projects.name"), text: $project.name)
                    .textFieldStyle(AppFieldStyle())
                LabeledContent(L10n.string("projects.root")) {
                    HStack {
                        TextField("/", text: $project.root)
                            .textFieldStyle(AppFieldStyle())
                            .accessibilityLabel(L10n.string("projects.root"))
                        Button {
                            chooseRoot()
                        } label: {
                            Image(systemName: "folder")
                        }
                        .help(L10n.string("projects.chooseRoot"))
                    }
                }
            }
            .formStyle(.grouped)
            .frame(height: 140)
            pathEditor("projects.files", text: $files)
            pathEditor("projects.exclude", text: $exclusions)
            Text(L10n.string("projects.paths.help"))
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button(L10n.string("editor.create.cancel"), role: .cancel) { dismiss() }
                Button(L10n.string("projects.save")) {
                    project.files = Self.lines(files)
                    project.exclude = Self.lines(exclusions)
                    Task {
                        if await model.save(project) { dismiss() }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!model.canSave(project) || model.isWorking)
            }
        }
        .padding(20)
        .frame(width: 620)
        .appControlSize()
        .disabled(model.isWorking)
        .appError(
            Binding(
                get: { model.presentedError }, set: { model.presentedError = $0 })
        )
        .onAppear {
            files = project.files.joined(separator: "\n")
            exclusions = project.exclude.joined(separator: "\n")
        }
    }

    private func pathEditor(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.string(title)).font(.headline)
            TextEditor(text: text)
                .font(.body.monospaced())
                .frame(height: 110)
                .border(.separator)
                .accessibilityLabel(L10n.string(title))
        }
    }

    private func chooseRoot() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { project.root = url.path }
    }

    private static func lines(_ text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

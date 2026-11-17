import SwiftUI

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
                        Image(
                            systemName: path.exists
                                ? (path.url.hasDirectoryPath ? "folder" : "doc")
                                : "questionmark.folder"
                        )
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

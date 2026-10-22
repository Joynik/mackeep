import SwiftUI

/// The window that finds the files of an application.
///
/// The folders of the application are searched, the files and the folders
/// that are found can be added to the application.
struct ApplicationSearchView: View {
    /// The model of the search.
    @Bindable var model: ApplicationSearchModel

    /// The editor of the application.
    let editor: ApplicationEditorModel

    /// Closes the window.
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.string("editor.search.title"))
                .font(.title3.weight(.semibold))

            TextField(
                L10n.string("editor.search.placeholder"),
                text: $model.searchText
            )
            .textFieldStyle(AppFieldStyle())
            .onSubmit {
                model.search()
            }

            HStack {
                Text(L10n.string("editor.search.count", model.results.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 5)

                Spacer()

                if model.isSearching {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if !model.hasFolders {
                Text(L10n.string("editor.search.noFolders"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else if model.results.isEmpty && !model.isSearching {
                Text(L10n.string("editor.search.empty"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                List(model.results) { file in
                    HStack(spacing: 8) {
                        Image(systemName: file.isDirectory ? "folder" : "doc")
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(file.isXDG ? "XDG" : "HOME").font(.caption).foregroundStyle(
                                .secondary)
                            Text(file.relativePath)
                                .font(.callout.monospaced())
                                .lineLimit(1)
                                .truncationMode(.middle)
                            if !file.sizeText.isEmpty {
                                Text(file.sizeText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer(minLength: 8)

                        if model.isKnown(file) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.tint)
                                .help(L10n.string("editor.search.added"))
                        } else {
                            HStack(spacing: 8) {
                                Button {
                                    add(file)
                                } label: {
                                    Image(systemName: "plus.circle")
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.tint)
                                .help(L10n.string("editor.search.add"))

                                Button {
                                    exclude(file)
                                } label: {
                                    Image(systemName: "minus.circle")
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.orange)
                                .help(L10n.string("editor.search.exclude"))
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                }
                .listStyle(.plain)
                .contentMargins(.horizontal, 0, for: .scrollContent)
            }

            HStack {
                Spacer()
                Button(L10n.string("editor.search.close")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 710, height: 480)
        // The controls of the window have the same height, so they line up.
        .appControlSize()
    }

    /// Add a file to the application.
    ///
    /// - Parameter file: The file that was found.
    private func add(_ file: FoundFile) {
        editor.addPath(
            EditorPath(path: file.relativePath, isXDG: file.isXDG)
        )
        model.search()
    }

    /// Add a file to the exclusions of the application.
    ///
    /// - Parameter file: The file that was found.
    private func exclude(_ file: FoundFile) {
        editor.addExclude(
            EditorPath(path: file.relativePath, isXDG: file.isXDG)
        )
        model.search()
    }
}

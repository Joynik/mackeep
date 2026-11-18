import SwiftUI

/// Project details use the same cards and actions as application details.
struct ProjectDetailView: View {
    let project: MackeepProject
    let onEdit: () -> Void
    let onCopy: () -> Void
    let onDelete: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(project.name).font(.title2.weight(.semibold))
                    Text(project.root)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                HStack(spacing: 8) {
                    Button(action: onEdit) {
                        Label(L10n.string("applications.edit"), systemImage: "pencil")
                    }
                    Button(action: onCopy) {
                        Label(L10n.string("applications.copy"), systemImage: "doc.on.doc")
                    }
                    Button(role: .destructive, action: onDelete) {
                        Label(L10n.string("applications.delete"), systemImage: "trash")
                    }
                }
                .appControlSize()
                CardView(title: L10n.string("applications.paths.title")) {
                    if project.files.isEmpty {
                        Text(L10n.string("applications.paths.empty")).foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(project.files, id: \.self) { path in
                                PathRow(path: resolvedPath(path))
                            }
                        }
                    }
                }
                CardView(title: L10n.string("applications.exclusions.title")) {
                    if project.exclude.isEmpty {
                        Text(L10n.string("applications.exclusions.empty")).foregroundStyle(
                            .secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(project.exclude, id: \.self) { pattern in
                                Text(pattern).font(.callout.monospaced())
                            }
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func resolvedPath(_ path: String) -> MackeepPath {
        let url = URL(fileURLWithPath: project.root, isDirectory: true)
            .appendingPathComponent(path)
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return MackeepPath(path: path, exists: exists, isDir: isDirectory.boolValue)
    }
}

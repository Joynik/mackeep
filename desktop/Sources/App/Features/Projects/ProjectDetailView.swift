import SwiftUI

/// Project details use the same cards and actions as application details.
struct ProjectDetailView: View {
    let project: MackeepProject
    let onEdit: () -> Void
    let onCopy: () -> Void
    let onDelete: () -> Void
    @State private var size = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(project.name).font(.title2.weight(.semibold))
                    Text(project.root)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Label(
                        L10n.string(
                            "applications.size.label",
                            ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
                        ),
                        systemImage: "internaldrive"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
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
        .task(id: [project.root] + project.files) { await estimateSize() }
    }

    private func estimateSize() async {
        size = 0
        let project = project
        let worker = Task.detached(priority: .utility) {
            let root = URL(fileURLWithPath: project.root, isDirectory: true)
            let paths = Set(
                project.files.map { root.appendingPathComponent($0).standardizedFileURL })
            var total = 0
            for path in paths {
                if Task.isCancelled { return 0 }
                total += ApplicationsModel.size(of: path)
            }
            return total
        }
        let total = await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }
        if !Task.isCancelled { size = total }
    }

    private func resolvedPath(_ path: String) -> MackeepPath {
        let url = URL(fileURLWithPath: project.root, isDirectory: true)
            .appendingPathComponent(path)
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return MackeepPath(path: path, exists: exists, isDir: isDirectory.boolValue)
    }
}

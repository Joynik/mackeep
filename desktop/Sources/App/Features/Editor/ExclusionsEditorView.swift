import SwiftUI

/// The editor of the exclusion rules of an application.
///
/// The folders of the application are shown as a tree: unchecking an item
/// adds it to the exclusion rules. A mask can be written by hand, and the
/// files it matches are shown.
struct ExclusionsEditorView: View {
    /// The paths of the application.
    let paths: [EditorPath]

    /// The exclusion rules.
    @Binding var patterns: [String]

    /// Whether the rules are the XDG ones.
    let isXDG: Bool

    /// The mask written by hand.
    @State private var mask: String = ""

    /// The names of the folders that are expanded.
    @State private var expanded: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if paths.isEmpty {
                Text(L10n.string("editor.exclusions.noPaths"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(paths) { path in
                    if path.url.hasDirectoryPath {
                        folder(path)
                    }
                }
            }

            Divider()

            HStack(spacing: 8) {
                TextField(
                    L10n.string("editor.exclusions.mask.placeholder"),
                    text: $mask
                )
                .textFieldStyle(AppFieldStyle())
                .font(.callout.monospaced())
                .lineLimit(1)

                Button(L10n.string("editor.exclusions.mask.add")) {
                    addMask()
                }
                .disabled(mask.isEmpty)
            }

            if !mask.isEmpty {
                let matcher: GlobMatcher = GlobMatcher(patterns: [mask])
                let files: [String] = paths.flatMap { path in
                    // The masks are relative to the root of the section, the
                    // way the tool matches them.
                    matcher.matchingFiles(in: path.url, relativeTo: root)
                }
                if files.isEmpty {
                    Text(L10n.string("editor.exclusions.mask.none"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(files.prefix(20), id: \.self) { file in
                            Text(file)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        if files.count > 20 {
                            Text(
                                L10n.string("editor.exclusions.mask.more", files.count - 20)
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if !patterns.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.string("editor.exclusions.current"))
                        .font(.subheadline.weight(.semibold))
                    ForEach(patterns, id: \.self) { pattern in
                        HStack(spacing: 8) {
                            Text(pattern)
                                .font(.caption.monospaced())
                            Spacer(minLength: 8)
                            Button {
                                patterns.removeAll { $0 == pattern }
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    /// The root of the files of the section.
    ///
    /// The rules of the exclusions are relative to it, the way the tool
    /// matches them.
    private var root: URL {
        isXDG ? EditorPath.xdgDirectory : EditorPath.homeDirectory
    }

    /// The tree of a folder of the application.
    @ViewBuilder
    private func folder(_ path: EditorPath) -> some View {
        DisclosureGroup(
            isExpanded: Binding(
                get: { expanded.contains(path.path) },
                set: { isExpanded in
                    if isExpanded {
                        expanded.insert(path.path)
                    } else {
                        expanded.remove(path.path)
                    }
                }
            )
        ) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(children(of: path.url), id: \.self) { child in
                    HStack(spacing: 8) {
                        Toggle(
                            "",
                            isOn: Binding(
                                get: { !isExcluded(child, in: path) },
                                set: { isChecked in
                                    if isChecked {
                                        removePattern(of: child, in: path)
                                    } else {
                                        addPattern(of: child, in: path)
                                    }
                                }
                            )
                        )
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.mini)

                        Image(systemName: child.hasDirectoryPath ? "folder" : "doc")
                            .foregroundStyle(.secondary)

                        Text(child.lastPathComponent)
                            .font(.callout)

                        Spacer(minLength: 0)
                    }
                    // The files of the list are on the left of the block.
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.vertical, 8)
            .padding(.leading, 12)
        } label: {
            Button {
                if expanded.contains(path.path) {
                    expanded.remove(path.path)
                } else {
                    expanded.insert(path.path)
                }
            } label: {
                Text(path.path)
                    .font(.callout.monospaced())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    /// The children of a folder.
    private func children(of url: URL) -> [URL] {
        let manager: FileManager = .default
        let contents: [URL] = (try? manager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        return contents.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Whether an item of a folder is excluded.
    private func isExcluded(_ child: URL, in path: EditorPath) -> Bool {
        patterns.contains(pattern(of: child, in: path))
    }

    /// Exclude an item of a folder.
    private func addPattern(of child: URL, in path: EditorPath) {
        let pattern: String = pattern(of: child, in: path)
        guard !patterns.contains(pattern) else { return }
        patterns.append(pattern)
    }

    /// Include an item of a folder again.
    private func removePattern(of child: URL, in path: EditorPath) {
        let pattern: String = pattern(of: child, in: path)
        patterns.removeAll { $0 == pattern }
    }

    /// The rule that excludes an item of a folder.
    ///
    /// The rules are relative to the root of the section, the way the tool
    /// matches them, so the full path of the file is written.
    private func pattern(of child: URL, in path: EditorPath) -> String {
        let relative: String = child.path.replacingOccurrences(
            of: root.path + "/",
            with: ""
        )
        return relative.isEmpty ? child.lastPathComponent : relative
    }

    /// Add the mask that is written by hand.
    private func addMask() {
        let pattern: String = EditorPath.corrected(mask, isXDG: isXDG)
        guard !pattern.isEmpty, !patterns.contains(pattern) else { return }
        patterns.append(pattern)
        mask = ""
    }
}

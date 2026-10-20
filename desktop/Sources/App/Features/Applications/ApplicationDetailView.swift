import SwiftUI

/// The details of an application.
struct ApplicationDetailView: View {
    /// The application.
    let application: MackeepApplication

    /// The model of the list.
    let model: ApplicationsModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                paths
                exclusions
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(application.displayName)
    }

    /// The name and the source of the application.
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(application.displayName)
                .font(.title2.weight(.semibold))
            Text(application.name)
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Label(
                    application.isCustom
                        ? L10n.string("applications.source.custom")
                        : L10n.string("applications.source.builtin"),
                    systemImage: application.isCustom
                        ? "person.crop.circle"
                        : "shippingbox"
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Label(
                    L10n.string("applications.size.label", sizeText),
                    systemImage: "internaldrive"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.top, 4)
        }
    }

    /// The paths of the application.
    private var paths: some View {
        CardView(title: L10n.string("applications.paths.title")) {
            if application.files.isEmpty && application.xdgFiles.isEmpty {
                Text(L10n.string("applications.paths.empty"))
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(application.files) { path in
                        PathRow(path: path)
                    }
                    ForEach(application.xdgFiles) { path in
                        PathRow(path: path, isXDG: true)
                    }
                }
            }
        }
    }

    /// The exclusion rules of the application.
    private var exclusions: some View {
        CardView(title: L10n.string("applications.exclusions.title")) {
            let patterns: [String] = (application.exclude ?? []) + (application.xdgExclude ?? [])
            if patterns.isEmpty {
                Text(L10n.string("applications.exclusions.empty"))
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(patterns, id: \.self) { pattern in
                        Text(pattern)
                            .font(.callout.monospaced())
                    }
                }
            }
        }
    }

    /// The size of the application, in a readable way.
    private var sizeText: String {
        ByteCountFormatter.string(
            fromByteCount: Int64(model.size(of: application)),
            countStyle: .file
        )
    }
}

/// A path of an application.
private struct PathRow: View {
    /// The path.
    let path: MackeepPath

    /// Whether the path is an XDG one.
    var isXDG: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: path.exists
                ? (path.isDir ? "folder" : "doc")
                : "questionmark.folder")
                .foregroundStyle(path.exists ? Color.secondary : Color.orange)

            Text(path.path)
                .font(.callout.monospaced())
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 8)

            if isXDG {
                Text("XDG")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A card of the details of an application.
struct CardView<Content: View>: View {
    /// The title of the card.
    let title: String

    /// The content of the card.
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.quaternary.opacity(0.35))
        )
    }
}

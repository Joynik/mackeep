import SwiftUI

/// The root view of the application, with its three sections.
struct RootView: View {
    @Environment(AppEnvironment.self) private var environment

    /// The section that is shown.
    @State private var selection: SidebarSection? = .applications

    var body: some View {
        NavigationSplitView {
            List(SidebarSection.allCases, selection: $selection) { section in
                Label {
                    Text(section.title)
                } icon: {
                    Image(systemName: section.systemImage)
                }
                .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        } detail: {
            switch selection ?? .applications {
            case .applications:
                applications
            case .backup:
                PlaceholderView(
                    title: "section.backup.title",
                    message: "section.backup.placeholder"
                )
            case .settings:
                PlaceholderView(
                    title: "section.settings.title",
                    message: "section.settings.placeholder"
                )
            }
        }
        .task {
            environment.applications.load()
        }
    }

    /// The list of the applications and their details.
    private var applications: some View {
        HStack(spacing: 0) {
            ApplicationsView(model: environment.applications)
                .frame(minWidth: 360, idealWidth: 460, maxWidth: 560)
            Divider()
            detail
                .frame(minWidth: 320, maxWidth: .infinity)
        }
    }

    /// The details of the selected application.
    @ViewBuilder
    private var detail: some View {
        if let application: MackeepApplication = environment.applications.selectedApplication {
            ApplicationDetailView(
                application: application,
                model: environment.applications
            )
        } else {
            ContentUnavailableView {
                Label {
                    Text(L10n.string("applications.detail.title"))
                } icon: {
                    Image(systemName: "square.grid.2x2")
                }
            } description: {
                Text(L10n.string("applications.detail.placeholder"))
            }
        }
    }
}

/// The sections of the sidebar.
enum SidebarSection: String, CaseIterable, Identifiable {
    case applications
    case backup
    case settings

    var id: String { rawValue }

    /// The title of the section.
    var title: String {
        switch self {
        case .applications: L10n.string("section.applications.title")
        case .backup: L10n.string("section.backup.title")
        case .settings: L10n.string("section.settings.title")
        }
    }

    /// The symbol of the section.
    var systemImage: String {
        switch self {
        case .applications: "square.grid.2x2"
        case .backup: "arrow.triangle.2.circlepath"
        case .settings: "gearshape"
        }
    }
}

/// A view shown while a section is not implemented yet.
struct PlaceholderView: View {
    /// The key of the title of the view.
    let title: String

    /// The key of the message of the view.
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label {
                Text(L10n.string(title))
            } icon: {
                Image(systemName: "wrench.and.screwdriver")
            }
        } description: {
            Text(L10n.string(message))
        }
    }
}

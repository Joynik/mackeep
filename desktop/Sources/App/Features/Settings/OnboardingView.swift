import SwiftUI

/// The wizard of the first launch of the application.
struct OnboardingView: View {
    /// The step of the wizard.
    enum Step: Int, CaseIterable {
        /// Find the tool of the command line.
        case findTool

        /// Choose the storage.
        case storage

        /// Check the applications that are installed.
        case applications

        var title: String {
            switch self {
            case .findTool:
                return L10n.string("onboarding.step.tool")
            case .storage:
                return L10n.string("onboarding.step.storage")
            case .applications:
                return L10n.string("onboarding.step.applications")
            }
        }
    }

    /// The step that is shown.
    @State private var step: Step = .findTool

    /// The model of the settings.
    @Bindable var settings: SettingsModel

    /// The model of the applications.
    @Bindable var applications: ApplicationsModel

    /// The dismissal of the wizard.
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header

            switch step {
            case .findTool:
                findTool
            case .storage:
                storage
            case .applications:
                applicationsStep
            }

            HStack {
                Spacer()
                if step != .findTool {
                    Button(L10n.string("onboarding.back")) {
                        step = Step(rawValue: step.rawValue - 1) ?? .findTool
                    }
                }
                Button(nextTitle) {
                    next()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 560, height: 420)
        .onAppear {
            settings.load()
        }
    }

    /// The title of the button that goes to the next step.
    private var nextTitle: String {
        step == .applications
            ? L10n.string("onboarding.done")
            : L10n.string("onboarding.next")
    }

    /// The header of the wizard.
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.string("onboarding.title"))
                .font(.title2.weight(.semibold))
            Text(step.title)
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }

    /// The step that finds the tool.
    private var findTool: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledContent(L10n.string("settings.tool.path")) {
                Text(settings.mackeepPath.isEmpty ? "—" : settings.mackeepPath)
                    .font(.callout.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            LabeledContent(L10n.string("settings.tool.version")) {
                Text(settings.mackeepVersion.isEmpty ? "—" : settings.mackeepVersion)
                    .font(.callout.monospaced())
            }

            if settings.mackeepPath.isEmpty {
                Label(
                    L10n.string("onboarding.tool.missing"),
                    systemImage: "exclamationmark.triangle"
                )
                .foregroundStyle(.orange)
                Text(L10n.string("onboarding.tool.help"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if settings.isToolKnown, !settings.isToolSupported {
                Label(
                    L10n.string("settings.tool.oldVersion"),
                    systemImage: "exclamationmark.triangle"
                )
                .foregroundStyle(.orange)
                Text(L10n.string("settings.tool.oldVersion.help"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// The step that chooses the storage.
    private var storage: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("", selection: $settings.engine) {
                ForEach(StorageEngine.allCases) { engine in
                    Text(engine.title).tag(engine)
                }
            }
            .labelsHidden()

            Label(
                settings.engine.isAvailable
                    ? L10n.string("settings.storage.yes")
                    : L10n.string("settings.storage.no"),
                systemImage: settings.engine.isAvailable
                    ? "checkmark.circle.fill"
                    : "xmark.circle.fill"
            )
            .foregroundStyle(settings.engine.isAvailable ? .green : .orange)

            Text(settings.backupDirectory)
                .font(.callout.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    /// The step that checks the applications.
    private var applicationsStep: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.string("onboarding.applications.message"))
                .font(.callout)

            List(availableApplications, id: \.name) { application in
                HStack {
                    Text(application.displayName)
                    Spacer()
                    if applications.isInstalled(application) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.tint)
                    }
                }
            }
            .frame(height: 180)
        }
    }

    /// The applications that are installed on this Mac.
    private var availableApplications: [MackeepApplication] {
        applications.applications.filter { applications.isInstalled($0) }
    }

    /// Go to the next step.
    private func next() {
        switch step {
        case .findTool:
            step = .storage
        case .storage:
            settings.save()
            step = .applications
        case .applications:
            dismiss()
        }
    }
}

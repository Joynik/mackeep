import SwiftUI

/// The path policy shared with the command line tool.
struct SecuritySettingsSection: View {
    @Bindable var model: SettingsModel

    var body: some View {
        Section(L10n.string("settings.security.title")) {
            LabeledContent(L10n.string("settings.security.externalPaths")) {
                Toggle("", isOn: $model.allowExternalPaths)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .accessibilityLabel(L10n.string("settings.security.externalPaths"))
                    .disabled(!model.supportsExternalPaths)
                    .onChange(of: model.allowExternalPaths) {
                        model.save()
                    }
            }
            Text(L10n.string("settings.security.externalPaths.help"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

}

/// The command line tool details.
struct ToolSettingsSection: View {
    @Bindable var model: SettingsModel

    var body: some View {
        Section(L10n.string("settings.tool.title")) {
            LabeledContent(L10n.string("settings.tool.path")) {
                Text(model.mackeepPath)
                    .font(.callout.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            LabeledContent(L10n.string("settings.tool.version")) {
                Text(model.mackeepVersion.isEmpty ? "—" : model.mackeepVersion)
                    .font(.callout.monospaced())
            }

            if model.isToolKnown, !model.isToolSupported {
                Label(
                    L10n.string("settings.tool.versionMismatch"),
                    systemImage: "exclamationmark.triangle"
                )
                .foregroundStyle(.orange)
                Text(model.toolCompatibilityMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Link(
                    L10n.string("settings.tool.oldVersion.link"),
                    destination: URL(
                        string: "https://github.com/Joynik/mackeep#installation"
                    )!
                )
                .font(.caption)
            }
        }
    }

}

/// The language and appearance controls.
struct AppearanceSettingsSection: View {
    @Bindable var environment: AppEnvironment

    var body: some View {
        Section(L10n.string("settings.appearance.title")) {
            LabeledContent(L10n.string("settings.appearance.language")) {
                Picker(
                    L10n.string("settings.appearance.language"), selection: $environment.language
                ) {
                    Text(L10n.string("settings.language.system")).tag(AppLanguage.system)
                    Text(L10n.string("settings.language.russian")).tag(AppLanguage.russian)
                    Text(L10n.string("settings.language.english")).tag(AppLanguage.english)
                    Text(L10n.string("settings.language.ukrainian")).tag(AppLanguage.ukrainian)
                    Text(L10n.string("settings.language.spanish")).tag(AppLanguage.spanish)
                    Text(L10n.string("settings.language.german")).tag(AppLanguage.german)
                    Text(L10n.string("settings.language.french")).tag(AppLanguage.french)
                    Text(L10n.string("settings.language.italian")).tag(AppLanguage.italian)
                    Text(L10n.string("settings.language.portuguese")).tag(AppLanguage.portuguese)
                    Text(L10n.string("settings.language.japanese")).tag(AppLanguage.japanese)
                    Text(L10n.string("settings.language.korean")).tag(AppLanguage.korean)
                    Text(L10n.string("settings.language.chinese")).tag(AppLanguage.chinese)
                }
                .labelsHidden()
            }

            LabeledContent(L10n.string("settings.appearance.theme")) {
                let themeTitle = L10n.string("settings.appearance.theme")
                Picker(themeTitle, selection: $environment.appearance) {
                    Text(L10n.string("settings.theme.system")).tag(AppAppearance.system)
                    Text(L10n.string("settings.theme.light")).tag(AppAppearance.light)
                    Text(L10n.string("settings.theme.dark")).tag(AppAppearance.dark)
                }
                .labelsHidden()
            }
        }
    }

}

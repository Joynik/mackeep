import SwiftUI
import AppKit

/// The settings of Mackeep.
struct SettingsView: View {
    /// The model of the settings.
    @Bindable var model: SettingsModel

    /// The environment of the view.
    @Environment(AppEnvironment.self) private var environment

    /// The rule of the global exclusions that is written.
    @State private var newExclude: String = ""

    /// The field that has the focus, the settings are written when it
    /// leaves it.
    @FocusState private var focusedField: Field?

    /// The fields that hold a value that is written.
    private enum Field: Hashable {
        case storagePath
        case directory
    }

    /// The same inset on both sides of every settings row.
    private let rowInsets = EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12)

    var body: some View {
        Form {
            appearance
                .listRowInsets(rowInsets)
            locations
                .listRowInsets(rowInsets)
            tool
                .listRowInsets(rowInsets)
            storage
                .listRowInsets(rowInsets)
            exclusions
                .listRowInsets(rowInsets)
            security
                .listRowInsets(rowInsets)
        }
        .formStyle(.grouped)
        .labeledContentStyle(CenteredSettingsRowStyle())
        .navigationTitle(L10n.string("section.settings.title"))
        .appError($model.presentedError)
        // The controls of the window have the same height, so they line up.
        .appControlSize()
        .disabled(model.isLoading)
        .overlay(alignment: .topTrailing) {
            if model.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .padding(12)
            }
        }
        .onAppear {
            // The settings are read when the section is shown for the
            // first time, the window does not wait for them.
            model.load()
        }
        .onChange(of: focusedField) { _, _ in
            // The value of a field is written when it loses the focus, the
            // user does not have to press Enter.
            model.save()
        }
    }

    /// The path policy shared with the command line tool.
    private var security: some View {
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

    /// The storage of Mackeep.
    private var storage: some View {
        Section(L10n.string("settings.storage.title")) {
            Picker("", selection: $model.engine) {
                ForEach(StorageEngine.allCases) { engine in
                    Text(engine.title).tag(engine)
                }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .trailing)
            .onChange(of: model.engine) {
                model.save()
            }

            LabeledContent(L10n.string("settings.storage.available")) {
                Label(
                    model.engine.isAvailable
                        ? L10n.string("settings.storage.yes")
                        : L10n.string("settings.storage.no"),
                    systemImage: model.engine.isAvailable
                        ? "checkmark.circle.fill"
                        : "xmark.circle.fill"
                )
                .foregroundStyle(model.engine.isAvailable ? .green : .orange)
            }

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                if model.engine == .fileSystem {
                    GridRow(alignment: .center) {
                        storageFieldLabel("settings.storage.path")
                        HStack {
                            TextField("", text: $model.storagePath)
                                .textFieldStyle(AppFieldStyle())
                                .multilineTextAlignment(.leading)
                                .accessibilityLabel(L10n.string("settings.storage.path"))
                                .focused($focusedField, equals: .storagePath)
                                .onSubmit {
                                    model.save()
                                }
                            Button {
                                chooseFolder()
                            } label: {
                                Image(systemName: "folder")
                            }
                            .help(L10n.string("settings.storage.choose"))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Divider()
                        .gridCellUnsizedAxes(.horizontal)
                }

                GridRow(alignment: .center) {
                    storageFieldLabel("settings.storage.directory")
                    TextField("", text: $model.directory)
                        .textFieldStyle(AppFieldStyle())
                        .multilineTextAlignment(.leading)
                        .accessibilityLabel(L10n.string("settings.storage.directory"))
                        .focused($focusedField, equals: .directory)
                        .onSubmit {
                            model.save()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            LabeledContent(L10n.string("settings.storage.resolved")) {
                Text(model.backupDirectory)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    /// Size the field labels using every translated label in the storage section.
    private func storageFieldLabel(_ key: String) -> some View {
        ZStack(alignment: .leading) {
            ForEach([
                "settings.storage.available",
                "settings.storage.path",
                "settings.storage.directory",
                "settings.storage.resolved",
            ], id: \.self) { label in
                Text(L10n.string(label))
                    .hidden()
                    .accessibilityHidden(true)
            }
            Text(L10n.string(key))
        }
    }

    /// The global exclusion rules.
    private var exclusions: some View {
        Section(L10n.string("settings.exclusions.title")) {
            ForEach(model.configErrors, id: \.self) { error in
                Label {
                    Text(error)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .foregroundStyle(.orange)
            }

            HStack {
                TextField(
                    L10n.string("settings.exclusions.placeholder"),
                    text: $newExclude
                )
                .textFieldStyle(AppFieldStyle())
                .font(.callout.monospaced())

                Button {
                    model.addGlobalExclude(newExclude)
                    newExclude = ""
                    model.save()
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(newExclude.isEmpty)
                .help(L10n.string("settings.exclusions.add"))
            }

            if model.globalExclude.isEmpty {
                Text(L10n.string("settings.exclusions.empty"))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.globalExclude, id: \.self) { pattern in
                    HStack {
                        Text(pattern)
                            .font(.callout.monospaced())
                        Spacer(minLength: 8)
                        Button {
                            model.removeGlobalExclude(pattern)
                            model.save()
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                    .frame(minHeight: AppControl.height, alignment: .center)
                    .listRowInsets(rowInsets)
                }
            }
        }
    }

    /// Where the files of Mackeep are.
    private var locations: some View {
        Section(L10n.string("settings.locations.title")) {
            LabeledContent(L10n.string("settings.locations.config")) {
                HStack {
                    Spacer(minLength: 8)
                    Text(model.configFilePath)
                        .font(.callout.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button {
                        reveal(model.configFilePath)
                    } label: {
                        Image(systemName: "folder")
                    }
                    .help(L10n.string("settings.locations.reveal"))
                    .disabled(model.configFilePath.isEmpty)
                }
            }

            LabeledContent(L10n.string("settings.locations.apps")) {
                HStack {
                    Spacer(minLength: 8)
                    Text(model.customAppsDir)
                        .font(.callout.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .accessibilityIdentifier("settings.customAppsDir")
                    Button {
                        reveal(model.customAppsDir)
                    } label: {
                        Image(systemName: "folder")
                    }
                    .help(L10n.string("settings.locations.reveal"))
                    .disabled(model.customAppsDir.isEmpty)
                }
            }
        }
    }

    /// The tool of the command line.
    private var tool: some View {
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
                    L10n.string("settings.tool.oldVersion"),
                    systemImage: "exclamationmark.triangle"
                )
                .foregroundStyle(.orange)
                Text(L10n.string("settings.tool.oldVersion.help"))
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

    /// The language and the appearance of the application.
    private var appearance: some View {
        @Bindable var environment: AppEnvironment = environment

        return Section(L10n.string("settings.appearance.title")) {
            LabeledContent(L10n.string("settings.appearance.language")) {
                Picker(L10n.string("settings.appearance.language"), selection: $environment.language) {
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
                Picker(L10n.string("settings.appearance.theme"), selection: $environment.appearance) {
                    Text(L10n.string("settings.theme.system")).tag(AppAppearance.system)
                    Text(L10n.string("settings.theme.light")).tag(AppAppearance.light)
                    Text(L10n.string("settings.theme.dark")).tag(AppAppearance.dark)
                }
                .labelsHidden()
            }
        }
    }

    /// Choose the folder of the storage.
    private func chooseFolder() {
        let panel: NSOpenPanel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: EditorPath.homeDirectory.path)
        if panel.runModal() == .OK, let url: URL = panel.url {
            model.storagePath = url.path
            model.save()
        }
    }

    /// Show a path in the Finder.
    private func reveal(_ path: String) {
        guard !path.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }
}

/// Keep labels and controls centered even when their heights differ.
private struct CenteredSettingsRowStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .center) {
            configuration.label
            Spacer(minLength: 16)
            configuration.content
                .foregroundStyle(.secondary)
        }
    }
}

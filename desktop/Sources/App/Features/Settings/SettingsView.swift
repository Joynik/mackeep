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

    var body: some View {
        Form {
            appearance
            locations
            tool
            storage
            exclusions
        }
        .formStyle(.grouped)
        .navigationTitle(L10n.string("section.settings.title"))
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

    /// The storage of Mackeep.
    private var storage: some View {
        Section(L10n.string("settings.storage.title")) {
            Picker("", selection: $model.engine) {
                ForEach(StorageEngine.allCases) { engine in
                    Text(engine.title).tag(engine)
                }
            }
            .labelsHidden()
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

            if model.engine == .fileSystem {
                LabeledContent(L10n.string("settings.storage.path")) {
                    HStack {
                        TextField("", text: $model.storagePath)
                            .textFieldStyle(AppFieldStyle())
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
                }
            }

            LabeledContent(L10n.string("settings.storage.directory")) {
                TextField("", text: $model.directory)
                    .textFieldStyle(AppFieldStyle())
                    .focused($focusedField, equals: .directory)
                    .onSubmit {
                        model.save()
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
                }
            }
        }
    }

    /// Where the files of Mackeep are.
    private var locations: some View {
        Section(L10n.string("settings.locations.title")) {
            LabeledContent(L10n.string("settings.locations.config")) {
                HStack {
                    Text(model.configFilePath)
                        .font(.callout.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
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
                    Text(model.customAppsDir)
                        .font(.callout.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .accessibilityIdentifier("settings.customAppsDir")
                    Spacer(minLength: 8)
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
            Picker(
                L10n.string("settings.appearance.language"),
                selection: $environment.language
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

            Picker(
                L10n.string("settings.appearance.theme"),
                selection: $environment.appearance
            ) {
                Text(L10n.string("settings.theme.system")).tag(AppAppearance.system)
                Text(L10n.string("settings.theme.light")).tag(AppAppearance.light)
                Text(L10n.string("settings.theme.dark")).tag(AppAppearance.dark)
            }
        }
    }

    /// Choose the folder of the storage.
    private func chooseFolder() {
        let panel: NSOpenPanel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory())
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

import Foundation

/// The model of the settings of Mackeep.
@Observable
@MainActor
final class SettingsModel {
    /// The engine of the storage.
    var engine: StorageEngine = .dropbox

    /// The path of the storage, for the file system engine.
    var storagePath: String = ""

    /// The name of the folder of the backup inside the storage.
    var directory: String = "Mackeep"

    /// The global exclusion rules.
    var globalExclude: [String] = []

    /// The path of the config file of Mackeep.
    private(set) var configFilePath: String = ""

    /// The directory where the custom application configs are read.
    private(set) var customAppsDir: String = ""

    /// The folder where the backup is written, as the tool of Mackeep sees it.
    private(set) var resolvedBackupDirectory: String = ""

    /// The path of the binary of Mackeep.
    private(set) var mackeepPath: String = ""

    /// The version of the binary of Mackeep.
    ///
    /// It is known when the capabilities of the tool are read, they arrive
    /// after the start of the application.
    var mackeepVersion: String { capabilities?.version ?? "" }

    /// What the binary of Mackeep can do.
    var capabilities: MackeepCapabilities?

    /// The error shown to the user, when there is one.
    var presentedError: AppError?

    /// Whether the settings are being read.
    private(set) var isLoading: Bool = false

    /// Whether the settings were already read.
    private var hasLoaded: Bool = false

    /// The main config file of Mackeep.
    private var mainConfig: MainConfig?

    /// The command line tool of Mackeep.
    private let command: MackeepCommand?

    init(command: MackeepCommand?, capabilities: MackeepCapabilities?) {
        self.command = command
        self.capabilities = capabilities
        self.mackeepPath = command?.path ?? ""
    }

    /// Whether the binary of Mackeep is recent enough.
    var isToolSupported: Bool { capabilities?.isSupported ?? false }

    /// Whether the capabilities of the binary of Mackeep are known.
    ///
    /// The warning about an old version is only shown when the version of
    /// the binary is known.
    var isToolKnown: Bool { capabilities != nil }

    /// The folder where the backup is written.
    ///
    /// The tool of Mackeep knows the real path of the storage, it is used
    /// when it is known. Otherwise the folder is counted by the settings.
    var backupDirectory: String {
        if !resolvedBackupDirectory.isEmpty {
            return resolvedBackupDirectory
        }

        let base: String
        switch engine {
        case .fileSystem:
            base = storagePath.isEmpty ? NSHomeDirectory() : storagePath
        default:
            base = engine.standardPath ?? NSHomeDirectory()
        }

        return (base as NSString).appendingPathComponent(directory)
    }

    /// Read the configuration of Mackeep.
    ///
    /// The work is done out of the main thread, so the window stays alive.
    /// The settings are only read once, the view asks for them when it is
    /// shown for the first time.
    func load() {
        guard let command, !hasLoaded else { return }

        hasLoaded = true
        isLoading = true

        Task { [weak self] in
            let result: LoadResult = await Task.detached(priority: .userInitiated) {
                Self.load(with: command)
            }.value
            self?.apply(result)
        }
    }

    /// What is read from Mackeep.
    private struct LoadResult: Sendable {
        /// The configuration of Mackeep.
        let config: MackeepConfig?

        /// The content of the config file Mackeep uses.
        let document: INIDocument?

        /// The path of the config file Mackeep uses.
        let configURL: URL?

        /// The message of the error, when there is one.
        let errorMessage: String?
    }

    /// Read the configuration of Mackeep.
    ///
    /// - Parameter command: The command line tool of Mackeep.
    /// - Returns: What was read.
    nonisolated private static func load(with command: MackeepCommand) -> LoadResult {
        do {
            let config: MackeepConfig = try command.runJSON(
                ["--json", "config"],
                as: MackeepConfig.self
            )
            let url: URL = URL(fileURLWithPath: config.configFile)
            // The config file is created when it does not exist, the
            // settings are shown anyway when it cannot be read
            let document: INIDocument? = try? MainConfig.createIfNeeded(at: url)
                .document
            return LoadResult(
                config: config,
                document: document,
                configURL: url,
                errorMessage: nil
            )
        } catch {
            return LoadResult(
                config: nil,
                document: nil,
                configURL: nil,
                errorMessage: "\(error)"
            )
        }
    }

    /// Take what was read from Mackeep.
    ///
    /// - Parameter result: What was read.
    private func apply(_ result: LoadResult) {
        isLoading = false

        if let message: String = result.errorMessage {
            presentedError = AppError(
                title: L10n.string("error.load.title"),
                message: message
            )
            return
        }

        guard
            let config: MackeepConfig = result.config,
            let url: URL = result.configURL
        else {
            return
        }

        configFilePath = config.configFile
        customAppsDir = config.customAppsDir ?? config.customAppsDirs.first ?? ""
        globalExclude = config.globalExclude
        resolvedBackupDirectory = config.storage.resolvedBackupDir

        let raw: String = config.storage.engine
        if let engine: StorageEngine = StorageEngine(rawValue: raw) {
            self.engine = engine
        }
        directory = config.storage.directory

        if engine == .fileSystem {
            storagePath = config.storage.path
        }
        if let document: INIDocument = result.document {
            mainConfig = MainConfig(url: url, document: document)
        }
    }

    /// Write the settings in the config file of Mackeep.
    func save() {
        guard let mainConfig else { return }

        mainConfig.setStorage(
            engine: engine.rawValue,
            path: engine == .fileSystem ? storagePath : nil,
            directory: directory
        )
        mainConfig.setGlobalExclude(globalExclude)

        do {
            try mainConfig.save()
        } catch {
            presentedError = AppError(
                title: L10n.string("error.save.title"),
                message: "\(error)"
            )
        }
    }

    /// Add a global exclusion rule.
    ///
    /// - Parameter pattern: The rule.
    func addGlobalExclude(_ pattern: String) {
        let rule: String = pattern.trimmingCharacters(in: .whitespaces)
        guard !rule.isEmpty, !globalExclude.contains(rule) else { return }
        globalExclude.append(rule)
    }

    /// Remove a global exclusion rule.
    ///
    /// - Parameter pattern: The rule.
    func removeGlobalExclude(_ pattern: String) {
        globalExclude.removeAll { $0 == pattern }
    }
}

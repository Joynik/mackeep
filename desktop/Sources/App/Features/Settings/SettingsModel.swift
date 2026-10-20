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

    /// The directories where the custom application configs are read.
    private(set) var customAppsDirs: [String] = []

    /// The folder where the backup is written, as the tool of Mackeep sees it.
    private(set) var resolvedBackupDirectory: String = ""

    /// The path of the binary of Mackeep.
    private(set) var mackeepPath: String = ""

    /// The version of the binary of Mackeep.
    private(set) var mackeepVersion: String = ""

    /// What the binary of Mackeep can do.
    var capabilities: MackeepCapabilities?

    /// The error shown to the user, when there is one.
    var presentedError: AppError?

    /// The main config file of Mackeep.
    private var mainConfig: MainConfig?

    /// The command line tool of Mackeep.
    private let command: MackeepCommand?

    init(command: MackeepCommand?, capabilities: MackeepCapabilities?) {
        self.command = command
        self.capabilities = capabilities
        self.mackeepPath = command?.path ?? ""
        self.mackeepVersion = capabilities?.version ?? ""
    }

    /// Whether the binary of Mackeep is recent enough.
    var isToolSupported: Bool { capabilities?.isSupported ?? false }

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
    func load() {
        guard let command else { return }

        do {
            let config: MackeepConfig = try command.runJSON(
                ["--json", "config"],
                as: MackeepConfig.self
            )
            configFilePath = config.configFile
            customAppsDirs = config.customAppsDirs
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
            mainConfig = try MainConfig.load(
                from: URL(fileURLWithPath: config.configFile)
            )
        } catch {
            presentedError = AppError(
                title: L10n.string("error.load.title"),
                message: "\(error)"
            )
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

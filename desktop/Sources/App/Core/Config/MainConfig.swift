import Foundation

/// The main config file of Mackeep.
///
/// The file is the one Mackeep uses, it is given by `mackeep --json config`.
/// The applications to sync and the ones to ignore are written in it.
final class MainConfig {
    /// Serialize writes from settings and background application selection saves.
    private static let writeLock = NSLock()
    private var listUpdates: [String: [String]] = [:]
    private var valueUpdates: [String: [String: String]] = [:]

    /// The path of the config file.
    let url: URL

    /// The content of the config file.
    private(set) var document: INIDocument

    /// Create the config.
    ///
    /// - Parameters:
    ///   - url: The path of the config file.
    ///   - document: The content of the file.
    init(url: URL, document: INIDocument) {
        self.url = url
        self.document = document
    }

    /// Read the config file.
    ///
    /// - Parameter url: The path of the config file.
    /// - Returns: The config.
    static func load(from url: URL) throws -> MainConfig {
        let document: INIDocument = try INIFile.load(
            from: url,
            stripsInlineComments: true
        )
        return MainConfig(url: url, document: document)
    }

    /// Create the config file, when it does not exist.
    ///
    /// The file is created with the default backup folder, the same way the
    /// command line version does it.
    ///
    /// - Parameter url: The path of the config file.
    /// - Returns: The config.
    static func createIfNeeded(at url: URL) throws -> MainConfig {
        if !FileManager.default.fileExists(atPath: url.path) {
            let document: INIDocument = INIDocument(text: """
            # The configuration of Mackeep.
            # See https://github.com/Joynik/mackeep/blob/master/doc/README.md

            [storage]
            engine = unconfigured
            directory = Mackeep

            """)
            try INIFile.save(document, to: url, backup: false)
        }

        return try load(from: url)
    }

    /// The names of the applications to sync.
    var appsToSync: [String] {
        document.optionKeys(inSection: "applications_to_sync")
    }

    /// The names of the applications to ignore.
    var appsToIgnore: [String] {
        document.optionKeys(inSection: "applications_to_ignore")
    }

    /// Whether definitions may refer to files outside HOME.
    var allowExternalPaths: Bool {
        ["true", "yes", "1", "on"].contains(
            document.value(forKey: "allow_external_paths", inSection: "security")?.lowercased() ?? "false"
        )
    }

    /// Store the shared CLI and desktop path policy.
    func setAllowExternalPaths(_ allowed: Bool) {
        let value = allowed ? "true" : "false"
        document.setValue(value, forKey: "allow_external_paths", inSection: "security")
        valueUpdates["security", default: [:]]["allow_external_paths"] = value
    }

    /// The global exclusion rules.
    var globalExclude: [String] {
        document.values(inSection: "exclude")
    }

    /// The engine of the storage.
    var storageEngine: String? {
        document.value(forKey: "engine", inSection: "storage")
    }

    /// The path of the storage.
    var storagePath: String? {
        document.value(forKey: "path", inSection: "storage")
    }

    /// The name of the directory of the backup inside the storage.
    var storageDirectory: String? {
        document.value(forKey: "directory", inSection: "storage")
    }

    /// Set the applications that are used for the backup, and the ones that
    /// are not.
    ///
    /// The two lists are written: the applications to sync are the ones that
    /// are checked, the applications to ignore are the ones of the list that
    /// are not. The applications that are not in the list at all are not
    /// backed up either, the list of the applications to sync is the one
    /// that tells what is backed up.
    ///
    /// - Parameters:
    ///   - synced: The names of the applications to sync.
    ///   - ignored: The names of the applications to ignore.
    func setSyncedApplications(_ synced: [String], ignored: [String]) {
        document.setOptionKeys(synced.sorted(), inSection: "applications_to_sync")
        document.setOptionKeys(ignored.sorted(), inSection: "applications_to_ignore")
        listUpdates["applications_to_sync"] = synced.sorted()
        listUpdates["applications_to_ignore"] = ignored.sorted()
    }

    /// Set the storage of Mackeep.
    ///
    /// - Parameters:
    ///   - engine: The engine of the storage.
    ///   - path: The path of the storage, for the file system engine.
    ///   - directory: The name of the folder of the backup.
    func setStorage(engine: String, path: String?, directory: String?) {
        document.setValue(engine, forKey: "engine", inSection: "storage")
        valueUpdates["storage", default: [:]]["engine"] = engine
        if let path {
            document.setValue(path, forKey: "path", inSection: "storage")
            valueUpdates["storage", default: [:]]["path"] = path
        }
        if let directory {
            document.setValue(directory, forKey: "directory", inSection: "storage")
            valueUpdates["storage", default: [:]]["directory"] = directory
        }
    }

    /// Set the global exclusion rules.
    ///
    /// - Parameter patterns: The patterns.
    func setGlobalExclude(_ patterns: [String]) {
        document.setOptionKeys(patterns, inSection: "exclude")
        listUpdates["exclude"] = patterns
    }

    /// Write the config file.
    ///
    /// The file is written atomically, and the previous version is kept.
    func save() throws {
        Self.writeLock.lock()
        defer { Self.writeLock.unlock() }
        var latest = FileManager.default.fileExists(atPath: url.path)
            ? try INIFile.load(from: url, stripsInlineComments: true)
            : document
        for section in listUpdates.keys.sorted() {
            latest.setOptionKeys(listUpdates[section]!, inSection: section)
        }
        for section in valueUpdates.keys.sorted() {
            for key in valueUpdates[section]!.keys.sorted() {
                latest.setValue(valueUpdates[section]![key]!, forKey: key, inSection: section)
            }
        }
        try INIFile.save(latest, to: url)
        document = latest
        listUpdates.removeAll()
        valueUpdates.removeAll()
    }
}

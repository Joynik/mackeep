import Foundation

/// The main config file of Mackeep.
///
/// The file is the one Mackeep uses, it is given by `mackeep --json config`.
/// The applications to sync and the ones to ignore are written in it.
final class MainConfig {
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
            directory = Mackeep

            """)
            try INIFile.save(document, to: url, backup: false)
        }

        return try load(from: url)
    }

    /// The names of the applications to sync.
    var appsToSync: [String] {
        document.values(inSection: "applications_to_sync")
    }

    /// The names of the applications to ignore.
    var appsToIgnore: [String] {
        document.values(inSection: "applications_to_ignore")
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

    /// Set the applications that are synced.
    ///
    /// The two modes of Mackeep are used one at a time: either the
    /// applications to sync are written, or the ones to ignore. The other
    /// list is cleared, so the file always means one thing.
    ///
    /// - Parameters:
    ///   - names: The names of the applications.
    ///   - mode: The mode of the selection.
    func setSyncedApplications(_ names: [String], mode: SyncMode) {
        switch mode {
        case .allExceptUnchecked:
            document.setOptionKeys(names.sorted(), inSection: "applications_to_ignore")
            document.setOptionKeys([], inSection: "applications_to_sync")
        case .onlyChecked:
            document.setOptionKeys(names.sorted(), inSection: "applications_to_sync")
            document.setOptionKeys([], inSection: "applications_to_ignore")
        }
    }

    /// Set the storage of Mackeep.
    ///
    /// - Parameters:
    ///   - engine: The engine of the storage.
    ///   - path: The path of the storage, for the file system engine.
    ///   - directory: The name of the folder of the backup.
    func setStorage(engine: String, path: String?, directory: String?) {
        document.setValue(engine, forKey: "engine", inSection: "storage")
        if let path {
            document.setValue(path, forKey: "path", inSection: "storage")
        }
        if let directory {
            document.setValue(directory, forKey: "directory", inSection: "storage")
        }
    }

    /// Set the global exclusion rules.
    ///
    /// - Parameter patterns: The patterns.
    func setGlobalExclude(_ patterns: [String]) {
        document.setOptionKeys(patterns, inSection: "exclude")
    }

    /// Write the config file.
    ///
    /// The file is written atomically, and the previous version is kept.
    func save() throws {
        try INIFile.save(document, to: url)
    }
}

/// The way the applications are selected.
enum SyncMode: String, CaseIterable, Identifiable {
    /// Everything is synced, except the applications that are not checked.
    case allExceptUnchecked

    /// Only the applications that are checked are synced.
    case onlyChecked

    var id: String { rawValue }
}

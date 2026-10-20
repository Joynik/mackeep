import Foundation

/// The finder of the command line tool of Mackeep.
enum MackeepDiscovery {
    /// The names of the binary.
    static let binaryNames: [String] = ["mackeep-cli", "mackeep"]

    /// The directories where the binary is looked for.
    static let directories: [String] = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin",
        "/bin",
    ]

    /// Find the binary of Mackeep.
    ///
    /// - Parameters:
    ///   - manualPath: The path of the binary, when the user set one.
    ///   - fileManager: The file manager.
    /// - Returns: The path of the binary, nil when it is not found.
    static func find(
        manualPath: String? = nil,
        fileManager: FileManager = .default
    ) -> String? {
        if let manualPath, !manualPath.isEmpty,
           isExecutable(manualPath, fileManager: fileManager)
        {
            return manualPath
        }

        for directory in directories {
            for name in binaryNames {
                let path: String = directory + "/" + name
                if isExecutable(path, fileManager: fileManager) { return path }
            }
        }
        return nil
    }

    /// Whether a path is an executable file.
    ///
    /// - Parameters:
    ///   - path: The path of the file.
    ///   - fileManager: The file manager.
    /// - Returns: True when the file can be run.
    static func isExecutable(_ path: String, fileManager: FileManager = .default) -> Bool {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else {
            return false
        }
        guard !isDirectory.boolValue else { return false }
        return fileManager.isExecutableFile(atPath: path)
    }
}

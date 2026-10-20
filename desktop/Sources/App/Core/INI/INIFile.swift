import Foundation

/// An INI file of Mackeep.
enum INIFile {
    /// The error of a file operation.
    enum FileError: LocalizedError {
        /// The file cannot be read.
        case cannotRead(URL, Error)

        /// The file cannot be written.
        case cannotWrite(URL, Error)

        public var errorDescription: String? {
            switch self {
            case let .cannotRead(url, error):
                "Cannot read \(url.path): \(error.localizedDescription)"
            case let .cannotWrite(url, error):
                "Cannot write \(url.path): \(error.localizedDescription)"
            }
        }
    }

    /// Read a file.
    ///
    /// - Parameters:
    ///   - url: The path of the file.
    ///   - stripsInlineComments: Whether the inline comments are stripped
    ///     from the values, the way the main config file of Mackeep does.
    /// - Returns: The document of the file.
    static func load(
        from url: URL,
        stripsInlineComments: Bool = false
    ) throws -> INIDocument {
        do {
            let text: String = try String(contentsOf: url, encoding: .utf8)
            return INIDocument(text: text, stripsInlineComments: stripsInlineComments)
        } catch {
            throw FileError.cannotRead(url, error)
        }
    }

    /// Write a file, atomically.
    ///
    /// The previous version of the file is kept in a file with the `.bak`
    /// extension.
    ///
    /// - Parameters:
    ///   - document: The document to write.
    ///   - url: The path of the file.
    ///   - backup: Whether the previous version is kept.
    static func save(
        _ document: INIDocument,
        to url: URL,
        backup: Bool = true
    ) throws {
        let manager: FileManager = .default
        let directory: URL = url.deletingLastPathComponent()

        do {
            if backup, manager.fileExists(atPath: url.path) {
                let backupURL: URL = url.appendingPathExtension("bak")
                if manager.fileExists(atPath: backupURL.path) {
                    try manager.removeItem(at: backupURL)
                }
                try manager.copyItem(at: url, to: backupURL)
            }

            if !manager.fileExists(atPath: directory.path) {
                try manager.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true
                )
            }

            // The file is written next to the final one, and moved in place
            let temporary: URL = directory.appendingPathComponent(
                ".\(url.lastPathComponent).\(UUID().uuidString).tmp"
            )
            try document.text.write(
                to: temporary,
                atomically: true,
                encoding: .utf8
            )
            if manager.fileExists(atPath: url.path) {
                _ = try manager.replaceItemAt(url, withItemAt: temporary)
            } else {
                try manager.moveItem(at: temporary, to: url)
            }
        } catch {
            throw FileError.cannotWrite(url, error)
        }
    }
}

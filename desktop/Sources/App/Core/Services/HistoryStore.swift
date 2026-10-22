import Darwin
import Foundation

/// A run of Mackeep, as it is kept in the history.
struct RunRecord: Codable, Equatable, Identifiable {
    /// The identifier of the run.
    let id: UUID

    /// When the run was started.
    let date: Date

    /// The command that was run: backup or restore.
    let command: String

    /// The application the run was about, when there is one.
    let application: String?

    /// Whether the run was fine.
    let succeeded: Bool

    /// The number of files that were copied.
    let files: Int

    /// The number of bytes that were copied.
    let bytes: Int

    /// The message of the error, when there is one.
    let message: String?

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        command: String,
        application: String? = nil,
        succeeded: Bool,
        files: Int = 0,
        bytes: Int = 0,
        message: String? = nil
    ) {
        self.id = id
        self.date = date
        self.command = command
        self.application = application
        self.succeeded = succeeded
        self.files = files
        self.bytes = bytes
        self.message = message
    }
}

/// The history of the runs of Mackeep.
///
/// The history is a JSON file in the application support folder.
@MainActor
final class HistoryStore {
    /// The name of the file of the history.
    static let fileName: String = "history.json"

    /// The maximum number of runs that are kept.
    static let maximumRuns: Int = 50

    /// The path of the file of the history.
    let url: URL

    /// The file manager.
    private let fileManager: FileManager

    init(fileManager: FileManager = .default, url: URL? = nil) {
        self.fileManager = fileManager
        if let url {
            self.url = url
            return
        }
        if EditorPath.isTesting {
            self.url = EditorPath.homeDirectory.appendingPathComponent("history.json")
            return
        }
        let support: URL = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSHomeDirectory())
        let directory: URL = support.appendingPathComponent("Mackeep")
        self.url = directory.appendingPathComponent(HistoryStore.fileName)
    }

    /// The decoder of the history.
    private static let decoder: JSONDecoder = {
        let decoder: JSONDecoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    /// The encoder of the history.
    private static let encoder: JSONEncoder = {
        let encoder: JSONEncoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    /// Read the history.
    ///
    /// - Returns: The runs, the most recent first.
    func load() throws -> [RunRecord] {
        do {
            try validateFile()
            let data = try Data(contentsOf: url)
            return try Self.decoder.decode([RunRecord].self, from: data)
                .sorted { $0.date > $1.date }
        } catch let error as CocoaError where
            error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return []
        }
    }

    /// Preserve malformed history before starting a new history file.
    @discardableResult
    func append(_ record: RunRecord) throws -> URL? {
        var records: [RunRecord]
        var recovery: URL?
        do {
            records = try load()
        } catch is DecodingError {
            var backup = url.appendingPathExtension("bak")
            if fileManager.fileExists(atPath: backup.path) {
                backup = url.appendingPathExtension("\(UUID().uuidString).bak")
            }
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            try fileManager.moveItem(at: url, to: backup)
            recovery = backup
            records = []
        }
        records.append(record)
        let newest = Array(records.sorted { $0.date > $1.date }.prefix(Self.maximumRuns))
        let data = try Self.encoder.encode(newest)
        let parent = url.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: parent, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        let staging = parent.appendingPathComponent(".history-\(UUID().uuidString)")
        try fileManager.createDirectory(
            at: staging, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700])
        defer { try? fileManager.removeItem(at: staging) }
        let file = staging.appendingPathComponent("history.json")
        try data.write(to: file)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        guard Darwin.rename(file.path, url.path) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        return recovery
    }

    private func validateFile() throws {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }
    }

    /// Remove the history.
    func clear() throws {
        if fileManager.fileExists(atPath: url.path) {
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            guard attributes[.type] as? FileAttributeType != .typeDirectory else {
                throw CocoaError(.fileWriteInvalidFileName)
            }
            try fileManager.removeItem(at: url)
        }
    }
}

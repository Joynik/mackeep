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
    func load() -> [RunRecord] {
        guard
            let data: Data = try? Data(contentsOf: url),
            let records: [RunRecord] = try? HistoryStore.decoder.decode(
                [RunRecord].self,
                from: data
            )
        else {
            return []
        }
        return records.sorted { $0.date > $1.date }
    }

    /// Write a run in the history.
    ///
    /// - Parameter record: The run.
    func append(_ record: RunRecord) {
        var records: [RunRecord] = load()
        records.append(record)
        records = records
            .sorted { $0.date > $1.date }
            .prefix(HistoryStore.maximumRuns)
            .map { $0 }

        guard let data: Data = try? HistoryStore.encoder.encode(records) else {
            return
        }

        try? fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: url, options: .atomic)
    }

    /// Remove the history.
    func clear() {
        try? fileManager.removeItem(at: url)
    }
}

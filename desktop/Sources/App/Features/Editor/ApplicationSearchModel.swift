import Foundation

/// A file or a folder that was found for an application.
struct FoundFile: Identifiable, Equatable, Sendable {
    /// The absolute path of the file.
    let url: URL

    /// The path of the file, relative to the home or to the XDG config home.
    let relativePath: String

    /// Whether the file is in the XDG config directory.
    let isXDG: Bool

    /// Whether the file is a folder.
    let isDirectory: Bool

    /// The size of the file, in bytes.
    let size: Int

    /// The identifier of the file.
    var id: String { "\(isXDG ? "xdg:" : "home:")\(relativePath)" }

    /// The size of the file, in a readable way.
    var sizeText: String {
        guard !isDirectory else { return "" }
        return ByteCountFormatter.string(
            fromByteCount: Int64(size),
            countStyle: .file
        )
    }
}

/// The model of the search of the files of an application.
///
/// The typed query selects matching files in configured folders, standard
/// macOS locations, and Spotlight. Results can be added to any configuration.
@Observable
@MainActor
final class ApplicationSearchModel {
    /// The maximum number of results.
    nonisolated static let maximumResults: Int = 300

    /// The maximum number of levels that are searched.
    nonisolated static let maximumDepth: Int = 4

    /// The text of the search.
    var searchText: String = "" {
        didSet { scheduleSearch() }
    }

    /// The files that were found.
    var results: [FoundFile] = []

    /// Whether the search is running.
    var isSearching: Bool = false

    /// The folders that are searched.
    var roots: [URL] = []

    /// The files that are searched.
    var rootFiles: [URL] = []

    /// The paths that are already in the application.
    var knownPaths: Set<String> = []

    /// The task of the search that is running.
    var task: Task<Void, Never>?
    var cancellation: CommandCancellation?
    var cachedIdentifiers: [String]?
    var cachedSearchText: String?
    var active = false
    let query: @Sendable (String, CommandCancellation?) -> [String]

    init(
        query: @escaping @Sendable (String, CommandCancellation?) -> [String] = {
            mdfind($0, cancellation: $1)
        }
    ) {
        self.query = query
    }

    func start() {
        active = true
        search()
    }

    func cancel() {
        active = false
        task?.cancel()
        cancellation?.cancel()
        isSearching = false
    }

    /// Set the paths of the application, the folders of them are searched.
    ///
    /// - Parameters:
    ///   - paths: The paths of the application.
    ///   - xdgPaths: The XDG paths of the application.
    func setPaths(
        _ paths: [EditorPath],
        xdgPaths: [EditorPath]
    ) {
        var folders: [URL] = []
        var files: [URL] = []
        var known: Set<String> = []

        for path: EditorPath in paths + xdgPaths {
            known.insert(path.id)
            let url: URL = path.url
            var isDirectory: ObjCBool = false
            guard
                FileManager.default.fileExists(
                    atPath: url.path,
                    isDirectory: &isDirectory
                )
            else {
                // The path does not exist, there is nothing to search in it
                continue
            }
            if isDirectory.boolValue {
                folders.append(url)
            } else {
                files.append(url)
            }
        }

        roots = folders
        rootFiles = files
        knownPaths = known
        if active { search() }
    }

}

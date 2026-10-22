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
/// The files of the application are the ones of the folders of its config,
/// the ones of the standard places of macOS, and the ones that Spotlight
/// knows about. The ones that are found can be added to the application, to
/// be backed up with it.
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
    private(set) var results: [FoundFile] = []

    /// Whether the search is running.
    private(set) var isSearching: Bool = false

    /// The folders that are searched.
    private var roots: [URL] = []

    /// The files that are searched.
    private var rootFiles: [URL] = []

    /// The paths that are already in the application.
    private var knownPaths: Set<String> = []

    /// The names of the application, they are used by the search.
    private var appNames: [String] = []

    /// The task of the search that is running.
    private var task: Task<Void, Never>?
    private var cancellation: CommandCancellation?
    private var cachedIdentifiers: [String]?
    private var active = false

    func start() { active = true; search() }

    func cancel() {
        active = false
        task?.cancel()
        cancellation?.cancel()
        isSearching = false
    }

    /// Whether the application has files that can be searched.
    var hasFolders: Bool { !roots.isEmpty || !rootFiles.isEmpty }

    /// Set the paths of the application, the folders of them are searched.
    ///
    /// The standard places of the application are searched too, they are
    /// found by the name of the application.
    ///
    /// - Parameters:
    ///   - paths: The paths of the application.
    ///   - xdgPaths: The XDG paths of the application.
    ///   - name: The name of the application, as it is shown.
    ///   - identifier: The identifier of the application.
    func setPaths(
        _ paths: [EditorPath],
        xdgPaths: [EditorPath],
        name: String,
        identifier: String
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

        // The standard places of the application, they are named after it
        for title: String in [name, identifier] {
            let trimmed: String = title.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            for candidate: URL in Self.standardPlaces(named: trimmed) {
                var isDirectory: ObjCBool = false
                guard
                    FileManager.default.fileExists(
                        atPath: candidate.path,
                        isDirectory: &isDirectory
                    ),
                    isDirectory.boolValue
                else {
                    continue
                }
                if !folders.contains(candidate) { folders.append(candidate) }
            }

            let preferences: URL = Self.home
                .appendingPathComponent("Library/Preferences/\(trimmed).plist")
            if !files.contains(preferences) { files.append(preferences) }
        }

        roots = folders
        rootFiles = files
        knownPaths = known
        if appNames != [name, identifier] { cachedIdentifiers = nil }
        appNames = [name, identifier]
        if active { search() }
    }

    /// The standard places of an application, on macOS.
    ///
    /// The cache is not there, it is not worth being backed up.
    ///
    /// - Parameter name: The name of the application.
    /// - Returns: The folders where the application keeps its data.
    nonisolated static func standardPlaces(named name: String) -> [URL] {
        let home: URL = Self.home
        return [
            xdgConfigHome.appendingPathComponent(name),
            home.appendingPathComponent("Library/Application Support/\(name)"),
            home.appendingPathComponent("Library/Containers/\(name)"),
            home.appendingPathComponent("Library/Logs/\(name)"),
            home.appendingPathComponent(
                "Library/Saved Application State/\(name).savedState"
            ),
        ]
    }

    /// The files of the home directory that belong to the application.
    ///
    /// The hidden files of the home directory, like the ones of the programs
    /// that keep their data in a dot folder, are not searched by Spotlight.
    /// They are found here.
    ///
    /// - Parameters:
    ///   - names: The names of the application.
    ///   - text: The text that is searched.
    ///   - known: The paths that are already in the application.
    /// - Returns: The files that were found.
    nonisolated static func homeFiles(
        named names: [String],
        matching text: String,
        known: Set<String>
    ) -> [FoundFile] {
        let children: [URL] = (try? FileManager.default.contentsOfDirectory(
            at: home,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: []
        )) ?? []

        var folders: [URL] = []
        var found: [FoundFile] = []

        for child: URL in children {
            if Task.isCancelled { break }
            var title: String = child.lastPathComponent
            if title.hasPrefix(".") { title.removeFirst() }

            guard
                names.contains(where: {
                    !$0.isEmpty && title.localizedCaseInsensitiveContains($0)
                })
            else {
                continue
            }
            guard let file: FoundFile = makeFile(child) else { continue }
            guard !known.contains(file.id) else { continue }

            if file.isDirectory {
                folders.append(child)
                // The folder itself is a file of the application
                if matches(file, text: text) { found.append(file) }
            } else if matches(file, text: text) {
                found.append(file)
            }
        }

        // The folders of the home directory are searched
        found += find(in: folders, matching: text, known: known)

        return found
    }

    /// The files of the folder of the preferences that belong to the
    /// application.
    ///
    /// The folder of the preferences is not searched by Spotlight, the files
    /// are found here. They are named after the application or after the
    /// identifier of its bundle.
    ///
    /// - Parameters:
    ///   - names: The names of the application.
    ///   - text: The text that is searched.
    ///   - known: The paths that are already in the application.
    /// - Returns: The files that were found.
    nonisolated static func preferenceFiles(
        named names: [String],
        matching text: String,
        known: Set<String>
    ) -> [FoundFile] {
        let folder: URL = home.appendingPathComponent("Library/Preferences")
        let children: [URL] = (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: []
        )) ?? []

        var found: [FoundFile] = []
        for child: URL in children {
            if Task.isCancelled { break }
            let title: String = child.lastPathComponent
            guard
                names.contains(where: {
                    !$0.isEmpty && title.localizedCaseInsensitiveContains($0)
                })
            else {
                continue
            }
            guard let file: FoundFile = makeFile(child) else { continue }
            guard matches(file, text: text) else { continue }
            guard !known.contains(file.id) else { continue }

            found.append(file)
            if found.count >= maximumResults { return found }
        }
        return found
    }

    /// The identifiers of the bundles of the applications that are installed.
    ///
    /// The files of an application are often named after the identifier of
    /// its bundle, and not after its name.
    ///
    /// - Parameter names: The names of the application.
    /// - Returns: The identifiers of the bundles that were found.
    nonisolated static func bundleIdentifiers(
        named names: [String], cancellation: CommandCancellation? = nil
    ) -> [String] {
        var identifiers: [String] = []

        for name: String in names {
            if Task.isCancelled { break }
            let trimmed: String = name.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            for path: String in mdfind(
                "kMDItemFSName == '*\(Self.escapedQuery(trimmed)).app'c", cancellation: cancellation
            ) {
                guard path.hasSuffix(".app") else { continue }
                guard
                    let identifier: String = bundleIdentifier(of: path),
                    !identifiers.contains(identifier)
                else {
                    continue
                }
                identifiers.append(identifier)
            }
        }

        return identifiers
    }

    /// The identifier of the bundle of an installed application.
    ///
    /// - Parameter path: The path of the application bundle.
    /// - Returns: The identifier of the bundle, nil when it is not known.
    nonisolated static func bundleIdentifier(of path: String) -> String? {
        let plist: URL = URL(fileURLWithPath: path)
            .appendingPathComponent("Contents/Info.plist")

        guard
            let data: Data = try? Data(contentsOf: plist),
            let properties: [String: Any] = try? PropertyListSerialization
                .propertyList(from: data, format: nil) as? [String: Any],
            let identifier: String = properties["CFBundleIdentifier"] as? String
        else {
            return nil
        }

        return identifier
    }

    /// The home directory of the user.
    nonisolated static var home: URL {
        EditorPath.homeDirectory
    }

    /// The directory of the configuration of the user, the XDG one.
    nonisolated static var xdgConfigHome: URL {
        EditorPath.xdgDirectory
    }

    /// Search the files a little later, when the user stops typing.
    ///
    /// The search of the disk is not cheap, it waits for the user.
    private func scheduleSearch() {
        guard active else { return }
        task?.cancel()
        cancellation?.cancel()
        task = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.search()
        }
    }

    /// Search the files that match the text.
    func search() {
        guard active else { return }
        task?.cancel()
        cancellation?.cancel()
        let token = CommandCancellation()
        cancellation = token
        let cached = cachedIdentifiers
        let roots: [URL] = self.roots
        let files: [URL] = self.rootFiles
        let known: Set<String> = self.knownPaths
        let names: [String] = self.appNames
        let text: String = searchText.trimmingCharacters(in: .whitespaces)

        isSearching = true
        task = Task { [weak self] in
            let worker = Task.detached(priority: .userInitiated) {
                // The identifier of the bundle of the application, the files
                // of an application are often named after it
                let identifiers =
                    cached ?? (names + Self.bundleIdentifiers(named: names, cancellation: token))

                // The standard places of the application, they are named
                // after the application and after its bundle
                var folders: [URL] = roots
                for identifier: String in identifiers {
                    for place: URL in Self.standardPlaces(named: identifier) {
                        var isDirectory: ObjCBool = false
                        guard
                            FileManager.default.fileExists(
                                atPath: place.path,
                                isDirectory: &isDirectory
                            ),
                            isDirectory.boolValue,
                            !folders.contains(place)
                        else {
                            continue
                        }
                        folders.append(place)
                    }
                }

                var found: [FoundFile] = Self.find(
                    in: folders,
                    files: files,
                    matching: text,
                    known: known
                )

                // The files of the preferences, they are not searched by
                // Spotlight
                found += Self.preferenceFiles(
                    named: identifiers,
                    matching: text,
                    known: known
                )

                // The hidden files of the home directory, they are not
                // searched by Spotlight either
                found += Self.homeFiles(
                    named: identifiers,
                    matching: text,
                    known: known
                )

                // The files of the whole disk
                found += Self.spotlightSearch(
                    names: identifiers,
                    matching: text,
                    known: known,
                    cancellation: token
                )

                var seen: Set<String> = []
                return (
                    identifiers,
                    found
                        .filter { seen.insert($0.id).inserted }
                    .sorted { $0.relativePath < $1.relativePath }
                        .prefix(Self.maximumResults).map { $0 }
                )
            }
            let (identifiers, found) = await withTaskCancellationHandler {
                await worker.value
            } onCancel: {
                worker.cancel(); token.cancel()
            }

            guard !Task.isCancelled else { return }
            self?.cachedIdentifiers = identifiers
            self?.results = found
            self?.isSearching = false
        }
    }

    /// Whether the file is already in the application.
    ///
    /// - Parameter file: The file.
    /// - Returns: True when the file is in the application.
    func isKnown(_ file: FoundFile) -> Bool {
        knownPaths.contains(file.id)
    }

    /// Find the files that match the text, in the folders.
    ///
    /// - Parameters:
    ///   - roots: The folders that are searched.
    ///   - files: The files that are searched.
    ///   - text: The text that is searched.
    ///   - known: The paths that are already in the application.
    /// - Returns: The files that were found.
    nonisolated static func find(
        in roots: [URL],
        files: [URL] = [],
        matching text: String,
        known: Set<String>
    ) -> [FoundFile] {
        let manager: FileManager = .default
        var found: [FoundFile] = []

        for file: URL in files {
            guard
                manager.fileExists(atPath: file.path),
                let item: FoundFile = makeFile(file)
            else {
                continue
            }
            if matches(item, text: text) && !known.contains(item.id) {
                found.append(item)
            }
        }

        for root: URL in roots {
            // The folder itself is a file of the application
            if let root: FoundFile = makeFile(root),
               matches(root, text: text),
                !known.contains(root.id)
            {
                found.append(root)
            }

            var stack: [(url: URL, depth: Int)] = [(root, 0)]
            while let item: (url: URL, depth: Int) = stack.popLast() {
                if Task.isCancelled { break }
                guard item.depth < maximumDepth else { continue }

                let children: [URL] = (try? manager.contentsOfDirectory(
                    at: item.url,
                    includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
                    options: []
                )) ?? []

                for child: URL in children {
                    if Task.isCancelled { break }
                    guard let file: FoundFile = makeFile(child) else { continue }

                    if matches(file, text: text) && !known.contains(file.id) {
                        found.append(file)
                    }

                    if file.isDirectory {
                        stack.append((child, item.depth + 1))
                    }

                    if found.count >= maximumResults { return found }
                }
            }
        }

        return found
    }

    /// Find the files that Spotlight knows about the application.
    ///
    /// The files are searched by the name of the application, over the whole
    /// disk, the ones that are outside of the home are not shown, they
    /// cannot be added to the application.
    ///
    /// - Parameters:
    ///   - names: The names of the application.
    ///   - text: The text that is searched.
    ///   - known: The paths that are already in the application.
    /// - Returns: The files that were found.
    nonisolated static func spotlightSearch(
        names: [String],
        matching text: String,
        known: Set<String>,
        cancellation: CommandCancellation? = nil
    ) -> [FoundFile] {
        var found: [FoundFile] = []
        var seen: Set<String> = []

        for name: String in names {
            if Task.isCancelled { break }
            let trimmed: String = name.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            for path: String in mdfind(
                "kMDItemFSName == '*\(Self.escapedQuery(trimmed))*'c", cancellation: cancellation)
            {
                guard !seen.contains(path) else { continue }
                seen.insert(path)

                let url: URL = URL(fileURLWithPath: path)
                guard isInTheHome(url) else { continue }
                guard let file: FoundFile = makeFile(url) else { continue }
                guard matches(file, text: text) else { continue }
                guard !known.contains(file.id) else { continue }

                found.append(file)
                if found.count >= maximumResults { return found }
            }
        }

        return found
    }

    nonisolated private static func escapedQuery(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
    }

    /// Ask Spotlight for the files that match the query.
    ///
    /// - Parameter query: The query of Spotlight.
    /// - Returns: The paths that Spotlight knows.
    nonisolated static func mdfind(_ query: String, cancellation: CommandCancellation? = nil)
        -> [String]
    {
        let process: Process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        process.arguments = [query]

        let pipe: Pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            if Task.isCancelled { return [] }
            if let cancellation { try cancellation.launch(process) } else { try process.run() }
            defer { cancellation?.forget() }
            let data: Data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            return String(data: data, encoding: .utf8)?
                .split(separator: "\n")
                .map(String.init) ?? []
        } catch {
            return []
        }
    }

    /// Make the file that is found.
    ///
    /// - Parameter url: The path of the file.
    /// - Returns: The file, nil when it cannot be read.
    nonisolated static func makeFile(_ url: URL) -> FoundFile? {
        let values: URLResourceValues = (try? url.resourceValues(
            forKeys: [.isDirectoryKey, .fileSizeKey]
        )) ?? URLResourceValues()
        let isXDG: Bool = ApplicationSearchModel.isXDG(url)

        return FoundFile(
            url: url,
            relativePath: EditorPath.relativePath(of: url, isXDG: isXDG),
            isXDG: isXDG,
            isDirectory: values.isDirectory ?? false,
            size: values.fileSize ?? 0
        )
    }

    /// Whether the file matches the text.
    ///
    /// - Parameters:
    ///   - file: The file.
    ///   - text: The text that is searched.
    /// - Returns: True when the file matches.
    nonisolated static func matches(_ file: FoundFile, text: String) -> Bool {
        guard !text.isEmpty else { return true }
        return file.url.lastPathComponent
            .localizedCaseInsensitiveContains(text)
            || file.relativePath.localizedCaseInsensitiveContains(text)
    }

    /// Whether a path is in the XDG config directory.
    ///
    /// - Parameter url: The path.
    /// - Returns: True when the path is in the XDG config directory.
    nonisolated static func isXDG(_ url: URL) -> Bool {
        let prefix: String = xdgConfigHome.standardizedFileURL.path + "/"
        return url.standardizedFileURL.path.hasPrefix(prefix)
    }

    /// Whether a path is in the home directory of the user.
    ///
    /// - Parameter url: The path.
    /// - Returns: True when the path is in the home directory.
    nonisolated static func isInTheHome(_ url: URL) -> Bool {
        let prefix: String = home.standardizedFileURL.path + "/"
        return url.standardizedFileURL.path.hasPrefix(prefix)
    }
}

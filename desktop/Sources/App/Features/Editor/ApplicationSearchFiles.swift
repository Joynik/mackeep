import Foundation

extension ApplicationSearchModel {
    /// The standard places of an application, on macOS.
    ///
    /// The cache is not there, it is not worth being backed up.
    ///
    /// - Parameter name: The name of the application.
    /// - Returns: The folders where the application keeps its data.
    nonisolated static func standardPlaces(named name: String) -> [URL] {
        guard !name.contains("/"), name != ".", name != ".." else { return [] }
        let home: URL = Self.home
        return [
            xdgConfigHome.appendingPathComponent(name),
            home.appendingPathComponent("Library/Application Support/\(name)"),
            home.appendingPathComponent("Library/Containers/\(name)"),
            home.appendingPathComponent("Library/Logs/\(name)"),
            home.appendingPathComponent(
                "Library/Saved Application State/\(name).savedState"
            )
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
        let children: [URL] =
            (try? FileManager.default.contentsOfDirectory(
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
        let children: [URL] =
            (try? FileManager.default.contentsOfDirectory(
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
        named names: [String], cancellation: CommandCancellation? = nil,
        query: (String, CommandCancellation?) -> [String] = { mdfind($0, cancellation: $1) }
    ) -> [String] {
        var identifiers: [String] = []

        for name: String in names {
            if Task.isCancelled { break }
            let trimmed: String = name.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            for path: String in query(
                "kMDItemFSName == '*\(Self.escapedQuery(trimmed)).app'c", cancellation
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

    nonisolated static func makeFile(_ url: URL) -> FoundFile? {
        let values: URLResourceValues =
            (try? url.resourceValues(
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

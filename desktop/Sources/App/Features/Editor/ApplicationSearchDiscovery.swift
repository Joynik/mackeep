import Foundation

extension ApplicationSearchModel {
    /// Ask Spotlight for the files that match the query.
    ///
    /// - Parameter query: The query of Spotlight.
    /// - Returns: The paths that Spotlight knows.
    nonisolated static func mdfind(
        _ query: String,
        cancellation: CommandCancellation? = nil
    ) -> [String] {
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
        var found: [FoundFile] = []
        for file in files {
            if let match = matchingFile(at: file, text: text, known: known, requireExisting: true) {
                found.append(match)
            }
        }
        for root in roots {
            if let match = matchingFile(at: root, text: text, known: known) {
                found.append(match)
            }
            found += findChildren(
                in: root,
                matching: text,
                known: known,
                initialCount: found.count
            )
        }
        return found
    }

    private nonisolated static func matchingFile(
        at url: URL,
        text: String,
        known: Set<String>,
        requireExisting: Bool = false
    ) -> FoundFile? {
        guard
            !requireExisting || FileManager.default.fileExists(atPath: url.path),
            let file = makeFile(url),
            matches(file, text: text),
            !known.contains(file.id)
        else {
            return nil
        }
        return file
    }

    private nonisolated static func findChildren(
        in root: URL,
        matching text: String,
        known: Set<String>,
        initialCount: Int
    ) -> [FoundFile] {
        let manager = FileManager.default
        var found: [FoundFile] = []
        var stack: [(url: URL, depth: Int)] = [(root, 0)]
        while let item = stack.popLast() {
            if Task.isCancelled { break }
            guard item.depth < maximumDepth else { continue }
            let children =
                (try? manager.contentsOfDirectory(
                    at: item.url,
                    includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
                    options: []
                )) ?? []
            for child in children {
                if Task.isCancelled { break }
                guard let file = makeFile(child) else { continue }
                if matches(file, text: text) && !known.contains(file.id) {
                    found.append(file)
                }
                if file.isDirectory {
                    stack.append((child, item.depth + 1))
                }
                if initialCount + found.count >= maximumResults { return found }
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
    ///   - query: Spotlight query boundary, replaceable for deterministic tests.
    /// - Returns: The files that were found.
    nonisolated static func spotlightSearch(
        names: [String],
        matching text: String,
        known: Set<String>,
        cancellation: CommandCancellation? = nil,
        query: (String, CommandCancellation?) -> [String] = { mdfind($0, cancellation: $1) }
    ) -> [FoundFile] {
        var found: [FoundFile] = []
        var seen: Set<String> = []

        for name: String in names {
            if Task.isCancelled { break }
            let trimmed: String = name.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            for path: String in query(
                "kMDItemFSName == '*\(Self.escapedQuery(trimmed))*'c", cancellation
            ) {
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

    nonisolated static func escapedQuery(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
    }

    /// Make the file that is found.
    ///
    /// - Parameter url: The path of the file.
    /// - Returns: The file, nil when it cannot be read.
}

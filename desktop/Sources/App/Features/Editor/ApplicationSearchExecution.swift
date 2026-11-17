import Foundation

extension ApplicationSearchModel {
    private struct SearchRequest: Sendable {
        let cachedIdentifiers: [String]?
        let text: String
        let roots: [URL]
        let files: [URL]
        let known: Set<String>
        let token: CommandCancellation
        let query: @Sendable (String, CommandCancellation?) -> [String]
    }

    nonisolated private static func performSearch(
        _ request: SearchRequest
    ) -> (identifiers: [String], files: [FoundFile]) {
        let names = [request.text]
        let identifiers =
            request.cachedIdentifiers
            ?? (names
                + bundleIdentifiers(
                    named: names,
                    cancellation: request.token,
                    query: request.query
                ))
        let found = findAllFiles(identifiers: identifiers, request: request)
        var seen: Set<String> = []
        let orderedFiles =
            found
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.relativePath < $1.relativePath }
            .prefix(maximumResults)
        return (identifiers, Array(orderedFiles))
    }

    nonisolated private static func findAllFiles(
        identifiers: [String],
        request: SearchRequest
    ) -> [FoundFile] {
        var folders = request.roots
        for identifier in identifiers {
            for place in standardPlaces(named: identifier) {
                var isDirectory: ObjCBool = false
                guard
                    FileManager.default.fileExists(atPath: place.path, isDirectory: &isDirectory),
                    isDirectory.boolValue,
                    !folders.contains(place)
                else {
                    continue
                }
                folders.append(place)
            }
        }
        return find(
            in: folders,
            files: request.files,
            matching: request.text,
            known: request.known
        )
            + preferenceFiles(
                named: identifiers,
                matching: request.text,
                known: request.known
            )
            + homeFiles(
                named: identifiers,
                matching: request.text,
                known: request.known
            )
            + spotlightSearch(
                names: identifiers,
                matching: request.text,
                known: request.known,
                cancellation: request.token,
                query: request.query
            )
    }

    /// Search the files a little later, when the user stops typing.
    ///
    /// The search of the disk is not cheap, it waits for the user.
    func scheduleSearch() {
        guard active else { return }
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            search()
            return
        }
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
        let text = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            results = []
            isSearching = false
            return
        }
        let cached = cachedSearchText == text ? cachedIdentifiers : nil
        let roots: [URL] = self.roots
        let files: [URL] = self.rootFiles
        let known: Set<String> = self.knownPaths
        let query = self.query

        isSearching = true
        task = Task { [weak self] in
            let worker = Task.detached(priority: .userInitiated) {
                Self.performSearch(
                    SearchRequest(
                        cachedIdentifiers: cached,
                        text: text,
                        roots: roots,
                        files: files,
                        known: known,
                        token: token,
                        query: query
                    )
                )
            }
            let (identifiers, found) = await withTaskCancellationHandler {
                await worker.value
            } onCancel: {
                worker.cancel()
                token.cancel()
            }

            guard !Task.isCancelled else { return }
            self?.cachedIdentifiers = identifiers
            self?.cachedSearchText = text
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
}

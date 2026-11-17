import Foundation

extension ApplicationsModel {
    /// Estimate only the selected application, never the entire catalog.
    func estimateSize(for application: MackeepApplication) {
        guard sizes[application.name] == nil else { return }
        sizeTask?.cancel()
        sizeTask = Task {
            let worker = Task.detached(priority: .utility) {
                var size = 0
                var seen: Set<URL> = []
                for (paths, isXDG) in [(application.files, false), (application.xdgFiles, true)] {
                    for path in paths where path.exists {
                        if Task.isCancelled { return 0 }
                        let url = EditorPath.absoluteURL(of: path.path, isXDG: isXDG)
                            .standardizedFileURL
                        if seen.insert(url).inserted { size += Self.size(of: url) }
                    }
                }
                return size
            }
            let size = await withTaskCancellationHandler {
                await worker.value
            } onCancel: {
                worker.cancel()
            }
            if !Task.isCancelled { sizes[application.name] = size }
        }
    }

    /// The size of a file or of a directory.
    ///
    /// - Parameter url: The path of the file.
    /// - Returns: The size in bytes.
    nonisolated static func size(of url: URL) -> Int {
        let manager: FileManager = .default
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return 0
        }
        guard isDirectory.boolValue else {
            let attributes: [FileAttributeKey: Any] =
                (try? manager.attributesOfItem(
                    atPath: url.path
                )) ?? [:]
            return (attributes[.size] as? Int) ?? 0
        }

        var size: Int = 0
        guard
            let enumerator: FileManager.DirectoryEnumerator = manager.enumerator(
                at: url,
                includingPropertiesForKeys: [.fileSizeKey],
                options: []
            )
        else {
            return 0
        }
        for case let file as URL in enumerator {
            if Task.isCancelled { break }
            let attributes: [FileAttributeKey: Any] =
                (try? manager.attributesOfItem(
                    atPath: file.path
                )) ?? [:]
            size += (attributes[.size] as? Int) ?? 0
        }
        return size
    }
}

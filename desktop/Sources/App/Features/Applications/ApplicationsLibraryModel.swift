import Foundation

extension ApplicationsModel {
    /// Fetch only the catalog manifest; existing definitions remain usable offline.
    func checkLibraryUpdates(force: Bool = false) async {
        guard let command, !isCheckingLibrary, !isUpdatingLibrary else { return }
        let checkedRecently =
            libraryCheckedAt.map {
                Date().timeIntervalSince($0) < 86_400
            } ?? false
        if !force && checkedRecently { return }
        isCheckingLibrary = true
        defer { isCheckingLibrary = false }
        do {
            let status = try await Task.detached {
                try command.runJSON(["--json", "library", "check"], as: LibraryStatus.self)
            }.value
            applyLibraryStatus(status)
        } catch {
            libraryError = error.localizedDescription
        }
    }

    /// Replace changed library definitions through the shared CLI implementation.
    func updateLibrary(application: String? = nil) async {
        guard let command, !isCheckingLibrary, !isUpdatingLibrary else { return }
        isUpdatingLibrary = true
        defer { isUpdatingLibrary = false }
        do {
            let arguments = ["--json", "library", "update"] + (application.map { [$0] } ?? [])
            let status = try await Task.detached {
                try command.runJSON(arguments, as: LibraryStatus.self)
            }.value
            applyLibraryStatus(status)
            if !(await reload()) {
                libraryError = L10n.string("applications.library.reloadFailed")
            }
        } catch {
            libraryError = error.localizedDescription
        }
    }

    /// Remove only an upstream-removed definition, after saving its deselection.
    func removeLibraryDefinition(_ application: MackeepApplication) async {
        guard let command, !isCheckingLibrary, !isUpdatingLibrary,
            !application.isCustom,
            removedLibraryDefinitions.contains(application.name)
        else { return }
        isUpdatingLibrary = true
        defer { isUpdatingLibrary = false }
        do {
            removeFromTheList(application)
            try await flushSelection()
            let name = application.name
            let status = try await Task.detached {
                try command.runJSON(["--json", "library", "remove", name], as: LibraryStatus.self)
            }.value
            applyLibraryStatus(status)
            if !(await reload()) {
                libraryError = L10n.string("applications.library.reloadFailed")
            }
        } catch {
            libraryError = error.localizedDescription
        }
    }

    private func applyLibraryStatus(_ status: LibraryStatus) {
        libraryUpdates = Set(status.updates.map(\.name))
        newLibraryDefinitions = status.new
        removedLibraryDefinitions = Set(status.removed)
        libraryCheckedAt = Date()
        libraryError = nil
    }
}

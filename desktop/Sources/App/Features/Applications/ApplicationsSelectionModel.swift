import Foundation

extension ApplicationsModel {
    /// Set whether the application is used for the backup, and write the
    /// config file.
    ///
    /// The applications that are checked are the ones to sync, the ones of
    /// the list that are not checked are the ones to ignore. The
    /// applications that are not in the list are not backed up.
    ///
    /// - Parameters:
    ///   - application: The application.
    ///   - enabled: Whether the application is backed up.
    func setEnabled(_ enabled: Bool, for application: MackeepApplication) {
        guard config != nil else { return }

        if enabled {
            syncedApps.insert(application.name)
            ignoredApps.remove(application.name)
        } else {
            syncedApps.remove(application.name)
            ignoredApps.insert(application.name)
        }

        writeTheLists()
    }

    /// Add an application of the library to the list of the user.
    ///
    /// The application is checked, it is used for the backup.
    ///
    /// - Parameter application: The application.
    func addToTheList(_ application: MackeepApplication) {
        setEnabled(true, for: application)
    }

    /// Remove an application of the library from the list of the user.
    ///
    /// The application is not backed up any more, and it is not in the list
    /// of the user.
    ///
    /// - Parameter application: The application.
    func removeFromTheList(_ application: MackeepApplication) {
        syncedApps.remove(application.name)
        ignoredApps.remove(application.name)
        writeTheLists()
    }

    /// Write the lists of the applications in the config file.
    private func writeTheLists() {
        guard let config else { return }

        config.setSyncedApplications(Array(syncedApps), ignored: Array(ignoredApps))
        let document = config.document
        let url = config.url
        saveRevision += 1
        let revision = saveRevision
        let selection = (syncedApps, ignoredApps)
        let previous = pendingSave
        pendingSave = Task {
            await previous?.value
            let message: String? = await Task.detached(priority: .userInitiated) {
                do {
                    let saving = MainConfig(url: url, document: document)
                    saving.setSyncedApplications(
                        document.values(inSection: "applications_to_sync"),
                        ignored: document.values(inSection: "applications_to_ignore")
                    )
                    try saving.save()
                    return nil
                } catch {
                    return error.localizedDescription
                }
            }.value
            if message == nil { savedSelection = selection }
            guard revision == saveRevision else { return }
            saveError = message
            if let message {
                syncedApps = savedSelection.0
                ignoredApps = savedSelection.1
                presentedError = AppError(
                    title: L10n.string("error.save.title"),
                    message: message
                )
            }
        }
    }
}

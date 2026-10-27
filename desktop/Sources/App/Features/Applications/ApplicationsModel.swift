import Foundation

/// The compatible JSON response of a library check or update.
struct LibraryStatus: Decodable, Sendable {
    struct Update: Decodable, Sendable {
        let name: String
        let sha256: String
    }

    struct NewDefinition: Decodable, Sendable, Identifiable {
        let name: String
        let displayName: String
        var id: String { name }

        enum CodingKeys: String, CodingKey {
            case name
            case displayName = "display_name"
        }
    }

    let revision: String
    let updates: [Update]
    let new: [NewDefinition]
    let removed: [String]

    enum CodingKeys: String, CodingKey { case revision, updates, new, removed }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        revision = try container.decode(String.self, forKey: .revision)
        updates = try container.decode([Update].self, forKey: .updates)
        new = try container.decodeIfPresent([NewDefinition].self, forKey: .new) ?? []
        removed = try container.decodeIfPresent([String].self, forKey: .removed) ?? []
    }
}

/// The filter of the list of the applications.
enum ApplicationFilter: String, CaseIterable, Identifiable {
    /// Every application of the list.
    case all

    /// The applications of the user.
    case custom

    /// The applications that were added from the library.
    case library

    /// The applications that are used for the backup.
    case enabled

    /// The applications that are not used for the backup.
    case disabled

    var id: String { rawValue }

    /// The title of the filter.
    var title: String {
        switch self {
        case .all: L10n.string("filter.applications.all")
        case .custom: L10n.string("filter.applications.custom")
        case .library: L10n.string("filter.applications.library")
        case .enabled: L10n.string("filter.applications.enabled")
        case .disabled: L10n.string("filter.applications.disabled")
        }
    }
}

/// The model of the list of the applications.
@Observable
@MainActor
final class ApplicationsModel {
    /// The applications of Mackeep.
    private(set) var applications: [MackeepApplication] = []

    /// The names of library definitions with a newer published version.
    private(set) var libraryUpdates: Set<String> = []
    private(set) var newLibraryDefinitions: [LibraryStatus.NewDefinition] = []
    private(set) var removedLibraryDefinitions: Set<String> = []
    private(set) var isCheckingLibrary = false
    private(set) var isUpdatingLibrary = false
    private(set) var libraryCheckedAt: Date?
    private(set) var libraryError: String?

    /// Fetch only the catalog manifest; existing definitions remain usable offline.
    func checkLibraryUpdates(force: Bool = false) async {
        guard let command, !isCheckingLibrary, !isUpdatingLibrary else { return }
        if !force, let libraryCheckedAt,
           Date().timeIntervalSince(libraryCheckedAt) < 86_400 { return }
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
              removedLibraryDefinitions.contains(application.name) else { return }
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

    /// The identifier of the selected application.
    var selection: String?

    /// The application that is copied, when the user asks for a copy.
    var copyRequest: MackeepApplication?

    /// The text of the search.
    var searchText: String = ""

    /// The filter of the list.
    var filter: ApplicationFilter = .all

    /// The estimated size of the applications, in bytes.
    private(set) var sizes: [String: Int] = [:]

    /// The error shown to the user, when there is one.
    var presentedError: AppError?

    /// The main config file of Mackeep.
    private(set) var config: MainConfig?

    /// The applications that are used for the backup.
    ///
    /// They are kept here, and not only in the config file, so the view is
    /// told when they change.
    private(set) var syncedApps: Set<String> = []

    /// The applications of the list that are not used for the backup.
    private(set) var ignoredApps: Set<String> = []

    /// The directory where the config files of the user are.
    private(set) var customAppsDir: String?

    /// The command line tool of Mackeep.
    private let command: MackeepCommand?

    /// The latest save, chained after earlier writes to preserve click order.
    private var pendingSave: Task<Void, Never>?
    private var saveRevision = 0
    private var saveError: String?
    private var savedSelection: (Set<String>, Set<String>) = ([], [])
    private var sizeTask: Task<Void, Never>?

    /// The editors of the applications, by identifier.
    private var editors: [String: ApplicationEditorModel] = [:]

    /// Create the model.
    ///
    /// - Parameter command: The command line tool of Mackeep.
    init(command: MackeepCommand?) {
        self.command = command
    }

    /// The applications of the list: the ones of the user and the ones that
    /// were added from the library.
    ///
    /// The applications of the library that the user did not add are not in
    /// the list, they are in the library.
    var listedApplications: [MackeepApplication] {
        applications
            .filter { application in
                application.isCustom || isListed(application)
            }
            .sorted {
                $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
            }
    }

    /// The applications of the list, after the filter and the search.
    ///
    /// They are sorted by the name of the application.
    var visibleApplications: [MackeepApplication] {
        let searched: [MackeepApplication] = listedApplications.filter { application in
            guard !searchText.isEmpty else { return true }
            return application.name.localizedCaseInsensitiveContains(searchText)
                || application.displayName.localizedCaseInsensitiveContains(searchText)
        }
        let filtered: [MackeepApplication] = searched.filter { application in
            switch filter {
            case .all: true
            case .custom: application.isCustom
            case .library: !application.isCustom
            case .enabled: isEnabled(application)
            case .disabled: !isEnabled(application)
            }
        }
        return filtered
    }

    /// The selected application.
    var selectedApplication: MackeepApplication? {
        guard let selection else { return nil }
        return listedApplications.first { $0.name == selection }
    }

    /// Whether the application is used for the backup.
    ///
    /// The checkbox of the list is set by hand, it tells what is backed up.
    ///
    /// - Parameter application: The application.
    /// - Returns: True when the application is backed up.
    func isEnabled(_ application: MackeepApplication) -> Bool {
        syncedApps.contains(application.name)
    }

    /// Whether the application is in the list of the user.
    ///
    /// The applications of the user are always in it, the ones of the library
    /// are in it when the user added them.
    ///
    /// - Parameter application: The application.
    /// - Returns: True when the application is in the list.
    func isListed(_ application: MackeepApplication) -> Bool {
        syncedApps.contains(application.name) || ignoredApps.contains(application.name)
    }

    /// Whether the application is installed on this Mac.
    ///
    /// - Parameter application: The application.
    /// - Returns: True when one of its paths exists.
    func isInstalled(_ application: MackeepApplication) -> Bool {
        (application.files + application.xdgFiles).contains { $0.exists }
    }

    /// The estimated size of an application, in bytes.
    ///
    /// - Parameter application: The application.
    /// - Returns: The size, zero when it is not known.
    func size(of application: MackeepApplication) -> Int {
        sizes[application.name] ?? 0
    }

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

    /// Wait until the queued configuration writes finish.
    func waitForPendingSaves() async {
        while true {
            let revision = saveRevision
            await pendingSave?.value
            if revision == saveRevision { return }
        }
    }

    /// Fail closed if the user's intended selection could not be saved.
    func flushSelection() async throws {
        await waitForPendingSaves()
        if let saveError {
            self.saveError = nil
            throw NSError(
                domain: "MackeepSelection", code: 1,
                userInfo: [NSLocalizedDescriptionKey: saveError])
        }
    }

    /// The model of the editor of an application.
    ///
    /// - Parameter appName: The identifier of the application.
    /// - Returns: The model, nil when the application is not known.
    func editor(for appName: String) -> ApplicationEditorModel? {
        if let editor: ApplicationEditorModel = editors[appName] {
            return editor
        }
        guard
            let application: MackeepApplication = applications
                .first(where: { $0.name == appName })
        else {
            return nil
        }
        let url: URL = URL(fileURLWithPath: application.cfgPath)
        guard let document: INIDocument = try? INIFile.load(from: url) else {
            return nil
        }
        let editor: ApplicationEditorModel = ApplicationEditorModel(
            appName: appName,
            url: url,
            document: document,
            mainConfig: config,
            onSave: { [weak self] in
                // The files of the application are shown in the details
                self?.load()
            }
        )
        editors[appName] = editor
        return editor
    }

    /// Set the applications of the list.
    ///
    /// - Parameter applications: The applications.
    func setApplications(_ applications: [MackeepApplication]) {
        self.applications = applications
        if let config { setConfig(config) }
    }

    /// The directory where the config files of the user are.
    ///
    /// It is the directory the tool of Mackeep reads, the user can have it
    /// somewhere else.
    var customAppsDirectory: URL {
        if let directory: String = customAppsDir {
            return URL(fileURLWithPath: directory)
        }
        return URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".mackeep")
    }

    /// Delete an application of the user.
    ///
    /// The config file of the application is removed, and the application is
    /// not in the list any more. The applications of the library are not
    /// deleted, they are only removed from the list, they are still in the
    /// library.
    ///
    /// - Parameter application: The application.
    func delete(_ application: MackeepApplication) {
        guard application.isCustom else {
            removeFromTheList(application)
            load()
            return
        }

        let url: URL = URL(fileURLWithPath: application.cfgPath)
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            presentedError = AppError(
                title: L10n.string("error.save.title"),
                message: error.localizedDescription
            )
            return
        }

        editors.removeValue(forKey: application.name)
        removeFromTheList(application)
        load()
    }

    /// Set the config file of Mackeep.
    ///
    /// - Parameter config: The config.
    func setConfig(_ config: MainConfig) {
        self.config = config
        ignoredApps = Set(config.appsToIgnore)
        syncedApps =
            config.document.hasSection("applications_to_sync")
            ? Set(config.appsToSync).subtracting(ignoredApps)
            : Set(applications.map(\.name)).subtracting(ignoredApps)
        savedSelection = (syncedApps, ignoredApps)
    }

    /// Load the applications and the config of Mackeep.
    ///
    /// The work is done out of the main thread, so the window stays alive.
    func load() {
        Task { await reload() }
    }

    @discardableResult
    func reload() async -> Bool {
        guard let command else { return false }
        await waitForPendingSaves()
        let revision = saveRevision
        let result = await Task.detached(priority: .userInitiated) {
            Self.load(with: command)
        }.value
        guard revision == saveRevision else { return false }
        apply(result)
        return result.errorMessage == nil
    }

    /// What is read from Mackeep.
    private struct LoadResult: Sendable {
        /// The applications of Mackeep.
        let applications: [MackeepApplication]

        /// The path of the config file Mackeep uses.
        let configURL: URL?

        /// The content of the config file.
        let configDocument: INIDocument?

        /// The directory where the config files of the user are.
        let customAppsDir: String?

        /// The message of the error, when there is one.
        let errorMessage: String?
    }

    /// Read the applications and the config of Mackeep.
    ///
    /// - Parameter command: The command line tool of Mackeep.
    /// - Returns: What was read.
    nonisolated private static func load(with command: MackeepCommand) -> LoadResult {
        do {
            let applications: [MackeepApplication] = try command.runJSON(
                ["--json", "list"],
                as: [MackeepApplication].self
            )

            // The config file Mackeep uses is the one that is edited
            let json: MackeepConfig = try command.runJSON(
                ["--json", "config"],
                as: MackeepConfig.self
            )
            let url: URL = URL(fileURLWithPath: json.configFile)
            let document: INIDocument = try INIFile.load(
                from: url,
                stripsInlineComments: true
            )
            return LoadResult(
                applications: applications,
                configURL: url,
                configDocument: document,
                customAppsDir: json.customAppsDir,
                errorMessage: nil
            )
        } catch {
            return LoadResult(
                applications: [],
                configURL: nil,
                configDocument: nil,
                customAppsDir: nil,
                errorMessage: error.localizedDescription
            )
        }
    }

    /// Take what was read from Mackeep.
    ///
    /// - Parameter result: What was read.
    private func apply(_ result: LoadResult) {
        if let message: String = result.errorMessage {
            presentedError = AppError(
                title: L10n.string("error.load.title"),
                message: message
            )
            return
        }

        applications = result.applications
        customAppsDir = result.customAppsDir
        if let url: URL = result.configURL, let document: INIDocument = result.configDocument {
            setConfig(MainConfig(url: url, document: document))
        }
        sizeTask?.cancel()
        sizes = [:]
    }

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
            let attributes: [FileAttributeKey: Any] = (try? manager.attributesOfItem(
                atPath: url.path
            )) ?? [:]
            return (attributes[.size] as? Int) ?? 0
        }

        var size: Int = 0
        guard let enumerator: FileManager.DirectoryEnumerator = manager.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: []
        ) else {
            return 0
        }
        for case let file as URL in enumerator {
            if Task.isCancelled { break }
            let attributes: [FileAttributeKey: Any] = (try? manager.attributesOfItem(
                atPath: file.path
            )) ?? [:]
            size += (attributes[.size] as? Int) ?? 0
        }
        return size
    }
}

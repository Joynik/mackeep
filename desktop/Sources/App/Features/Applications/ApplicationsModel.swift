import Foundation

/// The compatible JSON response of a library check or update.
struct LibraryStatus: Decodable, Sendable {
    struct Update: Decodable, Sendable {
        let name: String
        let sha256: String
    }

    let revision: String
    let updates: [Update]
    let new: [NewLibraryDefinition]
    let removed: [String]

    enum CodingKeys: String, CodingKey { case revision, updates, new, removed }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        revision = try container.decode(String.self, forKey: .revision)
        updates = try container.decode([Update].self, forKey: .updates)
        new = try container.decodeIfPresent([NewLibraryDefinition].self, forKey: .new) ?? []
        removed = try container.decodeIfPresent([String].self, forKey: .removed) ?? []
    }
}

/// A definition that is new in the application library.
struct NewLibraryDefinition: Decodable, Sendable, Identifiable {
    let name: String
    let displayName: String
    var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name
        case displayName = "display_name"
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
    var applications: [MackeepApplication] = []

    /// The names of library definitions with a newer published version.
    var libraryUpdates: Set<String> = []
    var newLibraryDefinitions: [NewLibraryDefinition] = []
    var removedLibraryDefinitions: Set<String> = []
    var isCheckingLibrary = false
    var isUpdatingLibrary = false
    var libraryCheckedAt: Date?
    var libraryError: String?

    /// The identifier of the selected application.
    var selection: String?

    /// The application that is copied, when the user asks for a copy.
    var copyRequest: MackeepApplication?

    /// The text of the search.
    var searchText: String = ""

    /// The filter of the list.
    var filter: ApplicationFilter = .all

    /// The estimated size of the applications, in bytes.
    var sizes: [String: Int] = [:]

    /// The error shown to the user, when there is one.
    var presentedError: AppError?

    /// The main config file of Mackeep.
    var config: MainConfig?

    /// The applications that are used for the backup.
    ///
    /// They are kept here, and not only in the config file, so the view is
    /// told when they change.
    var syncedApps: Set<String> = []

    /// The applications of the list that are not used for the backup.
    var ignoredApps: Set<String> = []

    /// The directory where the config files of the user are.
    var customAppsDir: String?

    /// The command line tool of Mackeep.
    let command: MackeepCommand?

    /// The latest save, chained after earlier writes to preserve click order.
    var pendingSave: Task<Void, Never>?
    var saveRevision = 0
    var saveError: String?
    var savedSelection: (Set<String>, Set<String>) = ([], [])
    var sizeTask: Task<Void, Never>?

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
            let application: MackeepApplication =
                applications
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

}

import Foundation

/// The filter of the list of the applications.
enum ApplicationFilter: String, CaseIterable, Identifiable {
    /// Every application.
    case all

    /// The applications that are synced.
    case synced

    /// The applications that are not synced.
    case excluded

    /// The applications of the user.
    case custom

    /// The applications that are installed on this Mac.
    case installed

    var id: String { rawValue }

    /// The title of the filter.
    var title: String {
        switch self {
        case .all: L10n.string("filter.applications.all")
        case .synced: L10n.string("filter.applications.synced")
        case .excluded: L10n.string("filter.applications.excluded")
        case .custom: L10n.string("filter.applications.custom")
        case .installed: L10n.string("filter.applications.installed")
        }
    }
}

/// The order of the list of the applications.
enum ApplicationSort: String, CaseIterable, Identifiable {
    /// By identifier.
    case name

    /// By name.
    case displayName

    /// By size, the biggest first.
    case size

    var id: String { rawValue }

    /// The title of the order.
    var title: String {
        switch self {
        case .name: L10n.string("sort.applications.name")
        case .displayName: L10n.string("sort.applications.displayName")
        case .size: L10n.string("sort.applications.size")
        }
    }
}

/// The model of the list of the applications.
@Observable
@MainActor
final class ApplicationsModel {
    /// The applications of Mackeep.
    private(set) var applications: [MackeepApplication] = []

    /// The identifier of the selected application.
    var selection: String?

    /// The text of the search.
    var searchText: String = ""

    /// The filter of the list.
    var filter: ApplicationFilter = .all

    /// The order of the list.
    var sort: ApplicationSort = .name

    /// The way the applications are selected.
    var mode: SyncMode = .allExceptUnchecked

    /// The estimated size of the applications, in bytes.
    private(set) var sizes: [String: Int] = [:]

    /// The error shown to the user, when there is one.
    var presentedError: AppError?

    /// The main config file of Mackeep.
    private(set) var config: MainConfig?

    /// The command line tool of Mackeep.
    private let command: MackeepCommand?

    /// The editors of the applications, by identifier.
    private var editors: [String: ApplicationEditorModel] = [:]

    /// Create the model.
    ///
    /// - Parameter command: The command line tool of Mackeep.
    init(command: MackeepCommand?) {
        self.command = command
    }

    /// The applications of the list, after the filter, the search and the
    /// order.
    var visibleApplications: [MackeepApplication] {
        let searched: [MackeepApplication] = applications.filter { application in
            guard !searchText.isEmpty else { return true }
            return application.name.localizedCaseInsensitiveContains(searchText)
                || application.displayName.localizedCaseInsensitiveContains(searchText)
        }
        let filtered: [MackeepApplication] = searched.filter { application in
            switch filter {
            case .all: true
            case .synced: isSynced(application)
            case .excluded: !isSynced(application)
            case .custom: application.isCustom
            case .installed: isInstalled(application)
            }
        }
        switch sort {
        case .name:
            return filtered.sorted { $0.name < $1.name }
        case .displayName:
            return filtered.sorted { $0.displayName < $1.displayName }
        case .size:
            return filtered.sorted { (sizes[$0.name] ?? 0) > (sizes[$1.name] ?? 0) }
        }
    }

    /// The selected application.
    var selectedApplication: MackeepApplication? {
        guard let selection else { return nil }
        return applications.first { $0.name == selection }
    }

    /// The applications that are not synced.
    var excludedApplications: Set<String> {
        Set(config?.appsToIgnore ?? [])
    }

    /// Whether an application is synced.
    ///
    /// - Parameter application: The application.
    /// - Returns: True when the application is synced.
    func isSynced(_ application: MackeepApplication) -> Bool {
        switch mode {
        case .allExceptUnchecked:
            !excludedApplications.contains(application.name)
        case .onlyChecked:
            (config?.appsToSync ?? []).contains(application.name)
        }
    }

    /// Whether an application is installed on this Mac.
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

    /// Set whether an application is synced, and write the config file.
    ///
    /// - Parameters:
    ///   - application: The application.
    ///   - synced: Whether the application is synced.
    func setSynced(_ synced: Bool, for application: MackeepApplication) {
        guard let config else { return }

        var names: Set<String>
        switch mode {
        case .allExceptUnchecked:
            // The applications that are not synced are the ones that are
            // ignored
            names = excludedApplications
            if !synced { names.insert(application.name) }
        case .onlyChecked:
            names = Set(config.appsToSync)
            if synced { names.insert(application.name) } else { names.remove(application.name) }
        }

        config.setSyncedApplications(Array(names), mode: mode)
        do {
            try config.save()
        } catch {
            presentedError = AppError(
                title: L10n.string("error.save.title"),
                message: "\(error)"
            )
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
            mainConfig: config
        )
        editors[appName] = editor
        return editor
    }

    /// Set the applications of the list.
    ///
    /// - Parameter applications: The applications.
    func setApplications(_ applications: [MackeepApplication]) {
        self.applications = applications
    }

    /// Set the config file of Mackeep.
    ///
    /// - Parameter config: The config.
    func setConfig(_ config: MainConfig) {
        self.config = config
    }

    /// Load the applications and the config of Mackeep.
    ///
    /// The work is done out of the main thread, so the window stays alive.
    func load() {
        guard let command else { return }

        Task { [weak self] in
            let result: LoadResult = await Task.detached(priority: .userInitiated) {
                Self.load(with: command)
            }.value
            self?.apply(result)
        }
    }

    /// What is read from Mackeep.
    private struct LoadResult: Sendable {
        /// The applications of Mackeep.
        let applications: [MackeepApplication]

        /// The path of the config file Mackeep uses.
        let configURL: URL?

        /// The content of the config file.
        let configDocument: INIDocument?

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
                errorMessage: nil
            )
        } catch {
            return LoadResult(
                applications: [],
                configURL: nil,
                configDocument: nil,
                errorMessage: "\(error)"
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
        if let url: URL = result.configURL, let document: INIDocument = result.configDocument {
            config = MainConfig(url: url, document: document)
        }
        estimateSizes()
    }

    /// Estimate the size of the applications, in the background.
    private func estimateSizes() {
        let home: String = NSHomeDirectory()
        let applications: [MackeepApplication] = self.applications

        Task { [weak self] in
            let sizes: [String: Int] = await Task.detached(priority: .utility) {
                Self.computeSizes(of: applications, in: home)
            }.value
            self?.sizes = sizes
        }
    }

    /// Compute the size of the applications.
    ///
    /// - Parameters:
    ///   - applications: The applications.
    ///   - home: The home directory of the user.
    /// - Returns: The size of every application, in bytes.
    nonisolated private static func computeSizes(
        of applications: [MackeepApplication],
        in home: String
    ) -> [String: Int] {
        var sizes: [String: Int] = [:]
        for application in applications {
            var size: Int = 0
            for path in application.files + application.xdgFiles where path.exists {
                size += Self.size(
                    of: URL(fileURLWithPath: home).appendingPathComponent(path.path)
                )
            }
            sizes[application.name] = size
        }
        return sizes
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
            let attributes: [FileAttributeKey: Any] = (try? manager.attributesOfItem(
                atPath: file.path
            )) ?? [:]
            size += (attributes[.size] as? Int) ?? 0
        }
        return size
    }
}

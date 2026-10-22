import Foundation

/// A problem found in the config file of an application.
struct ValidationIssue: Identifiable, Equatable {
    /// The identifier of the problem.
    let id = UUID()

    /// The severity of the problem: a warning or an error.
    let severity: Severity

    /// The message of the problem.
    let message: String

    /// The severity of a problem.
    enum Severity {
        /// The application cannot be saved.
        case error

        /// The application can be saved, but something looks wrong.
        case warning
    }
}

/// The model of the editor of an application.
@Observable
@MainActor
final class ApplicationEditorModel {
    /// The identifier of the application.
    let appName: String

    /// The path of the config file of the application.
    let url: URL

    /// The content of the config file.
    private(set) var document: INIDocument

    /// The name of the application.
    var displayName: String {
        get { document.value(forKey: "name", inSection: "application") ?? "" }
        set {
            document.setValue(newValue, forKey: "name", inSection: "application")
            validate()
        }
    }

    /// The paths of the application.
    var paths: [EditorPath] {
        get {
            document.values(inSection: "configuration_files").map {
                EditorPath(path: $0)
            }
        }
        set {
            document.setOptionKeys(
                newValue.map(\.path),
                inSection: "configuration_files"
            )
            validate()
        }
    }

    /// The XDG paths of the application.
    var xdgPaths: [EditorPath] {
        get {
            document.values(inSection: "xdg_configuration_files").map {
                EditorPath(path: $0, isXDG: true)
            }
        }
        set {
            document.setOptionKeys(
                newValue.map(\.path),
                inSection: "xdg_configuration_files"
            )
            validate()
        }
    }

    /// The exclusion rules of the application.
    var excludes: [String] {
        get { document.values(inSection: "exclude") }
        set { document.setOptionKeys(newValue, inSection: "exclude") }
    }

    /// The XDG exclusion rules of the application.
    var xdgExcludes: [String] {
        get { document.values(inSection: "xdg_exclude") }
        set { document.setOptionKeys(newValue, inSection: "xdg_exclude") }
    }

    /// The text of the config file, in the text mode.
    var text: String {
        get { document.text }
        set {
            guard newValue != document.text else { return }
            document = INIDocument(text: newValue)
            validate()
        }
    }

    /// Whether the text mode is shown.
    var isTextMode: Bool = false

    /// The problems found in the config file.
    private(set) var issues: [ValidationIssue] = []

    /// The changes that are not written yet.
    private(set) var hasUnsavedChanges: Bool = false

    /// The previous versions of the config file, for the undo.
    private var history: [INIDocument] = []

    /// The main config file of Mackeep, where the name of the application goes.
    private var mainConfig: MainConfig?

    /// The callback called when the config file of the application is saved.
    ///
    /// The list of the applications is read again, the files of the
    /// application are shown in the details.
    private var onSave: (() -> Void)?

    /// The date when the config file was written the last time.
    private var lastModification: Date?

    /// Create the editor.
    ///
    /// - Parameters:
    ///   - appName: The identifier of the application.
    ///   - url: The path of the config file.
    ///   - document: The content of the config file.
    ///   - mainConfig: The main config file of Mackeep.
    init(
        appName: String,
        url: URL,
        document: INIDocument,
        mainConfig: MainConfig? = nil,
        onSave: (() -> Void)? = nil
    ) {
        self.appName = appName
        self.url = url
        self.document = document
        self.mainConfig = mainConfig
        self.onSave = onSave
        self.lastModification = Self.modificationDate(of: url)
    }

    /// The name of the application, for the title of the window.
    var title: String {
        displayName.isEmpty ? appName : displayName
    }

    /// Add a path to the application.
    ///
    /// The path is relative to the home or to the XDG config home, an
    /// absolute path is made relative.
    ///
    /// - Parameters:
    ///   - path: The path of the file or of the folder.
    ///   - isXDG: Whether the path is an XDG one.
    func addPath(_ path: String, isXDG: Bool) {
        let relative: String = EditorPath.corrected(path, isXDG: isXDG, allowExternalPaths: true)
        guard !relative.isEmpty else { return }

        var paths: [EditorPath] = isXDG ? xdgPaths : self.paths
        guard !paths.contains(where: { $0.path == relative }) else {
            issues.append(
                ValidationIssue(
                    severity: .warning,
                    message: L10n.string("editor.validation.duplicate", relative)
                )
            )
            return
        }
        paths.append(EditorPath(path: relative, isXDG: isXDG))
        if isXDG {
            xdgPaths = paths
        } else {
            self.paths = paths
        }
        validate()
    }

    /// Add a path to the application.
    ///
    /// - Parameter path: The path that is added.
    func addPath(_ path: EditorPath) {
        remember()
        addPath(path.path, isXDG: path.isXDG)
    }

    /// Add an exclusion rule to the application.
    ///
    /// The rule is relative to the home or to the XDG config home, an
    /// absolute path is made relative.
    ///
    /// - Parameter path: The path that is excluded.
    func addExclude(_ path: EditorPath) {
        remember()
        let rule: String = EditorPath.corrected(path.path, isXDG: path.isXDG)
        guard !rule.isEmpty else { return }
        var patterns: [String] = path.isXDG ? xdgExcludes : excludes
        guard !patterns.contains(rule) else { return }
        patterns.append(rule)
        setExcludes(patterns, isXDG: path.isXDG)
    }

    /// Remove a path of the application.
    ///
    /// - Parameter path: The path.
    func removePath(_ path: EditorPath) {
        if path.isXDG {
            xdgPaths = xdgPaths.filter { $0 != path }
        } else {
            paths = paths.filter { $0 != path }
        }
        validate()
    }

    /// Set the exclusion rules of the application.
    ///
    /// - Parameters:
    ///   - patterns: The rules.
    ///   - isXDG: Whether the rules are the XDG ones.
    func setExcludes(_ patterns: [String], isXDG: Bool) {
        if isXDG {
            xdgExcludes = patterns
        } else {
            excludes = patterns
        }
        validate()
    }

    /// Undo the last change.
    func undo() {
        guard let previous: INIDocument = history.popLast() else { return }
        document = previous
        validate()
    }

    /// Can the last change be undone.
    var canUndo: Bool { !history.isEmpty }

    /// Remember the current state, before a change.
    func remember() {
        history.append(document)
        if history.count > 50 { history.removeFirst() }
        hasUnsavedChanges = true
    }

    /// Read the latest shared policy when settings changed in another window.
    private var allowsExternalPaths: Bool {
        guard let mainConfig else { return false }
        return (try? MainConfig.load(from: mainConfig.url))?.allowExternalPaths
            ?? mainConfig.allowExternalPaths
    }

    /// Check the config file of the application.
    func validate() {
        var issues: [ValidationIssue] = []

        if displayName.trimmingCharacters(in: .whitespaces).isEmpty {
            issues.append(
                ValidationIssue(
                    severity: .error,
                    message: L10n.string("editor.validation.name")
                )
            )
        }

        let allPaths: [EditorPath] = paths + xdgPaths
        var seen: Set<String> = []
        for path: EditorPath in allPaths {
            if !seen.insert(path.path).inserted {
                issues.append(
                    ValidationIssue(
                        severity: .error,
                        message: L10n.string("editor.validation.duplicate", path.path)
                    )
                )
            }
            if !allowsExternalPaths,
               path.path.hasPrefix("/") || path.path.split(separator: "/").contains("..") {
                issues.append(
                    ValidationIssue(
                        severity: .error,
                        message: L10n.string("editor.validation.absolute", path.path)
                    )
                )
            }
        }

        // The rules of the exclusions are relative to the home directory, or
        // to the XDG config home.
        for (patterns, isXDG) in [(excludes, false), (xdgExcludes, true)] {
            for pattern: String in patterns {
                if !pattern.contains("*") && !pattern.contains("?") {
                    let url: URL = EditorPath.absoluteURL(of: pattern, isXDG: isXDG)
                    if !FileManager.default.fileExists(atPath: url.path) {
                        issues.append(
                            ValidationIssue(
                                severity: .warning,
                                message: L10n.string(
                                    "editor.validation.missing",
                                    pattern
                                )
                            )
                        )
                    }
                }
            }
        }

        self.issues = issues
    }

    /// Whether the config file can be saved.
    var canSave: Bool {
        !issues.contains { $0.severity == .error }
    }

    /// Write the config file.
    ///
    /// The name of the application goes to the main config file of Mackeep when
    /// only the checked applications are synced.
    func save() throws {
        guard canSave else { return }

        try INIFile.save(document, to: url)
        lastModification = Self.modificationDate(of: url)
        hasUnsavedChanges = false
        history.removeAll()

        // The application is added to the applications to sync
        if let mainConfig {
            var names: Set<String> = Set(mainConfig.appsToSync)
            names.insert(appName)
            var ignored: Set<String> = Set(mainConfig.appsToIgnore)
            ignored.remove(appName)
            mainConfig.setSyncedApplications(Array(names), ignored: Array(ignored))
            try mainConfig.save()
        }

        // The list of the applications is read again, the new files of the
        // application are shown in the details
        onSave?()
    }

    /// Whether the config file was changed by something else.
    func hasChangedOutside() -> Bool {
        guard let last: Date = lastModification else { return false }
        guard let current: Date = Self.modificationDate(of: url) else { return false }
        return current > last
    }

    /// Read the config file again.
    func reload() throws {
        document = try INIFile.load(from: url)
        lastModification = Self.modificationDate(of: url)
        hasUnsavedChanges = false
        history.removeAll()
        validate()
    }

    /// The date when a file was written the last time.
    ///
    /// - Parameter url: The path of the file.
    /// - Returns: The date, nil when the file does not exist.
    static func modificationDate(of url: URL) -> Date? {
        let attributes: [FileAttributeKey: Any] = (try? FileManager.default
            .attributesOfItem(atPath: url.path)) ?? [:]
        return attributes[.modificationDate] as? Date
    }
}

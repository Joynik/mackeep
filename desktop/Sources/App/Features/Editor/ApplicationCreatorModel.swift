import Foundation

/// The model of the creation of an application.
@Observable
@MainActor
final class ApplicationCreatorModel {
    /// The identifier of the application.
    var name: String = ""

    /// The name of the application.
    var displayName: String = ""

    /// The template of the application.
    var template: ApplicationTemplate = .empty

    /// The problems of the creation.
    private(set) var issues: [ValidationIssue] = []

    /// The directory where the config files of the user are.
    let directory: URL

    /// The application that is copied, when the creation is a copy.
    let source: MackeepApplication?

    /// Create the model.
    ///
    /// - Parameters:
    ///   - directory: The directory where the config files of the user are.
    ///   - source: The application that is copied, when the creation is a
    ///     copy of an existing application.
    init(directory: URL, source: MackeepApplication? = nil) {
        self.directory = directory
        self.source = source
    }

    /// Whether the application can be created.
    var canCreate: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && issues.allSatisfy { $0.severity != .error }
    }

    /// Check what the user wrote.
    func validate(existing: Set<String>) {
        var issues: [ValidationIssue] = []

        let identifier: String = name.trimmingCharacters(in: .whitespaces)
        if identifier.isEmpty {
            issues.append(
                ValidationIssue(
                    severity: .error,
                    message: L10n.string("editor.validation.identifier")
                )
            )
        } else if identifier.contains("/") {
            issues.append(
                ValidationIssue(
                    severity: .error,
                    message: L10n.string("editor.validation.identifier")
                )
            )
        } else if existing.contains(identifier) {
            issues.append(
                ValidationIssue(
                    severity: .error,
                    message: L10n.string("editor.validation.exists", identifier)
                )
            )
        }

        self.issues = issues
    }

    /// Create the config file of the application.
    ///
    /// When the application is a copy of another one, the config file of
    /// the other one is copied, with the new name.
    ///
    /// - Returns: The identifier of the application.
    @discardableResult
    func create() throws -> String {
        let identifier: String = name.trimmingCharacters(in: .whitespaces)

        if let source {
            try copy(of: source, to: identifier)
            return identifier
        }

        var document: INIDocument = INIDocument()

        document.setValue(
            displayName.isEmpty ? identifier : displayName,
            forKey: "name",
            inSection: "application"
        )
        for section: EditorSection in template.sections where section != .application {
            document.ensureSection(section.rawValue)
        }

        let url: URL = directory.appendingPathComponent("\(identifier).cfg")
        try INIFile.save(document, to: url)
        return identifier
    }

    /// Copy the config file of an application.
    ///
    /// - Parameters:
    ///   - source: The application that is copied.
    ///   - identifier: The identifier of the copy.
    private func copy(of source: MackeepApplication, to identifier: String) throws {
        var document: INIDocument = try INIFile.load(
            from: URL(fileURLWithPath: source.cfgPath)
        )
        document.setValue(
            displayName.isEmpty ? identifier : displayName,
            forKey: "name",
            inSection: "application"
        )

        let url: URL = directory.appendingPathComponent("\(identifier).cfg")
        try INIFile.save(document, to: url)
    }
}

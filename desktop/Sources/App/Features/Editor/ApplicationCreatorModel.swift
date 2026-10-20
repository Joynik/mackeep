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

    /// Create the model.
    ///
    /// - Parameter directory: The directory where the config files of the user
    ///   are.
    init(directory: URL) {
        self.directory = directory
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
    /// - Returns: The identifier of the application.
    @discardableResult
    func create() throws -> String {
        let identifier: String = name.trimmingCharacters(in: .whitespaces)
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
}

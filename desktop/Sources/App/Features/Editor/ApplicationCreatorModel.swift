import Foundation

/// The model of the creation of an application.
@Observable
@MainActor
final class ApplicationCreatorModel: Identifiable {
    /// The identifier of the model.
    let id: UUID = UUID()

    /// The identifier of the application.
    ///
    /// It holds the lowercase Latin letters, the digits, the dash and the
    /// underscore only. The uppercase letters are lowered as they are typed.
    var name: String {
        get { identifier }
        set { identifier = ApplicationCreatorModel.clean(name: newValue) }
    }

    /// The identifier, as it is written.
    private var identifier: String = ""

    /// The name of the application.
    var displayName: String = ""

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

    /// Clean an identifier.
    ///
    /// Only the lowercase Latin letters, the digits, the dash and the
    /// underscore are kept, the uppercase letters are lowered.
    ///
    /// - Parameter name: The identifier that is written.
    /// - Returns: The identifier, cleaned.
    static func clean(name: String) -> String {
        let lowered: String = name.lowercased()
        return String(
            lowered.filter { character in
                character.isASCII && (
                    character.isLetter
                        || character.isNumber
                        || character == "-"
                        || character == "_"
                )
            }
        )
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
        guard canCreate else { throw CocoaError(.fileWriteInvalidFileName) }
        let identifier: String = name.trimmingCharacters(in: .whitespaces)

        var document =
            try source.map { try INIFile.load(from: URL(fileURLWithPath: $0.cfgPath)) }
            ?? INIDocument()
        document.setValue(
            displayName.isEmpty ? identifier : displayName,
            forKey: "name", inSection: "application")
        if source == nil { document.ensureSection(EditorSection.configurationFiles.rawValue) }
        try INIFile.save(
            document, to: directory.appendingPathComponent("\(identifier).cfg"),
            backup: false, replaceExisting: false)
        return identifier
    }
}

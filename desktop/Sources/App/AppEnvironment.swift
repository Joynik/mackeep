import Foundation
import SwiftUI

/// The state of the application, shared by all its windows.
@Observable
@MainActor
final class AppEnvironment {
    /// The language of the interface.
    var language: AppLanguage = .system

    /// The appearance of the interface.
    var appearance: AppAppearance = .system

    /// The path of the `mackeep-cli` binary.
    var mackeepPath: String = ""

    /// The version of the `mackeep-cli` binary, when it is known.
    var mackeepVersion: String = ""

    /// What the `mackeep-cli` binary can do.
    var capabilities: MackeepCapabilities?

    /// The error shown to the user, when there is one.
    var presentedError: AppError?

    /// The model of the list of the applications.
    let applications: ApplicationsModel

    /// The model of the backup section.
    let backup: BackupModel


    /// The command line tool of Mackeep.
    private let command: MackeepCommand?

    init() {
        let path: String? = MackeepDiscovery.find()
        self.command = path.map { MackeepCommand(path: $0) }
        self.applications = ApplicationsModel(command: command)
        self.backup = BackupModel(command: command)

        guard let path else { return }
        mackeepPath = path

        // The capabilities of the tool are checked out of the main thread,
        // the window must show up right away.
        Task { [weak self] in
            let capabilities: MackeepCapabilities = await Task.detached {
                MackeepCommand(path: path).capabilities()
            }.value
            self?.capabilities = capabilities
            self?.mackeepVersion = capabilities.version
        }
    }

    /// Whether the tool of Mackeep is recent enough for the application.
    var isToolSupported: Bool { capabilities?.isSupported ?? false }

    /// The model of the editor of an application.
    ///
    /// - Parameter appName: The identifier of the application.
    /// - Returns: The model, nil when the application is not known.
    func editor(for appName: String) -> ApplicationEditorModel? {
        applications.editor(for: appName)
    }

    /// The directory where the config files of the user are.
    var customAppsDirectory: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".mackeep")
    }
}

/// The languages of the interface.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case russian
    case english

    var id: String { rawValue }

    /// The locale of the language, nil for the language of the system.
    var locale: Locale? {
        switch self {
        case .system: nil
        case .russian: Locale(identifier: "ru")
        case .english: Locale(identifier: "en")
        }
    }
}

/// The appearances of the interface.
enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    /// The color scheme of the appearance, nil for the one of the system.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// An error shown to the user.
struct AppError: Identifiable, Equatable {
    /// The identifier of the error.
    let id = UUID()

    /// The title of the error.
    let title: String

    /// The message of the error.
    let message: String
}

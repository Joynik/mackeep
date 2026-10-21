import Foundation
import SwiftUI

/// The state of the application, shared by all its windows.
@Observable
@MainActor
final class AppEnvironment {
    /// The language of the interface.
    ///
    /// The language of the user is kept between the runs, the language of
    /// the system is used when nothing is chosen.
    var language: AppLanguage {
        get {
            guard let raw: String = UserDefaults.standard.string(forKey: "language") else {
                return .system
            }
            return AppLanguage(rawValue: raw) ?? .system
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "language")
            L10n.language = newValue
            NotificationCenter.default.post(
                name: .mackeepLanguageDidChange,
                object: nil
            )
        }
    }

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

    /// The model of the settings.
    let settings: SettingsModel

    /// Whether the wizard of the first launch was shown.
    var hasSeenOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: "hasSeenOnboarding") }
        set { UserDefaults.standard.set(newValue, forKey: "hasSeenOnboarding") }
    }

    /// The command line tool of Mackeep.
    private let command: MackeepCommand?

    init() {
        let path: String? = MackeepDiscovery.find()
        self.command = path.map { MackeepCommand(path: $0) }
        self.applications = ApplicationsModel(command: command)
        self.backup = BackupModel(command: command)
        self.settings = SettingsModel(command: command, capabilities: nil)

        // The strings are read in the language of the user
        L10n.language = language

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
            self?.settings.capabilities = capabilities
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
    case system = "system"
    case russian = "ru"
    case english = "en"
    case spanish = "es"
    case german = "de"
    case french = "fr"
    case italian = "it"
    case portuguese = "pt-BR"
    case japanese = "ja"
    case korean = "ko"
    case chinese = "zh-Hans"

    var id: String { rawValue }

    /// The locale of the language, nil for the language of the system.
    var locale: Locale? {
        switch self {
        case .system: nil
        default: Locale(identifier: rawValue)
        }
    }

    /// The locale of the language, the locale of the system for the system.
    var resolvedLocale: Locale {
        locale ?? Locale.current
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

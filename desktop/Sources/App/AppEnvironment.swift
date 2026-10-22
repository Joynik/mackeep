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
    var language: AppLanguage = .system {
        didSet {
            preferences.set(language.rawValue, forKey: "language")
            L10n.language = language
            NotificationCenter.default.post(
                name: .mackeepLanguageDidChange,
                object: nil
            )
        }
    }

    /// The appearance of the interface.
    ///
    /// The choice of the user is kept between the runs, the appearance of
    /// the system is used when nothing is chosen.
    var appearance: AppAppearance = .system {
        didSet {
            preferences.set(appearance.rawValue, forKey: "appearance")
        }
    }

    /// The model of the list of the applications.
    let applications: ApplicationsModel

    /// The model of the backup section.
    let backup: BackupModel

    /// The model of the settings.
    let settings: SettingsModel

    /// Whether the wizard of the first launch was shown.
    var hasSeenOnboarding: Bool {
        get { preferences.bool(forKey: "hasSeenOnboarding") }
        set { preferences.set(newValue, forKey: "hasSeenOnboarding") }
    }

    private let preferences: UserDefaults

    init(
        command injected: MackeepCommand? = nil, defaults: UserDefaults? = nil,
        discover: Bool = true
    ) {
        let testing = EditorPath.isTesting
        let preferences =
            defaults
            ?? (testing
                ? UserDefaults(
                    suiteName:
                        "com.joynik.mackeep.tests.\(ProcessInfo.processInfo.processIdentifier)")!
                : .standard)
        self.preferences = preferences
        if testing { preferences.set(true, forKey: "hasSeenOnboarding") }
        let testPath = EditorPath.testValue("MACKEEP_TEST_CLI")
        let path =
            injected?.path ?? (testing ? testPath : (discover ? MackeepDiscovery.find() : nil))
        let command = injected ?? path.map { MackeepCommand(path: $0) }
        let applications = ApplicationsModel(command: command)
        self.applications = applications
        self.backup = BackupModel(
            command: command, prepare: { try await applications.flushSelection() })
        self.settings = SettingsModel(command: command, capabilities: nil)

        // The choices of the user are kept between the runs
        language = Self.savedLanguage(in: preferences)
        appearance = Self.savedAppearance(in: preferences)

        // The strings are read in the language of the user
        L10n.language = language

        guard let path else { return }

        // The capabilities of the tool are checked out of the main thread,
        // the window must show up right away.
        Task { [weak self] in
            let capabilities: MackeepCapabilities = await Task.detached {
                (injected ?? MackeepCommand(path: path)).capabilities()
            }.value
            self?.settings.capabilities = capabilities
        }
    }

    /// The language that was chosen the last time.
    private static func savedLanguage(in preferences: UserDefaults) -> AppLanguage {
        guard let raw: String = preferences.string(forKey: "language") else {
            return .system
        }
        return AppLanguage(rawValue: raw) ?? .system
    }

    /// The appearance that was chosen the last time.
    private static func savedAppearance(in preferences: UserDefaults) -> AppAppearance {
        guard let raw: String = preferences.string(forKey: "appearance") else {
            return .system
        }
        return AppAppearance(rawValue: raw) ?? .system
    }

    /// The model of the editor of an application.
    ///
    /// - Parameter appName: The identifier of the application.
    /// - Returns: The model, nil when the application is not known.
    func editor(for appName: String) -> ApplicationEditorModel? {
        applications.editor(for: appName)
    }


}

/// The languages of the interface.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system = "system"
    case russian = "ru"
    case english = "en"
    case ukrainian = "uk"
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

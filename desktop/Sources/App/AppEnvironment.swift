import Foundation
import SwiftUI

/// The state of the application, shared by all its windows.
@Observable
final class AppEnvironment {
    /// The language of the interface.
    var language: AppLanguage = .system

    /// The appearance of the interface.
    var appearance: AppAppearance = .system

    /// The path of the `mackeep-cli` binary.
    var mackeepPath: String = ""

    /// The version of the `mackeep-cli` binary, when it is known.
    var mackeepVersion: String = ""

    /// The error shown to the user, when there is one.
    var presentedError: AppError?

    init() {}
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

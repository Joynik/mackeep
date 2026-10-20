import Foundation
import SwiftUI

/// The strings of the interface.
///
/// The strings are looked up in the bundle of the chosen language, so the
/// language can be changed without restarting the application. The menus of
/// the system do not follow the environment of SwiftUI, they are updated
/// with the notification of `LanguageManager`.
enum L10n {
    /// The bundle of the chosen language.
    private static var currentBundle: Bundle = .main

    /// The language of the interface.
    static var language: AppLanguage = .system {
        didSet {
            currentBundle = Self.bundle(for: language)
        }
    }

    /// Get the string of a key.
    ///
    /// - Parameters:
    ///   - key: The key of the string.
    ///   - arguments: The arguments of the format of the string.
    /// - Returns: The string, the key itself when it is missing.
    static func string(_ key: String, _ arguments: CVarArg...) -> String {
        let value: String = currentBundle.localizedString(
            forKey: key,
            value: key,
            table: nil
        )
        guard !arguments.isEmpty else { return value }
        return String(format: value, arguments: arguments)
    }

    /// Get the bundle of a language.
    ///
    /// - Parameter language: The language.
    /// - Returns: The bundle of the language, the main one when the language
    ///   is not available.
    static func bundle(for language: AppLanguage) -> Bundle {
        guard let identifier = language.locale?.identifier else {
            return .main
        }
        guard
            let path = Bundle.main.path(
                forResource: identifier,
                ofType: "lproj"
            ),
            let bundle = Bundle(path: path)
        else {
            return .main
        }
        return bundle
    }
}

/// The manager of the language of the interface.
@Observable
final class LanguageManager {
    /// The language of the interface.
    var language: AppLanguage {
        didSet {
            guard language != oldValue else { return }
            L10n.language = language
            NotificationCenter.default.post(
                name: .mackeepLanguageDidChange,
                object: nil
            )
        }
    }

    init(language: AppLanguage = .system) {
        self.language = language
        L10n.language = language
    }
}

extension Notification.Name {
    /// The notification sent when the language of the interface changes.
    static let mackeepLanguageDidChange = Notification.Name(
        "com.joynik.mackeep.languageDidChange"
    )
}

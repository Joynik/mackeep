import Foundation
import SwiftUI

/// The strings of the interface.
///
/// The strings are looked up in the bundle of the chosen language, so the
/// language can be changed without restarting the application. The menus of
/// the system do not follow the environment of SwiftUI, they are updated
/// with the notification of the change of the language.
@Observable
final class L10n {
    /// The strings of the interface, they are shared by the windows.
    static let shared = L10n()

    /// The bundle of the chosen language.
    ///
    /// It is observed, so the views are drawn again when the language
    /// changes.
    private(set) var currentBundle: Bundle = .main

    /// The language of the interface.
    var language: AppLanguage = .system {
        didSet {
            currentBundle = Self.bundle(for: language)
        }
    }

    /// The language of the interface.
    static var language: AppLanguage {
        get { shared.language }
        set { shared.language = newValue }
    }

    /// Get the string of a key.
    ///
    /// - Parameters:
    ///   - key: The key of the string.
    ///   - arguments: The arguments of the format of the string.
    /// - Returns: The string, the key itself when it is missing.
    static func string(_ key: String, _ arguments: CVarArg...) -> String {
        let value: String = shared.currentBundle.localizedString(
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

extension Notification.Name {
    /// The notification sent when the language of the interface changes.
    static let mackeepLanguageDidChange = Notification.Name(
        "com.joynik.mackeep.languageDidChange"
    )
}

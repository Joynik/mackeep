import XCTest

@testable import MackeepDesktop

/// The catalog of the strings.
struct StringCatalog: Decodable {
    /// The strings of the catalog.
    struct Entry: Decodable {
        /// A translation of a string.
        struct Localization: Decodable {
            /// The translation itself.
            struct Unit: Decodable {
                /// The text of the translation.
                let value: String
            }

            /// The translation.
            let stringUnit: Unit
        }

        /// The translations of the string, by language.
        let localizations: [String: Localization]
    }

    /// The strings of the catalog.
    let strings: [String: Entry]
}

/// The tests of the localization.
final class LocalizationTests: XCTestCase {
    /// The directory of the sources of the application.
    static var sources: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Unit
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // desktop
            .appendingPathComponent("Sources")
            .appendingPathComponent("App")
    }

    /// The catalog of the strings.
    static var catalog: StringCatalog? {
        let url: URL = Self.sources
            .appendingPathComponent("Resources")
            .appendingPathComponent("Localizable.xcstrings")
        guard let data: Data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(StringCatalog.self, from: data)
    }

    /// The keys used in the sources.
    static func usedKeys() -> Set<String> {
        var keys: Set<String> = []
        guard
            let enumerator: FileManager.DirectoryEnumerator = FileManager.default
                .enumerator(at: Self.sources, includingPropertiesForKeys: nil),
            let expression: NSRegularExpression = try? NSRegularExpression(
                pattern: "L10n\\.string\\(\"([^\"]+)\""
            )
        else {
            return keys
        }
        for case let file as URL in enumerator where file.pathExtension == "swift" {
            guard let text: String = try? String(contentsOf: file, encoding: .utf8) else {
                continue
            }
            let range: NSRange = NSRange(text.startIndex..., in: text)
            for match: NSTextCheckingResult in expression.matches(
                in: text,
                range: range
            ) {
                guard let keyRange: Range = Range(match.range(at: 1), in: text) else {
                    continue
                }
                keys.insert(String(text[keyRange]))
            }
        }
        return keys
    }

    func testEveryKeyIsInTheCatalog() throws {
        let catalog: StringCatalog = try XCTUnwrap(Self.catalog)

        for key: String in Self.usedKeys() {
            XCTAssertNotNil(catalog.strings[key], "The key \(key) is missing")
        }
    }

    func testEveryKeyIsTranslated() throws {
        let catalog: StringCatalog = try XCTUnwrap(Self.catalog)

        for (key, entry) in catalog.strings {
            for language: String in ["en", "ru"] {
                let localization: StringCatalog.Entry.Localization? = entry
                    .localizations[language]
                let text: String = localization?.stringUnit.value ?? ""
                XCTAssertFalse(
                    text.isEmpty,
                    "The key \(key) has no \(language) translation"
                )
                XCTAssertNotEqual(
                    text,
                    key,
                    "The key \(key) is not translated in \(language)"
                )
            }
        }
    }

    func testTheLanguageIsLookedUpInItsBundle() {
        L10n.language = .russian
        defer { L10n.language = .system }

        XCTAssertEqual(L10n.string("section.applications.title"), "Приложения")
        XCTAssertEqual(L10n.string("section.backup.title"), "Бэкап")
        XCTAssertEqual(L10n.string("section.settings.title"), "Настройки")
    }
}

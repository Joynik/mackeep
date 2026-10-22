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
    static var catalog: StringCatalog {
        get throws {
            let url = Self.sources.appendingPathComponent("Resources/Localizable.xcstrings")
            return try JSONDecoder().decode(StringCatalog.self, from: Data(contentsOf: url))
        }
    }

    /// Read literal arguments, including multiline and conditional localization calls.
    static func usedKeys() throws -> Set<String> {
        var enumerationError: Error?
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(
            at: Self.sources, includingPropertiesForKeys: nil,
            errorHandler: { _, error in enumerationError = error; return false }))
        let call = try NSRegularExpression(pattern: #"L10n\.string\(([^)]*)\)"#)
        let literal = try NSRegularExpression(pattern: #""([A-Za-z][A-Za-z0-9_]*\.[A-Za-z0-9_.]+)""#)
        var keys: Set<String> = []
        for case let file as URL in enumerator where file.pathExtension == "swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            for match in call.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                let arguments = String(text[try XCTUnwrap(Range(match.range(at: 1), in: text))])
                for key in literal.matches(in: arguments, range: NSRange(arguments.startIndex..., in: arguments)) {
                    keys.insert(String(arguments[try XCTUnwrap(Range(key.range(at: 1), in: arguments))]))
                }
            }
        }
        if let enumerationError { throw enumerationError }
        // Settings passes these label keys through its storageFieldLabel helper.
        keys.formUnion(["settings.storage.available", "settings.storage.path",
                        "settings.storage.directory", "settings.storage.resolved"])
        return keys
    }

    func testEveryKeyIsInTheCatalog() throws {
        let catalog: StringCatalog = try Self.catalog

        let keys = try Self.usedKeys()
        XCTAssertTrue(keys.contains("section.applications.title"))
        XCTAssertTrue(keys.contains("backup.action.copied"))
        for key in keys {
            XCTAssertNotNil(catalog.strings[key], "The key \(key) is missing")
        }
    }

    /// The languages of the interface, with the key of their name.
    static let languages: [(code: String, key: String)] = [
        ("en", "settings.language.english"),
        ("ru", "settings.language.russian"),
        ("uk", "settings.language.ukrainian"),
        ("es", "settings.language.spanish"),
        ("de", "settings.language.german"),
        ("fr", "settings.language.french"),
        ("it", "settings.language.italian"),
        ("pt-BR", "settings.language.portuguese"),
        ("ja", "settings.language.japanese"),
        ("ko", "settings.language.korean"),
        ("zh-Hans", "settings.language.chinese"),
    ]

    func testEveryKeyIsTranslated() throws {
        let catalog: StringCatalog = try Self.catalog

        for (key, entry) in catalog.strings {
            for language: String in Self.languages.map(\.code) {
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
                let english = try XCTUnwrap(entry.localizations["en"]?.stringUnit.value)
                XCTAssertEqual(try Self.placeholders(text), try Self.placeholders(english),
                               "Format mismatch for \(key) in \(language)")
            }
        }
    }

    func testEveryLanguageIsInThePicker() throws {
        let catalog: StringCatalog = try Self.catalog

        for language: (code: String, key: String) in Self.languages {
            XCTAssertNotNil(
                catalog.strings[language.key]?.localizations[language.code],
                "The language \(language.code) has no name"
            )
        }
    }

    func testTheLanguageIsLookedUpInItsBundle() {
        L10n.language = .russian
        defer { L10n.language = .system }

        XCTAssertEqual(L10n.string("section.applications.title"), "Приложения")
        XCTAssertEqual(L10n.string("section.backup.title"), "Бэкап и Восстановление")
        XCTAssertEqual(L10n.string("section.settings.title"), "Настройки")
    }

    func testTheLanguageIsChangedAtOnce() {
        L10n.language = .ukrainian
        defer { L10n.language = .system }

        // The strings of the interface
        XCTAssertEqual(L10n.string("section.applications.title"), "Застосунки")
        XCTAssertEqual(L10n.string("section.backup.title"), "Бекап і Відновлення")
        XCTAssertEqual(L10n.string("section.settings.title"), "Налаштування")

        // The names of the tabs
        XCTAssertEqual(SidebarSection.applications.title, "Застосунки")
        XCTAssertEqual(SidebarSection.backup.title, "Бекап і Відновлення")
        XCTAssertEqual(SidebarSection.settings.title, "Налаштування")
    }

    func testTheNameOfTheUkrainianIsInEveryLanguage() throws {
        let catalog: StringCatalog = try Self.catalog
        let entry: StringCatalog.Entry = try XCTUnwrap(
            catalog.strings["settings.language.ukrainian"]
        )
        let name: String = entry.localizations["uk"]?.stringUnit.value ?? ""

        XCTAssertEqual(name, "Українська")
    }

    /// Keep argument positions and types, including repeated or reordered arguments.
    private static func placeholders(_ text: String) throws -> [String] {
        let expression = try NSRegularExpression(
            pattern: #"%(?:([0-9]+)\$)?([-+#0 ]*[0-9]*(?:\.[0-9]+)?(?:hh|ll|[hljztL])?[@diuoxXfFeEgGaAcCsSp])|%%"#)
        var position = 0
        return expression.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            let token = String(text[Range(match.range, in: text)!])
            if token == "%%" { return nil }
            position += 1
            let number = Range(match.range(at: 1), in: text).map { String(text[$0]) } ?? String(position)
            let type = String(text[Range(match.range(at: 2), in: text)!])
            return number + ":" + type
        }.sorted()
    }

    @MainActor
    func testEveryCompiledLanguageContainsTheCatalogAndFormatsResults() throws {
        let catalog = try Self.catalog
        let previous = L10n.language
        defer { L10n.language = previous }
        let languages = AppLanguage.allCases.filter { $0 != .system }
        XCTAssertEqual(Set(languages.map(\.rawValue)), Set(Self.languages.map(\.code)))
        for language in languages {
            let path = try XCTUnwrap(Bundle.main.path(forResource: language.rawValue, ofType: "lproj"))
            let bundle = try XCTUnwrap(Bundle(path: path))
            for (key, entry) in catalog.strings {
                let expected = try XCTUnwrap(entry.localizations[language.rawValue]?.stringUnit.value)
                XCTAssertEqual(bundle.localizedString(forKey: key, value: "MISSING", table: nil), expected,
                               "Compiled \(language.rawValue) value differs for \(key)")
            }
            L10n.language = language
            let expected = try XCTUnwrap(catalog.strings["backup.summary"]?
                .localizations[language.rawValue]?.stringUnit.value)
            XCTAssertEqual(L10n.string("backup.summary", 9, 4, "42 MB"),
                           String(format: expected, 9, 4, "42 MB"))
            let translations = Set(catalog.strings.values.compactMap {
                $0.localizations[language.rawValue]?.stringUnit.value
            })
            let titles = SidebarSection.allCases.map(\.title) + StorageEngine.allCases.map(\.title)
                + BackupModel.PlanFilter.allCases.map(\.title)
            for title in titles { XCTAssertTrue(translations.contains(title), "Untranslated title: \(title)") }
        }
    }
}

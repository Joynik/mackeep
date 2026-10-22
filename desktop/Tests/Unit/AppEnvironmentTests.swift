import XCTest

@testable import MackeepDesktop

/// The tests of the state shared by the windows.
@MainActor
final class AppEnvironmentTests: XCTestCase {
    private var preferences: UserDefaults!
    private var suite: String!
    private var previousLanguage: AppLanguage!
    override func setUpWithError() throws {
        previousLanguage = L10n.language
        suite = "com.joynik.mackeep.test.\(UUID().uuidString)"
        preferences = UserDefaults(suiteName: suite)
    }
    override func tearDownWithError() throws {
        preferences.removePersistentDomain(forName: suite)
        L10n.language = previousLanguage
    }

    func testTheAppearanceIsKeptBetweenTheRuns() {
        let environment: AppEnvironment = AppEnvironment(defaults: preferences, discover: false)

        environment.appearance = .dark

        // The choice is in the preferences
        XCTAssertEqual(preferences.string(forKey: "appearance"), "dark")

        // And it is read again by the next run
        let next: AppEnvironment = AppEnvironment(defaults: preferences, discover: false)
        XCTAssertEqual(next.appearance, .dark)
    }

    func testTheAppearanceOfTheSystemIsUsedByDefault() {
        preferences.removeObject(forKey: "appearance")

        let environment: AppEnvironment = AppEnvironment(defaults: preferences, discover: false)

        XCTAssertEqual(environment.appearance, .system)
    }

    func testTheLanguageIsKeptBetweenTheRuns() {
        let previous: String? = preferences.string(forKey: "language")
        defer {
            if let previous {
                preferences.set(previous, forKey: "language")
            } else {
                preferences.removeObject(forKey: "language")
            }
        }

        let environment: AppEnvironment = AppEnvironment(defaults: preferences, discover: false)
        environment.language = .ukrainian

        XCTAssertEqual(preferences.string(forKey: "language"), "uk")

        let next: AppEnvironment = AppEnvironment(defaults: preferences, discover: false)
        XCTAssertEqual(next.language, .ukrainian)
    }
}

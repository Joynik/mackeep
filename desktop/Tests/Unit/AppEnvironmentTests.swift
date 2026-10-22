import XCTest

@testable import MackeepDesktop

/// The tests of the state shared by the windows.
@MainActor
final class AppEnvironmentTests: XCTestCase {
    /// The value that was in the preferences before the test.
    private var savedAppearance: String?

    override func setUpWithError() throws {
        try super.setUpWithError()
        savedAppearance = UserDefaults.standard.string(forKey: "appearance")
    }

    override func tearDownWithError() throws {
        if let savedAppearance {
            UserDefaults.standard.set(savedAppearance, forKey: "appearance")
        } else {
            UserDefaults.standard.removeObject(forKey: "appearance")
        }

        try super.tearDownWithError()
    }

    func testTheAppearanceIsKeptBetweenTheRuns() {
        let environment: AppEnvironment = AppEnvironment()

        environment.appearance = .dark

        // The choice is in the preferences
        XCTAssertEqual(UserDefaults.standard.string(forKey: "appearance"), "dark")

        // And it is read again by the next run
        let next: AppEnvironment = AppEnvironment()
        XCTAssertEqual(next.appearance, .dark)
    }

    func testTheAppearanceOfTheSystemIsUsedByDefault() {
        UserDefaults.standard.removeObject(forKey: "appearance")

        let environment: AppEnvironment = AppEnvironment()

        XCTAssertEqual(environment.appearance, .system)
    }

    func testTheLanguageIsKeptBetweenTheRuns() {
        let previous: String? = UserDefaults.standard.string(forKey: "language")
        defer {
            if let previous {
                UserDefaults.standard.set(previous, forKey: "language")
            } else {
                UserDefaults.standard.removeObject(forKey: "language")
            }
        }

        let environment: AppEnvironment = AppEnvironment()
        environment.language = .ukrainian

        XCTAssertEqual(UserDefaults.standard.string(forKey: "language"), "uk")

        let next: AppEnvironment = AppEnvironment()
        XCTAssertEqual(next.language, .ukrainian)
    }
}

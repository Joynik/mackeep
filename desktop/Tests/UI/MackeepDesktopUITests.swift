import XCTest

/// The UI tests of the application.
final class MackeepDesktopUITests: XCTestCase {
    private let application = XCUIApplication(bundleIdentifier: "com.joynik.mackeep.testing")
    private var directory: URL!
    private var instance: NSRunningApplication?
    private var window: XCUIElement { application.windows.firstMatch }

    override func setUpWithError() throws {
        // Both the runner and test app need access; the runner's container is private.
        directory = URL(fileURLWithPath: "/private/tmp").appendingPathComponent(
            "mackeep-ui-\(UUID().uuidString)")
        let tool = try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: "mackeep-cli", withExtension: "sh"))
        application.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        application.launchEnvironment = [
            "MACKEEP_TESTING": "1", "MACKEEP_TEST_HOME": directory.path,
            "MACKEEP_TEST_CLI": tool.path,
        ]
    }

    override func tearDownWithError() throws { instance?.terminate() }

    private func startTheApplication() throws {
        var products = Bundle(for: Self.self).bundleURL
        while products.pathComponents.count > 1 && products.lastPathComponent != "Debug" {
            products.deleteLastPathComponent()
        }
        let app = products.appendingPathComponent("Mackeep.app")
        guard Bundle(url: app)?.bundleIdentifier == "com.joynik.mackeep.testing" else {
            throw XCTSkip(
                "Build UI tests with MACKEEP_BUNDLE_IDENTIFIER=com.joynik.mackeep.testing")
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.arguments = application.launchArguments
        for (key, value) in application.launchEnvironment.sorted(by: { $0.key < $1.key }) {
            configuration.arguments += ["-" + key, value]
        }
        configuration.environment = application.launchEnvironment
        let launched = expectation(description: "Test application launched")
        var failure: Error?
        NSWorkspace.shared.openApplication(at: app, configuration: configuration) { app, error in
            self.instance = app
            failure = error
            launched.fulfill()
        }
        wait(for: [launched], timeout: 20)
        if let failure { throw failure }
        XCTAssertTrue(window.waitForExistence(timeout: 20))
        waitForTheApplication()
    }

    private func waitForTheApplication() {
        instance?.activate(options: [.activateAllWindows])
        XCTAssertTrue(application.wait(for: .runningForeground, timeout: 10))
    }

    func testTheWindowOpens() throws {
        try startTheApplication()

        XCTAssertTrue(window.waitForExistence(timeout: 30))
    }

    func testTheLibraryAndTheSettings() throws {
        try startTheApplication()

        XCTAssertTrue(window.waitForExistence(timeout: 30))

        // The library is opened with the button of the toolbar
        let button: XCUIElement = window.buttons
            .matching(identifier: "applications.library.button")
            .firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 20))
        waitForTheApplication()
        button.click()

        // The applications of Mackeep are in the library
        let title: XCUIElementQuery = window.descendants(
            matching: .any
        ).matching(identifier: "applications.library.title")
        XCTAssertTrue(title.element(boundBy: 0).waitForExistence(timeout: 20))

        // The library is closed with the button
        let close: XCUIElement = window.buttons
            .matching(identifier: "applications.library.close")
            .firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 20))
        waitForTheApplication()
        close.click()

        XCTAssertTrue(title.element(boundBy: 0).waitForNonExistence(timeout: 20))

        // The settings are in the sidebar
        let item: XCUIElement = window.staticTexts
            .matching(
                NSPredicate(
                    format: "value == %@ OR label == %@ OR value == %@ OR label == %@",
                    "Настройки",
                    "Настройки",
                    "Settings",
                    "Settings"
                )
            )
            .firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 20))

        // The click needs the application to be in front
        waitForTheApplication()
        item.click()

        // The folder of the applications of the user is shown
        let folders: XCUIElementQuery = window.staticTexts
            .matching(identifier: "settings.customAppsDir")
        XCTAssertTrue(folders.element(boundBy: 0).waitForExistence(timeout: 20))

        // It is shown only once, the XDG location is not shown
        XCTAssertEqual(folders.count, 1)
        XCTAssertEqual(folders.element(boundBy: 0).value as? String, directory.appendingPathComponent(".mackeep").path)
    }
    func testCreatingAnApplicationOpensItsEditor() throws {
        try startTheApplication()
        let create = window.buttons["applications.create.button"]
        XCTAssertTrue(create.waitForExistence(timeout: 20))
        waitForTheApplication()
        create.click()
        let identifier = application.textFields["editor.create.identifier"]
        guard identifier.waitForExistence(timeout: 10) else {
            let errors = application.sheets.staticTexts.allElementsBoundByIndex.map {
                $0.value as? String ?? $0.label
            }
            XCTFail(errors.joined(separator: "\n") + "\n" + application.debugDescription)
            return
        }
        identifier.click()
        identifier.typeText("new-app")
        XCTAssertEqual(identifier.value as? String, "new-app")
        let name = application.textFields["editor.create.name"]
        name.click()
        name.typeText("New App")
        XCTAssertEqual(name.value as? String, "New App")
        application.buttons["editor.create.confirm"].click()
        XCTAssertTrue(application.windows["New App"].waitForExistence(timeout: 20))
    }

}

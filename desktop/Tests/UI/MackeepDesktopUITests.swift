import XCTest

/// The UI tests of the application.
final class MackeepDesktopUITests: XCTestCase {
    /// The identifier of the application.
    private static let identifier: String = "com.joynik.mackeep"

    /// The application of Mackeep.
    private var application: XCUIApplication {
        XCUIApplication(bundleIdentifier: Self.identifier)
    }

    /// The window of the application.
    private var window: XCUIElement {
        application.windows.firstMatch
    }

    override func setUpWithError() throws {
        try super.setUpWithError()

        // A running copy of the application takes the windows for itself,
        // so the new copy stays without a window
        stopTheApplication()
    }

    override func tearDownWithError() throws {
        stopTheApplication()

        try super.tearDownWithError()
    }

    /// Start the application.
    ///
    /// The application is started through the LaunchServices, because a
    /// application, that is started directly, does not get a window.
    private func startTheApplication() throws {
        let process: Process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", Self.applicationPath().path]
        try process.run()
        process.waitUntilExit()

        // The application comes to the front when it starts
        application.activate()
    }

    /// Stop every copy of the application and wait for them.
    private func stopTheApplication() {
        let running: [NSRunningApplication] = NSRunningApplication
            .runningApplications(withBundleIdentifier: Self.identifier)

        for copy: NSRunningApplication in running {
            copy.terminate()
        }

        let deadline: Date = Date().addingTimeInterval(10)
        while Date() < deadline {
            let copies: [NSRunningApplication] = NSRunningApplication
                .runningApplications(withBundleIdentifier: Self.identifier)
            if copies.isEmpty { return }

            usleep(200_000)
        }

        // The polite request was not enough
        for copy: NSRunningApplication in NSRunningApplication
            .runningApplications(withBundleIdentifier: Self.identifier)
        {
            copy.forceTerminate()
        }
    }

    /// The path of the built application.
    private static func applicationPath() -> URL {
        var folder: URL = Bundle(for: MackeepDesktopUITests.self).bundleURL
        while folder.pathComponents.count > 1,
              folder.lastPathComponent != "Debug"
        {
            folder = folder.deletingLastPathComponent()
        }

        return folder.appendingPathComponent("Mackeep.app")
    }

    func testTheWindowOpens() throws {
        try startTheApplication()

        XCTAssertTrue(window.waitForExistence(timeout: 30))
    }

    func testTheApplicationsAreListed() throws {
        try startTheApplication()

        XCTAssertTrue(window.waitForExistence(timeout: 30))

        // The applications of Mackeep are listed
        let list: XCUIElement = window.outlines.element(boundBy: 1)
        XCTAssertTrue(list.waitForExistence(timeout: 20))

        // The applications of the database of Mackeep are there
        let checkbox: XCUIElement = list.descendants(matching: .checkBox).firstMatch
        XCTAssertTrue(checkbox.waitForExistence(timeout: 20))
        XCTAssertTrue(
            checkbox.label.contains("Синхронизировать")
                || checkbox.label.contains("Sync")
        )
    }

    func testTheSettingsShowOneFolderForTheApplicationsOfTheUser() throws {
        try startTheApplication()

        XCTAssertTrue(window.waitForExistence(timeout: 30))

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
        application.activate()
        item.click()

        // The folder of the applications of the user is shown
        let folders: XCUIElementQuery = window.staticTexts
            .matching(identifier: "settings.customAppsDir")
        XCTAssertTrue(folders.element(boundBy: 0).waitForExistence(timeout: 20))

        // It is shown only once, the XDG location is not shown
        XCTAssertEqual(folders.count, 1)
    }
}

import XCTest

@testable import MackeepDesktop

/// The tests of the creation of an application.
@MainActor
final class ApplicationCreatorModelTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mackeep-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    /// The content of the config file of an application.
    nonisolated static let config: String = """
    # The name of the application
    [application]
    name = Test App

    [configuration_files]
    .testrc
    """

    /// An application of the database.
    private func application(name: String, path: String) -> MackeepApplication {
        MackeepApplication(
            schemaVersion: 1,
            name: name,
            displayName: name.capitalized,
            source: .builtin,
            cfgPath: path,
            files: [],
            xdgFiles: [],
            exclude: [],
            xdgExclude: [],
            error: nil
        )
    }

    func testTheIdentifierIsCleaned() {
        let model: ApplicationCreatorModel = ApplicationCreatorModel(directory: directory)

        model.name = "My App-2_x"

        XCTAssertEqual(model.name, "myapp-2_x")

        model.name = "Привет"
        XCTAssertEqual(model.name, "")
    }

    func testTheApplicationIsCreated() throws {
        let model: ApplicationCreatorModel = ApplicationCreatorModel(directory: directory)
        model.name = "test-app"
        model.displayName = "Test App"

        let identifier: String = try model.create()

        XCTAssertEqual(identifier, "test-app")
        let url: URL = directory.appendingPathComponent("test-app.cfg")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        let document: INIDocument = try INIFile.load(from: url)
        XCTAssertEqual(document.value(forKey: "name", inSection: "application"), "Test App")
    }

    func testTheApplicationIsCopied() throws {
        let source: URL = directory.appendingPathComponent("source.cfg")
        try ApplicationCreatorModelTests.config.write(
            to: source,
            atomically: true,
            encoding: .utf8
        )

        let model: ApplicationCreatorModel = ApplicationCreatorModel(
            directory: directory,
            source: application(name: "test-app", path: source.path)
        )
        model.name = "test-app-copy"
        model.displayName = "Test App (copy)"

        let identifier: String = try model.create()

        XCTAssertEqual(identifier, "test-app-copy")
        let url: URL = directory.appendingPathComponent("test-app-copy.cfg")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        // The config of the source is copied, with the new name
        let document: INIDocument = try INIFile.load(from: url)
        XCTAssertEqual(
            document.value(forKey: "name", inSection: "application"),
            "Test App (copy)"
        )
        XCTAssertEqual(
            document.values(inSection: "configuration_files"),
            [".testrc"]
        )
    }
}

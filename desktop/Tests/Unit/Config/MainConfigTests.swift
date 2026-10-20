import XCTest

@testable import MackeepDesktop

/// The tests of the main config file.
final class MainConfigTests: XCTestCase {
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

    /// Write a config file and return its path.
    private func makeConfig(_ text: String) throws -> URL {
        let url: URL = directory.appendingPathComponent(".mackeep.cfg")
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testTheApplicationsAreRead() throws {
        let url: URL = try makeConfig(
            """
            [storage]
            engine = file_system
            path = /Users/user/dotfiles

            [applications_to_sync]
            vim
            emacs

            [applications_to_ignore]
            slack
            """
        )
        let config: MainConfig = try MainConfig.load(from: url)

        XCTAssertEqual(config.appsToSync, ["vim", "emacs"])
        XCTAssertEqual(config.appsToIgnore, ["slack"])
        XCTAssertEqual(config.storageEngine, "file_system")
        XCTAssertEqual(config.storagePath, "/Users/user/dotfiles")
        XCTAssertNil(config.storageDirectory)
    }

    func testTheIgnoredApplicationsAreWritten() throws {
        let url: URL = try makeConfig("[storage]\nengine = dropbox\n")
        let config: MainConfig = try MainConfig.load(from: url)

        config.setSyncedApplications(["slack"], mode: .allExceptUnchecked)
        try config.save()

        let saved: MainConfig = try MainConfig.load(from: url)
        XCTAssertEqual(saved.appsToIgnore, ["slack"])
        XCTAssertEqual(saved.appsToSync, [])
    }

    func testTheSyncedApplicationsAreWritten() throws {
        let url: URL = try makeConfig(
            "[storage]\nengine = dropbox\n\n[applications_to_ignore]\nslack\n"
        )
        let config: MainConfig = try MainConfig.load(from: url)

        config.setSyncedApplications(["vim"], mode: .onlyChecked)
        try config.save()

        let saved: MainConfig = try MainConfig.load(from: url)
        XCTAssertEqual(saved.appsToSync, ["vim"])
        XCTAssertEqual(saved.appsToIgnore, [])
    }

    func testTheCommentsAreKeptWhenTheFileIsWritten() throws {
        let text: String = """
        # The storage of Mackeep
        [storage]
        engine = dropbox

        # The applications to sync
        [applications_to_sync]
        vim
        """
        let url: URL = try makeConfig(text)
        let config: MainConfig = try MainConfig.load(from: url)

        config.setSyncedApplications(["vim", "emacs"], mode: .onlyChecked)
        try config.save()

        let saved: String = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(saved.contains("# The storage of Mackeep"))
        XCTAssertTrue(saved.contains("# The applications to sync"))
        XCTAssertTrue(saved.contains("emacs"))
    }

    func testTheGlobalExclusionsAreWritten() throws {
        let url: URL = try makeConfig("[storage]\nengine = dropbox\n")
        let config: MainConfig = try MainConfig.load(from: url)

        config.setGlobalExclude(["**/.DS_Store", "*.log"])
        try config.save()

        let saved: MainConfig = try MainConfig.load(from: url)
        XCTAssertEqual(saved.globalExclude, ["**/.DS_Store", "*.log"])
    }

    func testThePreviousVersionIsKept() throws {
        let url: URL = try makeConfig("[storage]\nengine = dropbox\n")
        let config: MainConfig = try MainConfig.load(from: url)
        config.setSyncedApplications(["vim"], mode: .onlyChecked)
        try config.save()

        let backup: URL = url.appendingPathExtension("bak")
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path))
    }
}

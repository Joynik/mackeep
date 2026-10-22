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

    func testTheConfigFileIsCreatedWhenItIsMissing() throws {
        let url: URL = directory.appendingPathComponent(".mackeep.cfg")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))

        let config: MainConfig = try MainConfig.createIfNeeded(at: url)

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(config.storageDirectory, "Mackeep")
    }

    func testTheExistingConfigFileIsKept() throws {
        let url: URL = try makeConfig("[storage]\ndirectory = Other\n")

        let config: MainConfig = try MainConfig.createIfNeeded(at: url)

        XCTAssertEqual(config.storageDirectory, "Other")
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

        config.setSyncedApplications([], ignored: ["slack"])
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

        config.setSyncedApplications(["vim"], ignored: [])
        try config.save()

        let saved: MainConfig = try MainConfig.load(from: url)
        XCTAssertEqual(saved.appsToSync, ["vim"])
        XCTAssertEqual(saved.appsToIgnore, [])
    }

    func testTheApplicationsAreWrittenInAnEmptySection() throws {
        let url: URL = try makeConfig(
            "[storage]\nengine = dropbox\n\n[applications_to_sync]\n\n"
                + "[applications_to_ignore]\nslack\n"
        )
        let config: MainConfig = try MainConfig.load(from: url)

        config.setSyncedApplications(["vim"], ignored: ["slack"])
        try config.save()

        let saved: MainConfig = try MainConfig.load(from: url)
        XCTAssertEqual(saved.appsToSync, ["vim"])
        XCTAssertEqual(saved.appsToIgnore, ["slack"])
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

        config.setSyncedApplications(["vim", "emacs"], ignored: [])
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
        config.setSyncedApplications(["vim"], ignored: [])
        try config.save()

        let backup: URL = url.appendingPathExtension("bak")
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path))
    }
    func testExternalPathsAreDisabledByDefaultAndCanBeEnabled() throws {
        let url = try makeConfig("[storage]\nengine = file_system\n")
        let config = try MainConfig.load(from: url)
        XCTAssertFalse(config.allowExternalPaths)
        config.setAllowExternalPaths(true)
        try config.save()
        XCTAssertTrue(try MainConfig.load(from: url).allowExternalPaths)
    }

    func testSavingSettingsKeepsApplicationsChangedByAnotherModel() throws {
        let url = try makeConfig("[storage]\nengine = file_system\n")
        let settings = try MainConfig.load(from: url)
        let applications = try MainConfig.load(from: url)
        applications.setSyncedApplications(["vim"], ignored: [])
        try applications.save()
        settings.setAllowExternalPaths(true)
        try settings.save()
        let saved = try MainConfig.load(from: url)
        XCTAssertEqual(saved.appsToSync, ["vim"])
        XCTAssertTrue(saved.allowExternalPaths)
    }

}

import XCTest

@testable import MackeepDesktop

/// The tests of the model of the list of the applications.
@MainActor
final class ApplicationsModelTests: XCTestCase {
    /// An application of the database.
    private func application(
        name: String,
        source: MackeepAppSource = .builtin,
        files: [MackeepPath] = [],
        displayName: String? = nil,
        error: String? = nil
    ) -> MackeepApplication {
        MackeepApplication(
            schemaVersion: 1,
            name: name,
            displayName: displayName ?? name.capitalized,
            source: source,
            cfgPath: "/Users/user/.mackeep/\(name).cfg",
            files: files,
            xdgFiles: [],
            exclude: [],
            xdgExclude: [],
            error: error
        )
    }

    /// A model with the given applications and the given config.
    private func model(
        applications: [MackeepApplication],
        sync: [String] = [],
        ignore: [String] = []
    ) -> ApplicationsModel {
        let model: ApplicationsModel = ApplicationsModel(command: nil)
        let document: INIDocument = INIDocument(
            text: """
            [applications_to_sync]
            \(sync.joined(separator: "\n"))

            [applications_to_ignore]
            \(ignore.joined(separator: "\n"))
            """
        )
        let url: URL = URL(fileURLWithPath: "/tmp/.mackeep.cfg")
        model.setConfig(MainConfig(url: url, document: document))
        model.setApplications(applications)
        return model
    }

    func testTheListHoldsTheApplicationsOfTheUserAndTheAddedOnes() {
        let model: ApplicationsModel = model(
            applications: [
                application(name: "vim"),
                application(name: "emacs", source: .custom),
                application(name: "zsh"),
            ],
            sync: ["vim"]
        )

        XCTAssertEqual(
            model.listedApplications.map(\.name),
            ["emacs", "vim"]
        )
    }

    func testTheListIsSortedByDisplayName() {
        let model: ApplicationsModel = model(
            applications: [
                application(name: "b", displayName: "Zulu"),
                application(name: "a", displayName: "Alpha"),
            ],
            sync: ["a", "b"]
        )

        XCTAssertEqual(
            model.visibleApplications.map(\.displayName),
            ["Alpha", "Zulu"]
        )
    }

    func testTheSearchFiltersTheList() {
        let model: ApplicationsModel = model(
            applications: [
                application(name: "vim"),
                application(name: "emacs"),
            ],
            sync: ["vim", "emacs"]
        )
        model.searchText = "vi"

        XCTAssertEqual(model.visibleApplications.map(\.name), ["vim"])

        model.searchText = "VIM"
        XCTAssertEqual(model.visibleApplications.map(\.name), ["vim"])

        model.searchText = "nothing"
        XCTAssertTrue(model.visibleApplications.isEmpty)
    }

    func testTheFilterKeepsTheCustomApplications() {
        let model: ApplicationsModel = model(
            applications: [
                application(name: "vim"),
                application(name: "mine", source: .custom),
            ],
            sync: ["vim"]
        )
        model.filter = .custom

        XCTAssertEqual(model.visibleApplications.map(\.name), ["mine"])
    }

    func testTheFilterKeepsTheApplicationsOfTheLibrary() {
        let model: ApplicationsModel = model(
            applications: [
                application(name: "vim"),
                application(name: "mine", source: .custom),
            ],
            sync: ["vim"]
        )
        model.filter = .library

        XCTAssertEqual(model.visibleApplications.map(\.name), ["vim"])
    }

    func testTheFilterKeepsTheEnabledApplications() {
        let model: ApplicationsModel = model(
            applications: [
                application(name: "vim"),
                application(name: "emacs"),
            ],
            sync: ["vim"],
            ignore: ["emacs"]
        )
        model.filter = .enabled

        XCTAssertEqual(model.visibleApplications.map(\.name), ["vim"])
    }

    func testTheFilterKeepsTheDisabledApplications() {
        let model: ApplicationsModel = model(
            applications: [
                application(name: "vim"),
                application(name: "emacs"),
            ],
            sync: ["vim"],
            ignore: ["emacs"]
        )
        model.filter = .disabled

        XCTAssertEqual(model.visibleApplications.map(\.name), ["emacs"])
    }

    func testTheCheckedApplicationsAreTheOnlyOnesBackedUp() {
        let model: ApplicationsModel = model(
            applications: [
                application(name: "vim"),
                application(name: "emacs"),
            ],
            sync: ["vim"],
            ignore: ["emacs"]
        )

        XCTAssertTrue(model.isEnabled(model.applications[0]))
        XCTAssertFalse(model.isEnabled(model.applications[1]))
    }

    func testTheInstalledApplicationsAreKnown() {
        let model: ApplicationsModel = model(
            applications: [
                application(
                    name: "vim",
                    files: [MackeepPath(path: ".vimrc", exists: true, isDir: false)]
                ),
                application(name: "emacs"),
            ]
        )

        XCTAssertTrue(model.isInstalled(model.applications[0]))
        XCTAssertFalse(model.isInstalled(model.applications[1]))
    }

    func testTheApplicationsOfTheLibraryAreNotInTheList() {
        let model: ApplicationsModel = model(
            applications: [
                application(name: "vim"),
            ]
        )

        XCTAssertFalse(model.isListed(model.applications[0]))
        XCTAssertTrue(model.visibleApplications.isEmpty)
    }

    func testTheApplicationWithAnErrorIsStillInTheList() {
        let reason: String = "Invalid exclusion pattern in /Users/user/.mackeep/vim.cfg: unsupported absolute path: /absolute/path"
        let model: ApplicationsModel = model(
            applications: [
                application(name: "vim", error: reason),
                application(name: "emacs"),
            ],
            sync: ["vim"]
        )

        // The application is still listed, the reason is known
        XCTAssertEqual(model.visibleApplications.count, 1)
        XCTAssertEqual(model.visibleApplications[0].name, "vim")
        XCTAssertEqual(model.visibleApplications[0].error, reason)
    }

    func testTheApplicationOfTheLibraryIsRemovedFromTheList() {
        let model: ApplicationsModel = model(
            applications: [
                application(name: "vim"),
            ],
            sync: ["vim"]
        )

        model.delete(model.applications[0])

        XCTAssertFalse(model.isListed(model.applications[0]))
        XCTAssertTrue(model.visibleApplications.isEmpty)
    }

    func testTheApplicationOfTheLibraryIsAddedToTheList() throws {
        let url: URL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mackeep-tests-\(UUID().uuidString)")
            .appendingPathComponent(".mackeep.cfg")
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        try "[applications_to_sync]\n\n[applications_to_ignore]\n".write(
            to: url,
            atomically: true,
            encoding: .utf8
        )

        let model: ApplicationsModel = ApplicationsModel(command: nil)
        model.setConfig(MainConfig(url: url, document: try INIFile.load(from: url)))
        model.setApplications([application(name: "vim")])

        model.addToTheList(model.applications[0])

        XCTAssertTrue(model.isListed(model.applications[0]))
        XCTAssertTrue(model.isEnabled(model.applications[0]))

        // The config file holds the application
        let saved: MainConfig = try MainConfig.load(from: url)
        XCTAssertEqual(saved.appsToSync, ["vim"])
        XCTAssertEqual(saved.appsToIgnore, [])
    }
}

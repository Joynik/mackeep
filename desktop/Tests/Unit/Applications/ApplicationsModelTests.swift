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
        displayName: String? = nil
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
            xdgExclude: []
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

    func testTheListIsSortedByName() {
        let model: ApplicationsModel = model(
            applications: [
                application(name: "zsh"),
                application(name: "alacritty"),
            ]
        )

        XCTAssertEqual(
            model.visibleApplications.map(\.name),
            ["alacritty", "zsh"]
        )
    }

    func testTheListIsSortedByDisplayName() {
        let model: ApplicationsModel = model(
            applications: [
                application(name: "b", displayName: "Alpha"),
                application(name: "a", displayName: "Zulu"),
            ]
        )
        model.sort = .displayName

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
            ]
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
            ]
        )
        model.filter = .custom

        XCTAssertEqual(model.visibleApplications.map(\.name), ["mine"])
    }

    func testTheFilterKeepsTheInstalledApplications() {
        let model: ApplicationsModel = model(
            applications: [
                application(
                    name: "vim",
                    files: [MackeepPath(path: ".vimrc", exists: true, isDir: false)]
                ),
                application(name: "emacs"),
            ]
        )
        model.filter = .installed

        XCTAssertEqual(model.visibleApplications.map(\.name), ["vim"])
    }

    func testTheExcludedApplicationsAreNotSynced() {
        let model: ApplicationsModel = model(
            applications: [
                application(name: "vim"),
                application(name: "emacs"),
            ],
            ignore: ["emacs"]
        )

        XCTAssertTrue(model.isSynced(model.applications[0]))
        XCTAssertFalse(model.isSynced(model.applications[1]))
    }

    func testTheCheckedApplicationsAreTheOnlyOnesSynced() {
        let model: ApplicationsModel = model(
            applications: [
                application(name: "vim"),
                application(name: "emacs"),
            ],
            sync: ["vim"]
        )
        model.mode = .onlyChecked

        XCTAssertTrue(model.isSynced(model.applications[0]))
        XCTAssertFalse(model.isSynced(model.applications[1]))
    }

    func testTheFilterKeepsTheSyncedApplications() {
        let model: ApplicationsModel = model(
            applications: [
                application(name: "vim"),
                application(name: "emacs"),
            ],
            ignore: ["emacs"]
        )
        model.filter = .synced

        XCTAssertEqual(model.visibleApplications.map(\.name), ["vim"])
    }
}

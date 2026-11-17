import XCTest

@testable import MackeepDesktop

@MainActor
extension ApplicationsModelTests {
    func testRapidChangesUpdateImmediatelyAndSaveTheLatestState() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mackeep-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent(".mackeep.cfg")
        let original = "[applications_to_sync]\n\n[applications_to_ignore]\n"
        try original.write(to: url, atomically: true, encoding: .utf8)
        let model = ApplicationsModel(command: nil)
        model.setConfig(try MainConfig.load(from: url))
        let vim = application(name: "vim")
        let emacs = application(name: "emacs")

        model.setEnabled(true, for: vim)
        model.setEnabled(false, for: vim)
        model.setEnabled(true, for: emacs)

        XCTAssertFalse(model.isEnabled(vim))
        XCTAssertTrue(model.isEnabled(emacs))
        // Saving must not block the caller on the main actor.
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), original)
        await model.waitForPendingSaves()
        let saved = try MainConfig.load(from: url)
        XCTAssertEqual(saved.appsToSync, ["emacs"])
        XCTAssertEqual(saved.appsToIgnore, ["vim"])
        XCTAssertNil(model.presentedError)
    }

    func testBackgroundSaveReportsFailure() async throws {
        let model = ApplicationsModel(command: nil)
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("mackeep-tests-\(UUID().uuidString)")
        try Data().write(to: parent)
        defer { try? FileManager.default.removeItem(at: parent) }
        let url = parent.appendingPathComponent("mackeep.cfg")
        model.setConfig(MainConfig(url: url, document: INIDocument(text: "")))
        let vim = application(name: "vim")

        model.setEnabled(true, for: vim)
        await model.waitForPendingSaves()

        XCTAssertNotNil(model.presentedError)
    }

    func testChangingSelectionKeepsTheLatestSecuritySetting() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mackeep-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("main.cfg")
        try "[security]\nallow_external_paths = false\n".write(
            to: url, atomically: true, encoding: .utf8)
        let model = ApplicationsModel(command: nil)
        model.setConfig(try MainConfig.load(from: url))
        let settings = try MainConfig.load(from: url)
        settings.setAllowExternalPaths(true)
        try settings.save()

        model.setEnabled(true, for: application(name: "vim"))
        await model.waitForPendingSaves()
        XCTAssertTrue(try MainConfig.load(from: url).allowExternalPaths)
    }

    func testAbsentSelectionMeansAllExceptIgnored() {
        let model = ApplicationsModel(command: nil)
        model.setApplications([application(name: "vim"), application(name: "emacs")])
        model.setConfig(
            MainConfig(
                url: URL(fileURLWithPath: "/unused"),
                document: INIDocument(text: "[applications_to_ignore]\nemacs\n")))
        XCTAssertTrue(model.isEnabled(model.applications[0]))
        XCTAssertFalse(model.isEnabled(model.applications[1]))
    }

    func testFailedSaveRestoresSelectionAndBlocksOperations() async throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try Data().write(to: parent)
        defer { try? FileManager.default.removeItem(at: parent) }
        let model = ApplicationsModel(command: nil)
        model.setConfig(
            MainConfig(
                url: parent.appendingPathComponent("main.cfg"),
                document: INIDocument(text: "[applications_to_sync]\n")))
        let app = application(name: "vim")
        model.setEnabled(true, for: app)
        do {
            try await model.flushSelection()
            XCTFail("An unsaved selection must block operations")
        } catch {}
        XCTAssertFalse(model.isEnabled(app))
        XCTAssertNotNil(model.presentedError)
    }
}

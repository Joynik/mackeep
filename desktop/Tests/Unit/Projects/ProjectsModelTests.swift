import XCTest

@testable import MackeepDesktop

@MainActor
final class ProjectsModelTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mackeep-project-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    private func makeModel() throws -> ProjectsModel {
        let state = directory.appendingPathComponent("projects.json")
        try "[]".write(to: state, atomically: true, encoding: .utf8)
        let tool = directory.appendingPathComponent("cli")
        let script = """
            #!/bin/sh
            if [ -f "$STATE.fail" ]; then echo 'save failed' >&2; exit 1; fi
            case "$3" in
                list) cat "$STATE" ;;
                save) printf '[%s]\\n' "${4#--project-data=}" > "$STATE"; cat "$STATE" ;;
                delete) printf '[]\\n' > "$STATE"; cat "$STATE" ;;
                *) exit 2 ;;
            esac
            """
        try script.write(to: tool, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
        var command = MackeepCommand(path: tool.path, home: directory.path)
        command.environment["STATE"] = state.path
        return ProjectsModel(command: command)
    }

    func testSaveReloadRenameAndDelete() async throws {
        let model = try makeModel()
        var project = MackeepProject(
            name: "Example", root: "/Volumes/Projects/Example", files: ["src"])
        let created = await model.save(project)
        XCTAssertTrue(created)
        XCTAssertEqual(model.selectedProject, project)
        project.name = "Renamed"
        let renamed = await model.save(project)
        XCTAssertTrue(renamed)
        await model.load()
        XCTAssertEqual(model.projects, [project])
        XCTAssertFalse(model.canSave(MackeepProject(name: "renamed", root: "/tmp/other")))
        await model.delete(project)
        XCTAssertTrue(model.projects.isEmpty)
        XCTAssertNil(model.selection)
    }

    func testFailureRetainsSavedDefinition() async throws {
        let model = try makeModel()
        let project = MackeepProject(name: "Example", root: "/tmp/example")
        let created = await model.save(project)
        XCTAssertTrue(created)
        try Data().write(to: directory.appendingPathComponent("projects.json.fail"))
        await model.setEnabled(false, project: project)
        XCTAssertEqual(model.projects, [project])
        XCTAssertNotNil(model.presentedError)
        XCTAssertFalse(model.isWorking)
    }

    func testFiltersAndSearchUseOnlyProjects() async throws {
        let model = try makeModel()
        let project = MackeepProject(name: "Example", root: "/Volumes/Work/Example")
        _ = await model.save(project)
        model.filter = .disabled
        XCTAssertTrue(model.visibleProjects.isEmpty)
        await model.setEnabled(false, project: project)
        XCTAssertEqual(model.visibleProjects.count, 1)
        model.search = "work"
        XCTAssertEqual(model.visibleProjects.count, 1)
        model.search = "unknown"
        XCTAssertTrue(model.visibleProjects.isEmpty)
    }
}

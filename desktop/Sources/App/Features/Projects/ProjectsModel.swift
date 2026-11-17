import Foundation

/// A definition independent from the application catalog.
struct MackeepProject: Codable, Equatable, Identifiable, Sendable {
    var schemaVersion = MackeepSchema.version
    var id = UUID().uuidString.lowercased()
    var name = ""
    var root = ""
    var files: [String] = []
    var exclude: [String] = []
    var enabled = true

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case id, name, root, files, exclude, enabled
    }
}

/// Persist project changes through the same CLI used for backup operations.
@Observable
@MainActor
final class ProjectsModel {
    enum Filter: String, CaseIterable, Identifiable {
        case all, enabled, disabled
        var id: String { rawValue }
        var title: String { L10n.string("projects.filter.\(rawValue)") }
    }

    private(set) var projects: [MackeepProject] = []
    private(set) var isWorking = false
    var selection: String?
    var search = ""
    var filter: Filter = .all
    var presentedError: AppError?
    private let command: MackeepCommand?

    init(command: MackeepCommand?) { self.command = command }

    var visibleProjects: [MackeepProject] {
        projects.filter { project in
            (search.isEmpty || project.name.localizedCaseInsensitiveContains(search)
                || project.root.localizedCaseInsensitiveContains(search))
                && (filter == .all || project.enabled == (filter == .enabled))
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var selectedProject: MackeepProject? { projects.first { $0.id == selection } }

    func load() async { _ = await perform(["projects", "list"]) }

    func save(_ project: MackeepProject) async -> Bool {
        do {
            let data = try JSONEncoder().encode(project)
            guard let json = String(data: data, encoding: .utf8) else { return false }
            let saved = await perform(["projects", "save", "--project-data=\(json)"])
            if saved { selection = project.id }
            return saved
        } catch {
            present(error)
            return false
        }
    }

    func delete(_ project: MackeepProject) async {
        if await perform(["projects", "delete", project.id]), selection == project.id {
            selection = nil
        }
    }

    func setEnabled(_ enabled: Bool, project: MackeepProject) async {
        var updated = project
        updated.enabled = enabled
        _ = await save(updated)
    }

    /// Local validation improves feedback; the CLI independently validates every save.
    func canSave(_ project: MackeepProject) -> Bool {
        !project.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && project.root.hasPrefix("/")
            && !projects.contains {
                $0.id != project.id
                    && $0.name.caseInsensitiveCompare(
                        project.name.trimmingCharacters(in: .whitespacesAndNewlines))
                        == .orderedSame
            }
    }

    private func perform(_ arguments: [String]) async -> Bool {
        guard let command, !isWorking else { return false }
        isWorking = true
        defer { isWorking = false }
        do {
            projects = try await Task.detached(priority: .userInitiated) {
                try command.runJSON(["--json"] + arguments, as: [MackeepProject].self)
            }.value
            return true
        } catch {
            present(error)
            return false
        }
    }

    private func present(_ error: Error) {
        presentedError = AppError(
            title: L10n.string("error.save.title"), message: error.localizedDescription)
    }
}

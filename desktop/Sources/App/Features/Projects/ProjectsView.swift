import SwiftUI

/// An independent project list, without installed-application or library controls.
struct ProjectsView: View {
    @Bindable var model: ProjectsModel
    @State private var editing: MackeepProject?
    @State private var deleting: MackeepProject?

    var body: some View {
        HStack(spacing: 0) {
            VStack {
                TextField(L10n.string("projects.search"), text: $model.search)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)
                Picker(L10n.string("projects.filter"), selection: $model.filter) {
                    ForEach(ProjectsModel.Filter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                List(model.visibleProjects, selection: $model.selection) { project in
                    HStack {
                        Toggle(
                            L10n.string("projects.include"),
                            isOn: Binding(
                                get: { project.enabled },
                                set: { enabled in
                                    Task { await model.setEnabled(enabled, project: project) }
                                })
                        )
                        .labelsHidden()
                        .toggleStyle(.checkbox)
                        VStack(alignment: .leading) {
                            Text(project.name)
                            Text(project.root)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    .tag(project.id)
                }
            }
            .padding(.top)
            .frame(minWidth: 300, idealWidth: 400, maxWidth: 520)
            Divider()
            if let project = model.selectedProject {
                projectDetail(project)
            } else {
                ContentUnavailableView(
                    L10n.string("section.projects.title"), systemImage: "folder",
                    description: Text(L10n.string("projects.empty")))
            }
        }
        .navigationTitle(L10n.string("section.projects.title"))
        .toolbar {
            Button {
                editing = MackeepProject()
            } label: {
                Label(L10n.string("projects.create"), systemImage: "plus")
            }
        }
        .task { await model.load() }
        .disabled(model.isWorking)
        .overlay { if model.isWorking { ProgressView() } }
        .sheet(item: $editing) { project in
            ProjectEditorView(model: model, project: project)
        }
        .confirmationDialog(
            L10n.string("projects.delete.confirm", deleting?.name ?? ""),
            isPresented: Binding(
                get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible
        ) {
            if let project = deleting {
                Button(L10n.string("applications.delete"), role: .destructive) {
                    Task { await model.delete(project) }
                }
            }
        } message: {
            Text(L10n.string("projects.delete.help"))
        }
        .appError(
            Binding(
                get: { editing == nil ? model.presentedError : nil },
                set: { model.presentedError = $0 })
        )
        .appControlSize()
    }

    private func projectDetail(_ project: MackeepProject) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(project.name).font(.title2.weight(.semibold))
                Text(project.root).font(.callout.monospaced()).textSelection(.enabled)
                HStack {
                    Button(L10n.string("applications.edit")) { editing = project }
                    Button(L10n.string("applications.copy")) {
                        var copy = project
                        copy.id = UUID().uuidString.lowercased()
                        copy.name = ""
                        editing = copy
                    }
                    Button(L10n.string("applications.delete"), role: .destructive) {
                        deleting = project
                    }
                }
                CardView(title: L10n.string("projects.files")) {
                    Text(project.files.joined(separator: "\n"))
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                }
                CardView(title: L10n.string("projects.exclude")) {
                    Text(project.exclude.joined(separator: "\n"))
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .frame(minWidth: 320, maxWidth: .infinity)
    }
}

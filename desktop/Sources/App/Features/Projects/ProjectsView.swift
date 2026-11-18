import SwiftUI

/// The Applications layout, backed by the independent project list.
struct ProjectsView: View {
    @Bindable var model: ProjectsModel
    @State private var editing: MackeepProject?
    @State private var deleting: MackeepProject?

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                toolbar
                Divider()
                list
            }
            .frame(minWidth: 360, idealWidth: 460, maxWidth: 560)
            Divider()
            Group {
                if let project = model.selectedProject {
                    ProjectDetailView(
                        project: project, onEdit: { editing = project },
                        onCopy: { copySelected() }, onDelete: { deleting = project })
                } else {
                    ContentUnavailableView {
                        Label(L10n.string("section.projects.title"), systemImage: "folder")
                    } description: {
                        Text(L10n.string("projects.empty"))
                    }
                }
            }
            .frame(minWidth: 320, maxWidth: .infinity)
        }
        .navigationTitle(L10n.string("section.projects.title"))
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

    private var toolbar: some View {
        VStack(spacing: 13) {
            HStack(spacing: 8) {
                TextField(
                    L10n.string("projects.search"),
                    text: $model.search
                )
                .textFieldStyle(AppFieldStyle())
                .frame(maxWidth: .infinity)
                .accessibilityLabel(L10n.string("projects.search"))

                Picker("", selection: $model.filter) {
                    ForEach(ProjectsModel.Filter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 200)
                // The menu of macOS has a big padding inside, it is taken
                // away, so the filter stands right next to the search
                .padding(.leading, -32)
                .accessibilityLabel(L10n.string("projects.filter"))
            }
            HStack(spacing: 12) {
                Button {
                    editing = MackeepProject()
                } label: {
                    Label(
                        L10n.string("applications.create.add"),
                        systemImage: "plus.square"
                    )
                }
                .help(L10n.string("applications.create.add"))
                .accessibilityIdentifier("projects.create.button")

                Button {
                    copySelected()
                } label: {
                    Label(
                        L10n.string("applications.copy"),
                        systemImage: "doc.on.doc"
                    )
                }
                .help(L10n.string("applications.copy"))
                .disabled(model.selectedProject == nil)

                Button {
                    deleting = model.selectedProject
                } label: {
                    Label(
                        L10n.string("applications.delete"),
                        systemImage: "trash"
                    )
                }
                .help(L10n.string("applications.delete"))
                .disabled(model.selectedProject == nil)

                Spacer(minLength: 8)
            }
        }
        // The controls of the panel have the same height, so they line up.
        .appControlSize()
        .padding(12)
    }

    private var list: some View {
        List(selection: $model.selection) {
            Section {
                ForEach(model.visibleProjects) { project in
                    HStack(spacing: 10) {
                        Toggle(
                            "",
                            isOn: Binding(
                                get: { project.enabled },
                                set: { enabled in
                                    Task { await model.setEnabled(enabled, project: project) }
                                })
                        )
                        .labelsHidden()
                        .appSwitchSize()
                        .accessibilityLabel(L10n.string("projects.include"))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(project.name).font(.body)
                            Text(project.root)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { editing = project }
                    }
                    .padding(.vertical, 2)
                    .tag(project.id)
                    .contextMenu {
                        Button(L10n.string("applications.edit")) { editing = project }
                        Button(L10n.string("applications.copy")) {
                            model.selection = project.id
                            copySelected()
                        }
                        Button(L10n.string("applications.delete"), role: .destructive) {
                            deleting = project
                        }
                    }
                }
            } header: {
                Text("\(L10n.string("section.projects.title")): \(model.visibleProjects.count)")
            }
        }
        .listStyle(.inset)
    }

    private func copySelected() {
        guard var copy = model.selectedProject else { return }
        copy.id = UUID().uuidString.lowercased()
        copy.name = ""
        editing = copy
    }
}

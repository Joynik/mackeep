import SwiftUI

/// The list of the applications of Mackeep.
struct ApplicationsView: View {
    /// The model of the list.
    @Bindable var model: ApplicationsModel

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            list
        }
        .navigationTitle(L10n.string("section.applications.title"))
    }

    /// The tools of the list.
    private var toolbar: some View {
        HStack(spacing: 8) {
            TextField(
                L10n.string("applications.search.placeholder"),
                text: $model.searchText
            )
            .textFieldStyle(.roundedBorder)
            .accessibilityLabel(L10n.string("applications.search.placeholder"))

            Picker("", selection: $model.filter) {
                ForEach(ApplicationFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 140)
            .accessibilityLabel(L10n.string("applications.filter.label"))

            Picker("", selection: $model.sort) {
                ForEach(ApplicationSort.allCases) { sort in
                    Text(sort.title).tag(sort)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 140)
            .accessibilityLabel(L10n.string("applications.sort.label"))
        }
        .padding(12)
    }

    /// The list of the applications.
    private var list: some View {
        List(selection: $model.selection) {
            Section {
                ForEach(model.visibleApplications) { application in
                    ApplicationRow(application: application, model: model)
                        .tag(application.name)
                }
            } header: {
                Text(
                    L10n.string(
                        "applications.count",
                        model.visibleApplications.count
                    )
                )
            }
        }
        .listStyle(.inset)
    }
}

/// A row of the list of the applications.
private struct ApplicationRow: View {
    /// The application.
    let application: MackeepApplication

    /// The model of the list.
    let model: ApplicationsModel

    var body: some View {
        HStack(spacing: 10) {
            Toggle(
                "",
                isOn: Binding(
                    get: { model.isSynced(application) },
                    set: { model.setSynced($0, for: application) }
                )
            )
            .labelsHidden()
            .accessibilityLabel(
                L10n.string("applications.sync.label", application.displayName)
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(application.displayName)
                    .font(.body)
                Text(application.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if model.isInstalled(application) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.tint)
                    .help(L10n.string("applications.installed.label"))
                    .accessibilityLabel(L10n.string("applications.installed.label"))
            }

            Image(systemName: application.isCustom ? "person.crop.circle" : "shippingbox")
                .foregroundStyle(.secondary)
                .help(
                    application.isCustom
                        ? L10n.string("applications.source.custom")
                        : L10n.string("applications.source.builtin")
                )
                .accessibilityLabel(
                    application.isCustom
                        ? L10n.string("applications.source.custom")
                        : L10n.string("applications.source.builtin")
                )
        }
        .padding(.vertical, 2)
    }
}

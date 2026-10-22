import SwiftUI

/// The sheet that creates an application.
struct ApplicationCreatorView: View {
    /// The model of the creation.
    @Bindable var model: ApplicationCreatorModel

    /// The identifiers of the applications that exist.
    let existing: Set<String>

    /// The callback called when the application is created.
    let onCreate: (String) -> Void

    /// The error shown to the user, when there is one.
    @State private var presentedError: AppError?

    /// Closes the sheet.
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(
                model.source == nil
                    ? L10n.string("editor.create.title")
                    : L10n.string("editor.create.copyTitle")
            )
            .font(.title3.weight(.semibold))

            Form {
                Section {
                    TextField(
                        L10n.string("editor.create.name.placeholder"),
                        text: $model.displayName
                    )
                    .textFieldStyle(AppFieldStyle())
                    .accessibilityIdentifier("editor.create.name")
                    TextField(
                        L10n.string("editor.create.identifier.placeholder"),
                        text: $model.name
                    )
                    .textFieldStyle(AppFieldStyle())
                    .accessibilityIdentifier("editor.create.identifier")
                }
            }
            .formStyle(.grouped)
            .frame(height: 140)

            if !model.issues.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(model.issues) { issue in
                        Label(
                            issue.message,
                            systemImage: "exclamationmark.triangle"
                        )
                        .font(.caption)
                        .foregroundStyle(.orange)
                    }
                }
            }

            HStack {
                Spacer()
                Button(L10n.string("editor.create.cancel"), role: .cancel) {
                    dismiss()
                }
                Button(L10n.string("editor.create.create")) {
                    create()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!model.canCreate)
                .accessibilityIdentifier("editor.create.confirm")
            }
        }
        .padding(20)
        .frame(width: 460)
        // The controls of the window have the same height, so they line up.
        .appControlSize()
        .appError($presentedError)
        .onChange(of: model.name) {
            model.validate(existing: existing)
        }
    }

    /// Create the application.
    private func create() {
        do {
            let identifier: String = try model.create()
            onCreate(identifier)
        } catch {
            presentedError = AppError(
                title: L10n.string("error.save.title"),
                message: error.localizedDescription
            )
        }
    }
}

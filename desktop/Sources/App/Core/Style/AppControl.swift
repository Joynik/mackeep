import SwiftUI

/// The look of the controls of the application.
///
/// All the buttons, the fields and the lists have the same height, so they
/// stand in one line and the panels look the same in every window.
enum AppControl {
    /// The height of the controls.
    static let height: CGFloat = 28
}

extension View {
    /// Make the controls of the view the size of all the controls.
    ///
    /// The buttons and the lists of macOS grow with the large control size,
    /// the fields keep their own size, so they get their height from the
    /// style of the fields.
    func appControlSize() -> some View {
        controlSize(.large)
    }

    /// Make the switches of the view smaller.
    ///
    /// The switch of macOS has no medium size, it is a bit smaller than the
    /// large one.
    func appSwitchSize() -> some View {
        controlSize(.large)
            .scaleEffect(0.9)
    }
}

/// The style of the fields of the application.
///
/// The field of macOS has a fixed height, it does not grow with the control
/// size, so the border is drawn here, with the height of the buttons. The
/// system field is removed, so the field has only one border, and the text is
/// on the left, as in the other fields of the application.
struct AppFieldStyle: TextFieldStyle {
    /// The height of the field.
    static let height: CGFloat = AppControl.height

    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .textFieldStyle(.plain)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(AppFieldFrame())
    }
}

/// Shared border and spacing for SwiftUI and AppKit fields.
private struct AppFieldFrame: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 6)
            .frame(height: AppControl.height)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(
                                Color(nsColor: .separatorColor),
                                lineWidth: 1
                            )
                    }
            }
    }
}

/// Present persistence and command failures at the view that owns them.
extension View {
    func appError(_ error: Binding<AppError?>) -> some View {
        alert(
            error.wrappedValue?.title ?? "",
            isPresented: Binding(
                get: { error.wrappedValue != nil }, set: { if !$0 { error.wrappedValue = nil } }
            )
        ) {
            Button(L10n.string("error.dismiss"), role: .cancel) { error.wrappedValue = nil }
        } message: {
            Text(error.wrappedValue?.message ?? "")
        }
    }
}

/// A single-line field with explicit native alignment, independent of Form defaults.
struct LeadingTextField: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: text)
        field.isBezeled = false
        field.drawsBackground = false
        field.alignment = .left
        field.font = .systemFont(ofSize: NSFont.systemFontSize)
        field.cell?.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.text = $text
        if field.stringValue != text { field.stringValue = text }
        field.alignment = .left
        (field.currentEditor() as? NSTextView)?.alignment = .left
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            text.wrappedValue = field.stringValue
        }
    }
}

extension LeadingTextField {
    func appFieldStyle() -> some View { modifier(AppFieldFrame()) }
}

/// A field label whose hint is available on hover and on click.
struct FieldInfoLabel: View {
    let title: String
    let hint: String
    var iconOnly = false
    @State private var showsHint = false

    var body: some View {
        HStack(spacing: 6) {
            if !iconOnly { Text(title) }
            Button { showsHint.toggle() } label: {
                Image(systemName: "info.circle")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel(title)
            .help(hint)
            .popover(isPresented: $showsHint) {
                Text(hint)
                    .font(.callout)
                    .padding(12)
                    .frame(idealWidth: 260)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

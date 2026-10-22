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
            .padding(.horizontal, 6)
            .frame(height: Self.height)
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

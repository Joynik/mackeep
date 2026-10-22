import SwiftUI
import XCTest

@testable import MackeepDesktop

/// The tests of the size of the controls.
final class AppControlTests: XCTestCase {
    /// The height of a view.
    private func height<V: View>(_ view: V) -> CGFloat {
        let hosting: NSHostingView<AnyView> = NSHostingView(
            rootView: AnyView(view)
        )
        hosting.frame = CGRect(x: 0, y: 0, width: 400, height: 400)
        hosting.layoutSubtreeIfNeeded()
        return hosting.fittingSize.height
    }

    func testTheButtonHasTheHeightOfTheControls() {
        let size: CGFloat = height(
            Button("Add") {}
                .buttonStyle(.bordered)
                .appControlSize()
        )

        XCTAssertEqual(size, AppControl.height, accuracy: 0.5)
    }

    func testTheFieldHasTheHeightOfTheControls() {
        let size: CGFloat = height(
            TextField("Path", text: .constant(""))
                .textFieldStyle(AppFieldStyle())
        )

        XCTAssertEqual(size, AppControl.height, accuracy: 0.5)
    }

    func testTheListHasTheHeightOfTheControls() {
        let size: CGFloat = height(
            Picker("", selection: .constant(1)) { Text("All").tag(1) }
                .pickerStyle(.menu)
                .appControlSize()
        )

        XCTAssertEqual(size, AppControl.height, accuracy: 0.5)
    }

    @MainActor
    func testNativeFieldConnectsBindingDelegateAndLeftAlignedEditor() async throws {
        let state = FieldState()
        let hosting = NSHostingView(rootView: FieldHarness(state: state))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 40),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        defer { window.contentView = nil }
        hosting.layoutSubtreeIfNeeded()
        func field(in view: NSView) -> NSTextField? {
            (view as? NSTextField) ?? view.subviews.lazy.compactMap { field(in: $0) }.first
        }
        let native = try XCTUnwrap(field(in: hosting))
        XCTAssertEqual(native.stringValue, "Original")
        XCTAssertEqual(native.alignment, .left)
        XCTAssertNotNil(native.delegate)
        native.stringValue = "Typed name"
        native.delegate?.controlTextDidChange?(
            Notification(name: NSControl.textDidChangeNotification, object: native))
        XCTAssertEqual(state.text, "Typed name")
        state.text = "External update"
        native.alignment = .right
        hosting.rootView = FieldHarness(state: state)
        hosting.layoutSubtreeIfNeeded()
        try await waitUntil("Native field reflects the binding") { native.stringValue == state.text }
        XCTAssertEqual(native.alignment, .left)
        XCTAssertTrue(window.makeFirstResponder(native))
        let editor = try XCTUnwrap(native.currentEditor() as? NSTextView)
        editor.alignment = .right
        state.text = "Editing update"
        hosting.rootView = FieldHarness(state: state)
        hosting.layoutSubtreeIfNeeded()
        try await waitUntil("Editing field reflects the binding") { native.stringValue == state.text }
        XCTAssertEqual(editor.alignment, .left)
    }

    func testTheNativeFieldHasTheHeightOfTheControls() {
        let size = height(LeadingTextField(text: .constant("Name")).appFieldStyle())
        XCTAssertEqual(size, AppControl.height, accuracy: 0.5)
    }
}

@Observable
private final class FieldState {
    var text = "Original"
}

private struct FieldHarness: View {
    @Bindable var state: FieldState
    var body: some View { LeadingTextField(text: $state.text) }
}

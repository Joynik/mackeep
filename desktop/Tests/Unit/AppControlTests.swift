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
}

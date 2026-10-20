import SwiftUI

/// The entry point of the Mackeep desktop application.
@main
struct MackeepDesktopApp: App {
    /// The state of the application, shared by the windows.
    @State private var environment = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(environment)
        }
        .defaultSize(width: 1100, height: 720)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

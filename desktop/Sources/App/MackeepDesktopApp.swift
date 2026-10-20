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

        // The window of the editor of an application
        WindowGroup(for: String.self) { $appName in
            if let appName: String,
               let model: ApplicationEditorModel = environment.editor(for: appName)
            {
                ApplicationEditorView(model: model)
                    .environment(environment)
            }
        }
        .defaultSize(width: 780, height: 640)
    }
}

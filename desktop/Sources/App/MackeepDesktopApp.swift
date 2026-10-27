import SwiftUI

/// The entry point of the Mackeep desktop application.
@main
struct MackeepDesktopApp: App {
    /// The state of the application, shared by the windows.
    @State private var environment = AppEnvironment()
    @NSApplicationDelegateAdaptor(MackeepAppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(environment)
                .environment(\.locale, environment.language.resolvedLocale)
                .preferredColorScheme(environment.appearance.colorScheme)
                .onAppear { delegate.backup = environment.backup }
                .onReceive(
                    NotificationCenter.default.publisher(
                        for: NSApplication.willTerminateNotification)
                ) { _ in
                    if EditorPath.isTesting,
                        let home = EditorPath.testValue("MACKEEP_TEST_HOME"),
                        home.hasPrefix("/private/tmp/mackeep-ui-")
                    {
                        try? FileManager.default.removeItem(atPath: home)
                    }
                }
        }
        .defaultSize(width: 1100, height: 720)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        Window(L10n.string("applications.library.title"), id: "library") {
            LibraryView(model: environment.applications)
                .environment(environment)
                .environment(\.locale, environment.language.resolvedLocale)
                .preferredColorScheme(environment.appearance.colorScheme)
        }
        .defaultSize(width: 820, height: 600)
        .windowResizability(.contentMinSize)

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

/// Defer ordinary quit and logout until filesystem work has stopped safely.
@MainActor
final class MackeepAppDelegate: NSObject, NSApplicationDelegate {
    weak var backup: BackupModel?
    private var waitingForTermination = false

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let backup, backup.isRunning else { return .terminateNow }
        if !waitingForTermination {
            waitingForTermination = true
            Task {
                await backup.stopForTermination()
                waitingForTermination = false
                sender.reply(toApplicationShouldTerminate: true)
            }
        }
        return .terminateLater
    }
}

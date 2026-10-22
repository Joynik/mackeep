import Foundation
import UserNotifications

/// The notifications of the application.
enum Notifier {
    /// The identifier of the notifications of the application.
    private static let identifier: String = "com.joynik.mackeep.run"

    /// Ask the user for the permission to show the notifications.
    static func askPermission() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound]
        ) { _, _ in }
    }

    /// Tell the user that a run is over.
    ///
    /// - Parameters:
    ///   - title: The title of the notification.
    ///   - message: The message of the notification.
    /// - Returns: True when the notification was sent.
    @discardableResult
    static func notify(title: String, message: String) -> Bool {
        if EditorPath.isTesting { return false }
        let content: UNMutableNotificationContent = UNMutableNotificationContent()
        content.title = title
        content.body = message

        let request: UNNotificationRequest = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            guard let error else { return }
            NSLog("The notification was not sent: %@", String(describing: error))
        }
        return true
    }
}

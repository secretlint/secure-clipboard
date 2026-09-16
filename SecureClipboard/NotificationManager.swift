import Foundation
import UserNotifications
import os

/// Wraps UserNotifications delivery. Constructing this type never touches
/// `UNUserNotificationCenter`, which crashes when `Bundle.main.bundleIdentifier`
/// is nil (e.g. `swift run` / SPM test processes). All UN access is guarded by
/// `isAvailable` and performed lazily.
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    private let logger = Logger(subsystem: "com.secretlint.SecureClipboard", category: "Notifications")

    private var isAvailable: Bool {
        Bundle.main.bundleIdentifier != nil
    }

    private var center: UNUserNotificationCenter? {
        isAvailable ? UNUserNotificationCenter.current() : nil
    }

    /// Set the delegate and request authorization once per launch. The system
    /// only prompts while the state is `.notDetermined`, so later launches do
    /// not re-prompt. Failures are logged and never propagate.
    func start() {
        guard let center else {
            logger.debug("Notifications unavailable: no bundle identifier")
            return
        }
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { [logger] granted, error in
            if let error {
                logger.error("Notification authorization failed: \(error)")
            } else {
                logger.info("Notification authorization granted: \(granted, privacy: .public)")
            }
        }
    }

    /// Deliver a notification immediately. Safe to call from any thread; the
    /// call sites run off the main thread. Never throws into the caller.
    func send(title: String, body: String) {
        guard let center else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        // Unique identifier so each detection is delivered separately instead
        // of replacing a previous notification.
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        center.add(request) { [logger] error in
            if let error {
                logger.error("Notification delivery failed: \(error)")
            }
        }
    }

    /// Present banner + sound even when the app is the active application
    /// (e.g. while the menu bar menu is open).
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

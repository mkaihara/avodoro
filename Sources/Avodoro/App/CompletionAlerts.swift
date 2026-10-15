import AppKit
@preconcurrency import UserNotifications

/// The words of the end-of-session notification. Pure, so it is testable.
enum NotificationText {
    static func make(type: SessionType, description: String) -> (title: String, body: String) {
        switch type {
        case .focus:
            let task = description.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            return ("Focus session done", task.isEmpty ? "Time for a break." : task)
        case .break:
            return ("Break is over", "Ready to focus?")
        }
    }
}

/// Sound and notification when a session's time runs out.
///
/// Notification permission is asked at the first session end, not at launch. Any notification
/// failure (possible with ad hoc signing) is logged and otherwise ignored: the sound and the
/// pit's completion motion don't depend on it, and nothing here ever blocks.
@MainActor
final class CompletionAlerts: NSObject, UNUserNotificationCenterDelegate {
    private let settings: SettingsStore
    private var hasAskedPermission = false

    init(settings: SettingsStore) {
        self.settings = settings
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func sessionCompleted(type: SessionType, description: String) {
        if settings.soundAtEnd {
            if let sound = NSSound(named: NSSound.Name(settings.soundName)) {
                sound.play()
            } else {
                Log.app.error("Sound not found: \(self.settings.soundName, privacy: .public)")
            }
        }
        if settings.notificationAtEnd {
            let text = NotificationText.make(type: type, description: description)
            Task { await post(title: text.title, body: text.body) }
        }
    }

    private func post(title: String, body: String) async {
        let center = UNUserNotificationCenter.current()
        do {
            if !hasAskedPermission {
                hasAskedPermission = true
                let granted = try await center.requestAuthorization(options: [.alert])
                Log.app.info("Notification permission granted: \(granted, privacy: .public)")
            }
            let status = await center.notificationSettings().authorizationStatus
            guard status == .authorized || status == .provisional else {
                Log.app.info("Notifications not authorized (status \(status.rawValue, privacy: .public)); sound and animation only")
                return
            }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            // No sound: the app already played the chosen one.
            try await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        } catch {
            Log.app.error("Notification failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Show the banner even while Avodoro is active (for example with Settings open).
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }
}

import Foundation
import UserNotifications

/// scheduleMessage()/cancelScheduleSendPendingIntent(). iOS doesn't let apps send texts
/// in the background, so instead of an exact alarm a local notification fires at the
/// scheduled time and the message is handed to the composer when the app is opened.
enum Scheduler {
    static func identifier(_ id: Int64) -> String { "org.fossify.messages.scheduled.\(id)" }

    static func schedule(_ m: Message, title: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            // lock_screen_visibility decides how much the notification shows.
            switch Config.shared.lockScreenVisibilitySetting {
            case LockScreen.senderMessage:
                content.title = title
                content.body = m.body.isEmpty ? "Scheduled message" : m.body
            case LockScreen.sender:
                content.title = title
                content.body = "Scheduled message"
            default:
                content.title = "Scheduled message"
            }
            content.sound = .default
            content.threadIdentifier = String(m.threadId)
            let seconds = max(1, TimeInterval(m.date) - Date().timeIntervalSince1970)
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
            center.add(UNNotificationRequest(identifier: identifier(m.id), content: content, trigger: trigger))
        }
    }

    static func cancel(_ id: Int64) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier(id)])
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [identifier(id)])
    }
}

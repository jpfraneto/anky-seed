import Foundation
import UserNotifications

struct LocalNotificationScheduler {
    private let center: UNUserNotificationCenter
    private let identifier = "anky.daily-reminder"
    // Kept here (not in PurchaseConstants) so this file stays inside the
    // SwiftPM AnkyCore target, which has no Purchases/ sources.
    private let trialReminderIdentifier = "anky.trial-ending-reminder"

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) == true
    }

    func scheduleDailyReminder(hour: Int, minute: Int) async throws {
        let content = UNMutableNotificationContent()
        content.title = "ANKY"
        content.body = "write your anky today"
        content.sound = .default

        var components = DateComponents()
        components.hour = hour
        components.minute = minute

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        )
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        try await center.add(request)
    }

    func cancelDailyReminder() {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    /// The honest trial reminder: 44 hours into the 72-hour free trial,
    /// while there is still real time to cancel. Scheduling replaces any
    /// previously pending reminder.
    func scheduleTrialEndingReminder(at fireDate: Date) async throws {
        let interval = fireDate.timeIntervalSinceNow
        guard interval > 0 else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString(
            "Your Anky Pro trial ends tomorrow",
            comment: "Annual Pro trial expiry notification title"
        )
        content.body = NSLocalizedString(
            "Manage or cancel in Apple subscription settings. Pro includes automatic rest-of-day unlocking after you reach your target.",
            comment: "Annual Pro trial expiry notification body"
        )
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: trialReminderIdentifier,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        )
        center.removePendingNotificationRequests(withIdentifiers: [trialReminderIdentifier])
        try await center.add(request)
    }

    func cancelTrialEndingReminder() {
        center.removePendingNotificationRequests(withIdentifiers: [trialReminderIdentifier])
    }
}

import Foundation
import UserNotifications

/// Local notifications: daily streak nudge, streak-at-risk, and the pre-charge trial reminder.
enum NotificationService {
    private static let dailyId = "nagare.daily"
    private static let atRiskId = "nagare.streak.atrisk"
    private static let trialId = "nagare.trial.reminder"

    static func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            print("[Notifications] authorization error: \(error.localizedDescription)")
            return false
        }
    }

    static func isAuthorized() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    }

    /// Daily nudge at 19:00.
    static func scheduleDailyReminder() {
        let content = UNMutableNotificationContent()
        content.title = "Your daily flow is waiting"
        content.body = "A couple of clips keeps your streak alive. 流れに乗ろう!"
        content.sound = .default
        var components = DateComponents()
        components.hour = 19
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        add(UNNotificationRequest(identifier: dailyId, content: content, trigger: trigger))
    }

    /// Gentle streak-at-risk nudge at 21:30 today if the goal hasn't been met yet.
    static func scheduleStreakAtRisk(streak: Int) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [atRiskId])
        guard streak > 0 else { return }
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = 21
        components.minute = 30
        guard let fire = Calendar.current.date(from: components), fire > Date() else { return }
        let content = UNMutableNotificationContent()
        content.title = "Your \(streak)-day streak is at risk"
        content.body = "One short clip is all it takes tonight."
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        add(UNNotificationRequest(identifier: atRiskId, content: content, trigger: trigger))
    }

    static func cancelStreakAtRisk() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [atRiskId])
    }

    /// Reminder one day before a free trial ends (default: 3-day yearly trial → fire after 2 days).
    static func scheduleTrialReminder(trialDays: Int = 3) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [trialId])
        guard trialDays > 1 else { return }
        let fireAfterDays = max(1, trialDays - 1)
        let content = UNMutableNotificationContent()
        content.title = "Your free trial ends tomorrow"
        content.body = "Jojo Pro renews after your \(trialDays)-day trial unless you cancel at least 24 hours before it ends (Settings → Apple ID → Subscriptions)."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(fireAfterDays * 86_400), repeats: false)
        add(UNNotificationRequest(identifier: trialId, content: content, trigger: trigger))
    }

    static func cancelReminders() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [dailyId, atRiskId])
    }

    private static func add(_ request: UNNotificationRequest) {
        Task {
            do {
                try await UNUserNotificationCenter.current().add(request)
            } catch {
                print("[Notifications] schedule error: \(error.localizedDescription)")
            }
        }
    }
}

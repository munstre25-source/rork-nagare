import Foundation
import UserNotifications

/// Local notifications: daily streak nudge, review due cards, streak-at-risk, and trial reminder.
enum NotificationService {
    private static let dailyId = "nagare.daily"
    private static let reviewId = "nagare.review.due"
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

    /// Daily streak / study nudge at 19:00.
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

    /// Morning review nudge when flashcards are due.
    static func scheduleReviewReminder(dueCount: Int) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [reviewId])
        guard dueCount > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title = dueCount == 1 ? "1 card is due" : "\(dueCount) cards are due"
        content.body = "Quick review keeps words sticky. Open Vocab to practice."
        content.sound = .default
        content.userInfo = ["deepLink": "jojo://review"]

        var components = DateComponents()
        components.hour = 10
        components.minute = 0
        let calendar = Calendar.current
        let now = Date()
        if let todayAt10 = calendar.nextDate(after: now, matching: components, matchingPolicy: .nextTime),
           calendar.isDate(todayAt10, inSameDayAs: now) {
            let trigger = UNCalendarNotificationTrigger(dateMatching: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: todayAt10), repeats: false)
            add(UNNotificationRequest(identifier: reviewId, content: content, trigger: trigger))
        } else if let tomorrowAt10 = calendar.nextDate(after: now, matching: components, matchingPolicy: .nextTime) {
            let trigger = UNCalendarNotificationTrigger(dateMatching: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: tomorrowAt10), repeats: false)
            add(UNNotificationRequest(identifier: reviewId, content: content, trigger: trigger))
        }
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
        guard trialDays > 1 else { return }
        let expiration = Date().addingTimeInterval(TimeInterval(trialDays) * 86_400)
        scheduleTrialReminder(endingAt: expiration)
    }

    /// One day before the entitlement's trial end. No-op if that moment has already passed.
    static func scheduleTrialReminder(endingAt expiration: Date) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [trialId])
        let fire = expiration.addingTimeInterval(-86_400)
        let interval = fire.timeIntervalSinceNow
        guard interval > 60 else { return }
        let content = UNMutableNotificationContent()
        content.title = "Your free trial ends tomorrow"
        content.body = "Jojo Pro renews after your trial unless you cancel at least 24 hours before it ends (Settings → Apple ID → Subscriptions)."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        add(UNNotificationRequest(identifier: trialId, content: content, trigger: trigger))
    }

    static func cancelTrialReminder() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [trialId])
    }

    static func cancelReminders() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [dailyId, reviewId, atRiskId, trialId])
    }

    static func cancelAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
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

import Foundation
import UserNotifications

/// Local notifications: daily streak nudge, review due cards, streak-at-risk, and trial reminder.
enum NotificationService {
    private static let dailyId = "nagare.daily"
    private static let reminderHourKey = "jojo.reminderHour"
    private static let reviewId = "nagare.review.due"
    private static let firstReviewId = "nagare.review.first"
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

    static var reminderHour: Int {
        let saved = UserDefaults.standard.object(forKey: reminderHourKey) as? Int ?? 19
        return min(max(saved, 0), 23)
    }

    private static func dailyIdentifier(for date: Date) -> String {
        let day = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(dailyId).\(day.year ?? 0)-\(day.month ?? 0)-\(day.day ?? 0)"
    }

    /// Schedule seven local days; never nudge after today's goal is complete.
    static func scheduleDailyReminder(clipTitle: String? = nil, channel: String? = nil,
                                      clipId: String? = nil, goalReachedToday: Bool = false) {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let days = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [dailyId] + days.map { dailyIdentifier(for: $0) }
        )
        let content = UNMutableNotificationContent()
        if let clipTitle, !clipTitle.isEmpty {
            content.title = channel.map { "Continue \($0)" } ?? "Your clip is waiting"
            content.body = "“\(clipTitle)” — a couple of minutes keeps words sticky."
            if let clipId {
                content.userInfo = ["deepLink": "jojo://feed?clipId=\(clipId)"]
            } else {
                content.userInfo = ["deepLink": "jojo://feed"]
            }
        } else {
            content.title = "Your daily flow is waiting"
            content.body = "A couple of clips keeps your streak alive. 流れに乗ろう!"
        }
        content.sound = .default
        for (offset, day) in days.enumerated() {
            guard !(offset == 0 && goalReachedToday),
                  let fire = calendar.date(bySettingHour: reminderHour, minute: 0, second: 0, of: day),
                  fire > now else { continue }
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            add(UNNotificationRequest(identifier: dailyIdentifier(for: day), content: content, trigger: trigger))
        }
    }

    static func cancelDailyReminderToday() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [dailyIdentifier(for: Date())]
        )
    }

    /// Morning review nudge when flashcards are due.
    static func scheduleReviewReminder(dueCount: Int, clipTitle: String? = nil, clipId: String? = nil) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [reviewId])
        guard dueCount > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title = dueCount == 1 ? "1 card is due" : "\(dueCount) cards are due"
        if let clipTitle, !clipTitle.isEmpty {
            content.body = "Words from “\(clipTitle)” are ready — quick review keeps them sticky."
        } else {
            content.body = "Quick review keeps words sticky. Open Vocab to practice."
        }
        content.sound = .default
        if let clipId {
            content.userInfo = ["deepLink": "jojo://review?clipId=\(clipId)"]
        } else {
            content.userInfo = ["deepLink": "jojo://review"]
        }

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

    /// One immediate, local nudge when the first dictionary card becomes reviewable.
    static func scheduleFirstReviewReminder(dueAt: Date) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [firstReviewId])
        let interval = dueAt.timeIntervalSinceNow
        guard interval > 1 else { return }
        let content = UNMutableNotificationContent()
        content.title = "Your new card is ready"
        content.body = "A quick review will help this word stick."
        content.sound = .default
        content.userInfo = ["deepLink": "jojo://review"]
        add(UNNotificationRequest(
            identifier: firstReviewId,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        ))
    }

    static func cancelFirstReviewReminder() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [firstReviewId])
    }

    /// Gentle streak-at-risk nudge at 21:30 today if the goal hasn't been met yet.
    static func scheduleStreakAtRisk(streak: Int, clipTitle: String? = nil, clipId: String? = nil) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [atRiskId])
        guard streak > 0 else { return }
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = 21
        components.minute = 30
        guard let fire = Calendar.current.date(from: components), fire > Date() else { return }
        let content = UNMutableNotificationContent()
        content.title = "Your \(streak)-day streak is at risk"
        if let clipTitle, !clipTitle.isEmpty {
            content.body = "One short pass of “\(clipTitle)” is all it takes tonight."
        } else {
            content.body = "One short clip is all it takes tonight."
        }
        content.sound = .default
        if let clipId {
            content.userInfo = ["deepLink": "jojo://feed?clipId=\(clipId)"]
        } else {
            content.userInfo = ["deepLink": "jojo://feed"]
        }
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        add(UNNotificationRequest(identifier: atRiskId, content: content, trigger: trigger))
    }

    static func cancelStreakAtRisk() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [atRiskId])
    }

    /// Reminder one day before a free trial ends (default: 7-day yearly trial → fire after 6 days).
    static func scheduleTrialReminder(trialDays: Int = 7) {
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
        let today = Calendar.current.startOfDay(for: Date())
        let daily = (0..<8).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: today) }
            .map { dailyIdentifier(for: $0) }
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [dailyId, reviewId, firstReviewId, atRiskId, trialId] + daily
        )
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

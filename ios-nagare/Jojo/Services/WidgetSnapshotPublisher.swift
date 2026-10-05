import Foundation
import SwiftData
import WidgetKit

/// Publishes a retention snapshot into the App Group for home-screen widgets.
@MainActor
enum WidgetSnapshotPublisher {
    private static var lastFingerprint: String = ""

    static func publish(from app: AppModel) {
        let words = (try? app.context.fetch(FetchDescriptor<SavedWord>())) ?? []
        let now = Date()
        let due = words.filter { $0.dueAt <= now }.sorted { $0.dueAt < $1.dueAt }
        let teaser = due.first ?? words.sorted { $0.addedAt > $1.addedAt }.first

        let reading = teaser?.primaryReading ?? ""
        let snapshot = WidgetSnapshot(
            streak: app.currentStreak,
            dailyGoalMinutes: app.profile.dailyGoalMinutes,
            minutesWatchedToday: Int(app.todayWatchedSeconds / 60),
            dueCount: due.count,
            totalWords: words.count,
            teaserSurface: teaser?.surface,
            teaserGloss: teaser?.definitions.first ?? teaser?.jaDefinitions.first,
            teaserReading: reading.isEmpty || reading == teaser?.surface ? nil : reading,
            accent: app.profile.theme.rawValue,
            scheme: app.profile.scheme.rawValue,
            updatedAt: now
        )
        let fingerprint = "\(snapshot.streak)|\(snapshot.minutesWatchedToday)|\(snapshot.dueCount)|\(snapshot.teaserSurface ?? "")|\(snapshot.teaserReading ?? "")|\(snapshot.accent)|\(snapshot.scheme)|\(snapshot.dailyGoalMinutes)"
        snapshot.save()
        guard fingerprint != lastFingerprint else { return }
        lastFingerprint = fingerprint
        WidgetCenter.shared.reloadAllTimelines()
    }
}

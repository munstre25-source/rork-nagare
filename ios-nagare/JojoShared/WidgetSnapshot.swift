import Foundation

/// App Group shared by the Jojo app and its widgets.
nonisolated enum JojoAppGroup {
    static let id = "group.com.socialreporthq.jojo"
    static let snapshotDefaultsKey = "widget.snapshot.v1"

    static var defaults: UserDefaults? {
        UserDefaults(suiteName: id)
    }
}

/// Compact retention snapshot written by the app, read by widgets.
///
/// Content priority (conversion / retention):
/// 1. Due cards — highest intent open → review session
/// 2. Streak + minutes left — habit / loss aversion → open feed
/// 3. Goal complete — positive reinforcement
nonisolated struct WidgetSnapshot: Codable, Hashable, Sendable {
    var streak: Int
    var dailyGoalMinutes: Int
    var minutesWatchedToday: Int
    var dueCount: Int
    var totalWords: Int
    /// Next due (or recently added) surface for medium widget teaser.
    var teaserSurface: String?
    var teaserGloss: String?
    var updatedAt: Date

    static let empty = WidgetSnapshot(
        streak: 0,
        dailyGoalMinutes: 10,
        minutesWatchedToday: 0,
        dueCount: 0,
        totalWords: 0,
        teaserSurface: nil,
        teaserGloss: nil,
        updatedAt: .distantPast
    )

    var minutesLeft: Int {
        max(0, dailyGoalMinutes - minutesWatchedToday)
    }

    var goalProgress: Double {
        guard dailyGoalMinutes > 0 else { return 0 }
        return min(Double(minutesWatchedToday) / Double(dailyGoalMinutes), 1)
    }

    var isGoalReached: Bool {
        minutesWatchedToday >= dailyGoalMinutes
    }

    /// Prefer review when cards are waiting; otherwise protect / build the streak.
    var preferredDeepLink: URL {
        if dueCount > 0 {
            return URL(string: "jojo://review")!
        }
        return URL(string: "jojo://feed")!
    }

    var headline: String {
        if dueCount > 0 { return "\(dueCount)" }
        if streak > 0 { return "\(streak)" }
        return "—"
    }

    var headlineCaption: String {
        if dueCount > 0 { return dueCount == 1 ? "card due" : "cards due" }
        if streak > 0 { return streak == 1 ? "day streak" : "day streak" }
        return "start streak"
    }

    var goalCaption: String {
        if isGoalReached { return "Goal done" }
        if minutesLeft == 0 { return "Almost there" }
        return "\(minutesLeft) min left"
    }

    static func load() -> WidgetSnapshot {
        guard let data = JojoAppGroup.defaults?.data(forKey: JojoAppGroup.snapshotDefaultsKey),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else {
            return .empty
        }
        return snapshot
    }

    func save() {
        guard let defaults = JojoAppGroup.defaults,
              let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: JojoAppGroup.snapshotDefaultsKey)
    }
}

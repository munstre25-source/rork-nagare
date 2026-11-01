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
    /// Kana for the teaser when the surface is kanji. Empty when the surface is already kana.
    var teaserReading: String?
    /// Accent raw value: sakura, plum, or orange.
    var accent: String
    /// light or dark.
    var scheme: String
    var updatedAt: Date
    /// Due dates after `updatedAt`, so the widget can advance without opening the app.
    var upcomingDueDates: [Date]
    var lastStudyDay: Date?
    var clipTitle: String?
    var clipId: String?

    init(
        streak: Int,
        dailyGoalMinutes: Int,
        minutesWatchedToday: Int,
        dueCount: Int,
        totalWords: Int,
        teaserSurface: String?,
        teaserGloss: String?,
        teaserReading: String?,
        accent: String,
        scheme: String,
        updatedAt: Date,
        upcomingDueDates: [Date] = [],
        lastStudyDay: Date? = nil,
        clipTitle: String? = nil,
        clipId: String? = nil
    ) {
        self.streak = streak
        self.dailyGoalMinutes = dailyGoalMinutes
        self.minutesWatchedToday = minutesWatchedToday
        self.dueCount = dueCount
        self.totalWords = totalWords
        self.teaserSurface = teaserSurface
        self.teaserGloss = teaserGloss
        self.teaserReading = teaserReading
        self.accent = accent
        self.scheme = scheme
        self.updatedAt = updatedAt
        self.upcomingDueDates = upcomingDueDates
        self.lastStudyDay = lastStudyDay
        self.clipTitle = clipTitle
        self.clipId = clipId
    }

    static let empty = WidgetSnapshot(
        streak: 0,
        dailyGoalMinutes: 10,
        minutesWatchedToday: 0,
        dueCount: 0,
        totalWords: 0,
        teaserSurface: nil,
        teaserGloss: nil,
        teaserReading: nil,
        accent: "orange",
        scheme: "light",
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
        if let clipId, !clipId.isEmpty {
            var components = URLComponents()
            components.scheme = "jojo"
            components.host = "feed"
            components.queryItems = [URLQueryItem(name: "clipId", value: clipId)]
            if let url = components.url { return url }
        }
        return URL(string: "jojo://feed")!
    }

    /// A dated timeline prevents yesterday's minutes and overdue-card count lingering on screen.
    func current(at date: Date) -> WidgetSnapshot {
        var copy = self
        let calendar = Calendar.current
        if !calendar.isDate(updatedAt, inSameDayAs: date) {
            copy.minutesWatchedToday = 0
        }
        copy.dueCount += upcomingDueDates.filter { $0 <= date }.count
        if let graceEnd = calendar.date(byAdding: .day, value: 2,
                                      to: calendar.startOfDay(for: lastStudyDay ?? updatedAt)),
           date >= graceEnd {
            copy.streak = 0
        }
        return copy
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

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        streak = try c.decode(Int.self, forKey: .streak)
        dailyGoalMinutes = try c.decode(Int.self, forKey: .dailyGoalMinutes)
        minutesWatchedToday = try c.decode(Int.self, forKey: .minutesWatchedToday)
        dueCount = try c.decode(Int.self, forKey: .dueCount)
        totalWords = try c.decode(Int.self, forKey: .totalWords)
        teaserSurface = try c.decodeIfPresent(String.self, forKey: .teaserSurface)
        teaserGloss = try c.decodeIfPresent(String.self, forKey: .teaserGloss)
        teaserReading = try c.decodeIfPresent(String.self, forKey: .teaserReading)
        accent = try c.decodeIfPresent(String.self, forKey: .accent) ?? "orange"
        scheme = try c.decodeIfPresent(String.self, forKey: .scheme) ?? "light"
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        upcomingDueDates = try c.decodeIfPresent([Date].self, forKey: .upcomingDueDates) ?? []
        lastStudyDay = try c.decodeIfPresent(Date.self, forKey: .lastStudyDay)
        clipTitle = try c.decodeIfPresent(String.self, forKey: .clipTitle)
        clipId = try c.decodeIfPresent(String.self, forKey: .clipId)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(streak, forKey: .streak)
        try c.encode(dailyGoalMinutes, forKey: .dailyGoalMinutes)
        try c.encode(minutesWatchedToday, forKey: .minutesWatchedToday)
        try c.encode(dueCount, forKey: .dueCount)
        try c.encode(totalWords, forKey: .totalWords)
        try c.encodeIfPresent(teaserSurface, forKey: .teaserSurface)
        try c.encodeIfPresent(teaserGloss, forKey: .teaserGloss)
        try c.encodeIfPresent(teaserReading, forKey: .teaserReading)
        try c.encode(accent, forKey: .accent)
        try c.encode(scheme, forKey: .scheme)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(upcomingDueDates, forKey: .upcomingDueDates)
        try c.encodeIfPresent(lastStudyDay, forKey: .lastStudyDay)
        try c.encodeIfPresent(clipTitle, forKey: .clipTitle)
        try c.encodeIfPresent(clipId, forKey: .clipId)
    }

    private enum CodingKeys: String, CodingKey {
        case streak, dailyGoalMinutes, minutesWatchedToday, dueCount, totalWords
        case teaserSurface, teaserGloss, teaserReading, accent, scheme, updatedAt
        case upcomingDueDates, lastStudyDay, clipTitle, clipId
    }

    func save() {
        guard let defaults = JojoAppGroup.defaults,
              let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: JojoAppGroup.snapshotDefaultsKey)
    }
}

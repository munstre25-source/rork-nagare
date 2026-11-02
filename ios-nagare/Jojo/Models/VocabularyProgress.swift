import Foundation

/// Counts real review activity separately from the learner's current Known vocabulary.
@MainActor
struct VocabularyProgress {
    static let goalOptions = [5, 10, 15, 20, 30]

    let learnedCount: Int
    let savedCount: Int
    let practicedToday: Int
    let dailyGoal: Int

    var fraction: Double { min(1, Double(practicedToday) / Double(dailyGoal)) }
    var remaining: Int { max(0, dailyGoal - practicedToday) }
    var goalReached: Bool { practicedToday >= dailyGoal }

    init(words: [SavedWord], dailyGoal: Int, now: Date = .now, calendar: Calendar = .current) {
        let valid = words.filter { !$0.key.isEmpty }
        savedCount = Set(valid.map(\.key)).count
        learnedCount = Set(valid.filter { $0.state == .known }.map(\.key)).count
        self.dailyGoal = min(50, max(1, dailyGoal))

        if let day = calendar.dateInterval(of: .day, for: now) {
            practicedToday = Set(valid.filter { word in
                guard let reviewed = word.lastReviewedAt else { return false }
                return reviewed >= day.start && reviewed < day.end && reviewed <= now
            }.map(\.key)).count
        } else {
            practicedToday = 0
        }
    }
}

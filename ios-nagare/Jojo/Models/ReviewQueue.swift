import Foundation

/// Shared eligibility and ordering for the dock, Vocab, Explore, and Profile.
enum ReviewQueue {
    static func due(in words: [SavedWord], at now: Date = Date()) -> [SavedWord] {
        words.filter { $0.isDueForReview(at: now) }.sorted(by: prioritized)
    }

    /// No due cards means optional early practice of learning words, never automatic known cards.
    static func session(in words: [SavedWord], limit: Int = 10, at now: Date = Date()) -> [SavedWord] {
        let dueWords = due(in: words, at: now)
        let pool = dueWords.isEmpty ? words.filter { $0.state != .known }.sorted(by: prioritized) : dueWords
        return Array(pool.prefix(max(0, limit)))
    }

    static func label(for session: [SavedWord], at now: Date = Date()) -> String {
        guard !session.isEmpty else { return "All caught up" }
        let action = session.allSatisfy { $0.isDueForReview(at: now) } ? "Review" : "Practice"
        return "\(action) \(session.count) \(session.count == 1 ? "card" : "cards")"
    }

    private static func prioritized(_ lhs: SavedWord, _ rhs: SavedWord) -> Bool {
        if lhs.occurrenceCount != rhs.occurrenceCount { return lhs.occurrenceCount > rhs.occurrenceCount }
        if lhs.dueAt != rhs.dueAt { return lhs.dueAt < rhs.dueAt }
        return lhs.key < rhs.key
    }
}

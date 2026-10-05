import Foundation

/// Spaced-repetition schedule: Again resets to <1m; Good advances 10m → 1d → 3d → 7d → 16d → 35d.
nonisolated enum SRS {
    static let againInterval: TimeInterval = 60
    static let goodIntervals: [TimeInterval] = [600, 86_400, 3 * 86_400, 7 * 86_400, 16 * 86_400, 35 * 86_400]
    static let knownThreshold: TimeInterval = 21 * 86_400
    static let maxStep = goodIntervals.count

    /// Interval applied when the user taps Good at `step`.
    static func goodInterval(fromStep step: Int) -> TimeInterval {
        goodIntervals[min(max(step, 0), goodIntervals.count - 1)]
    }

    static func state(forStep step: Int, reviewed: Bool) -> SRSState {
        guard step > 0 else { return reviewed ? .learning : .new }
        let current = goodIntervals[min(step, goodIntervals.count) - 1]
        return current >= knownThreshold ? .known : .learning
    }

    static func label(_ interval: TimeInterval) -> String {
        if interval < 60 { return "<1m" }
        if interval <= 60 { return "<1m" }
        if interval < 3600 { return "\(Int(interval / 60))m" }
        if interval < 86_400 { return "\(Int(interval / 3600))h" }
        return "\(Int(interval / 86_400))d"
    }

    static var againLabel: String { "<1m" }

    /// Spoken form of the next showing, as on the review card footer.
    static func untilReview(_ interval: TimeInterval) -> String {
        if interval < 3600 {
            let minutes = max(1, Int(interval / 60))
            return minutes == 1 ? "1 minute until review" : "\(minutes) minutes until review"
        }
        if interval < 86_400 {
            let hours = max(1, Int(interval / 3600))
            return hours == 1 ? "1 hour until review" : "\(hours) hours until review"
        }
        let days = max(1, Int(interval / 86_400))
        return days == 1 ? "1 day until review" : "\(days) days until review"
    }
}

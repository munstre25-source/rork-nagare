import ActivityKit
import Foundation

/// The sentence currently being heard. The Dynamic Island and the lock screen read this.
nonisolated struct ImmersionAttributes: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable, Sendable {
        /// Word under the playhead.
        var surface: String
        /// Kana for that word, when the surface has kanji.
        var reading: String
        /// The full line being spoken.
        var line: String
        var translation: String
        var minutesLeft: Int
        var goalProgress: Double
        /// sakura, plum, or orange.
        var accent: String
    }

    /// Stable for the whole For You session. The line itself lives in the content state.
    var session: String
}

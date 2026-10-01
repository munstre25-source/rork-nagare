import Foundation

/// An entry in the bundled local dictionary (~300+ common N5–N3 words).
nonisolated struct DictionaryEntry: Codable, Hashable, Sendable {
    var surface: String
    var readings: [String]
    var romaji: String
    var pos: String
    var jlpt: String?
    var definitions: [String]
    var conjugationClass: String?
    var formality: String?
    var baseForm: String?
    var baseReading: String?
    var baseRomaji: String?
}

/// A pre-saved vocab word used to seed the deck after onboarding.
nonisolated struct SeedVocabEntry: Codable, Sendable {
    var clipId: String
    var lineIndex: Int
    var surface: String
    var contextSentence: String
    var occurrenceCount: Int
    var srsState: String
    var intervalStepIndex: Int
    var dueOffsetHours: Double
    var addedDaysAgo: Int
}

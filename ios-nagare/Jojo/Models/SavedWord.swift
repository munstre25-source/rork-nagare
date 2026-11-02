import Foundation
import SwiftData

nonisolated enum SRSState: String, Codable, Sendable, CaseIterable {
    /// Yomi-style ladder: New → Learning → Familiar → Easy → Known.
    case new, learning, familiar, easy, known

    var title: String {
        switch self {
        case .new: "New"
        case .learning: "Learning"
        case .familiar: "Familiar"
        case .easy: "Easy"
        case .known: "Known"
        }
    }

    /// Marks the learner can paint from the dictionary card (excludes raw `.new`).
    static var paintMarks: [SRSState] { [.learning, .familiar, .easy, .known] }

    /// Progress 0…1 used by the ripen timeline.
    var ripenProgress: Double {
        switch self {
        case .new: 0
        case .learning: 0.25
        case .familiar: 0.5
        case .easy: 0.75
        case .known: 1
        }
    }
}

/// A word the user has tapped. CloudKit-compatible: every property has a default, no unique constraints.
@Model
final class SavedWord {
    var key: String = ""
    var surface: String = ""
    var readings: [String] = []
    var romaji: String = ""
    var pos: String = ""
    var conjugationClass: String?
    var jlpt: String?
    var definitions: [String] = []
    var jaDefinitions: [String] = []
    var occurrenceCount: Int = 0
    var contextSentence: String = ""
    /// How the word works in the sentence it was found in. Empty until a tap explains it.
    var contextNote: String = ""
    var contextSurface: String = ""
    var contextClipId: String = ""
    var contextLineIndex: Int = 0
    var addedAt: Date = Date()
    var srsState: String = SRSState.new.rawValue
    var intervalStepIndex: Int = 0
    var dueAt: Date = Date()
    var lastReviewedAt: Date?

    init(key: String, surface: String, readings: [String], romaji: String, pos: String,
         conjugationClass: String?, jlpt: String?, definitions: [String], jaDefinitions: [String] = []) {
        self.key = key
        self.surface = surface
        self.readings = readings
        self.romaji = romaji
        self.pos = pos
        self.conjugationClass = conjugationClass
        self.jlpt = jlpt
        self.definitions = WordExplanation.meaningfulDefinitions(definitions)
        self.jaDefinitions = WordExplanation.meaningfulDefinitions(jaDefinitions)
    }

    var state: SRSState {
        get { SRSState(rawValue: srsState) ?? .new }
        set { srsState = newValue.rawValue }
    }

    func isDueForReview(at now: Date = Date()) -> Bool {
        state != .known && dueAt <= now
    }

    var primaryReading: String { readings.first ?? "" }
    var gloss: String { WordExplanation.meaningfulDefinitions(definitions).first ?? WordExplanation.meaningfulDefinitions(jaDefinitions).first ?? "" }

    /// Definitions for the active dictionary mode (falls back sensibly).
    func displayDefinitions(mode: DictionaryMode) -> [String] {
        let definitions = WordExplanation.meaningfulDefinitions(self.definitions)
        let jaDefinitions = WordExplanation.meaningfulDefinitions(self.jaDefinitions)
        let values: [String]
        switch mode {
        case .english:
            values = definitions.isEmpty ? jaDefinitions : definitions
        case .japanese:
            values = jaDefinitions.isEmpty ? definitions : jaDefinitions
        case .both:
            var out = jaDefinitions
            for d in definitions where !out.contains(d) { out.append(d) }
            values = out
        }
        return uniqueSavedDefinitions(values)
    }

    /// Stable dedupe key: dictionary form + reading.
    static func makeKey(surface: String, reading: String) -> String {
        "\(surface)|\(reading)"
    }
}

private func uniqueSavedDefinitions(_ values: [String]) -> [String] {
    var seen = Set<String>()
    return values.compactMap { value in
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = trimmed.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        guard !trimmed.isEmpty, seen.insert(key).inserted else { return nil }
        return trimmed
    }
}

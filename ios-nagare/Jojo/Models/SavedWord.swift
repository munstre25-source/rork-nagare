import Foundation
import SwiftData

nonisolated enum SRSState: String, Codable, Sendable, CaseIterable {
    case new, learning, known
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
        self.definitions = definitions
        self.jaDefinitions = jaDefinitions
    }

    var state: SRSState {
        get { SRSState(rawValue: srsState) ?? .new }
        set { srsState = newValue.rawValue }
    }

    var primaryReading: String { readings.first ?? "" }
    var gloss: String { definitions.first ?? jaDefinitions.first ?? "" }

    /// Definitions for the active dictionary mode (falls back sensibly).
    func displayDefinitions(mode: DictionaryMode) -> [String] {
        switch mode {
        case .english:
            return definitions.isEmpty ? jaDefinitions : definitions
        case .japanese:
            return jaDefinitions.isEmpty ? definitions : jaDefinitions
        case .both:
            var out = jaDefinitions
            for d in definitions where !out.contains(d) { out.append(d) }
            return out
        }
    }

    /// Stable dedupe key: dictionary form + reading.
    static func makeKey(surface: String, reading: String) -> String {
        "\(surface)|\(reading)"
    }
}

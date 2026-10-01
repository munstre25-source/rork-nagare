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
         conjugationClass: String?, jlpt: String?, definitions: [String]) {
        self.key = key
        self.surface = surface
        self.readings = readings
        self.romaji = romaji
        self.pos = pos
        self.conjugationClass = conjugationClass
        self.jlpt = jlpt
        self.definitions = definitions
    }

    var state: SRSState {
        get { SRSState(rawValue: srsState) ?? .new }
        set { srsState = newValue.rawValue }
    }

    var primaryReading: String { readings.first ?? "" }
    var gloss: String { definitions.first ?? "" }

    /// Stable dedupe key: dictionary form + reading.
    static func makeKey(surface: String, reading: String) -> String {
        "\(surface)|\(reading)"
    }
}

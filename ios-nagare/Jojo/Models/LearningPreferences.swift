import Foundation
import SwiftUI

/// Appearance preference for the whole app (Feed, Vocab, and Profile share one scheme).
nonisolated enum AppearanceMode: String, CaseIterable, Identifiable, Sendable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// What to show under the video transcript.
///
/// Clips are streamed from their original YouTube source (never re-hosted).
/// Subtitles here are Jojo’s learner transcript + translations — not Crunchyroll
/// or other licensed closed captions. See ClipInfoSheet for the rights note.
nonisolated enum SubtitleMode: String, CaseIterable, Identifiable, Sendable {
    case japanese, english, both
    var id: String { rawValue }
    var title: String {
        switch self {
        case .japanese: "Japanese"
        case .english: "English"
        case .both: "Japanese + English"
        }
    }
    var showsJapanese: Bool { self == .japanese || self == .both }
    var showsEnglish: Bool { self == .english || self == .both }
}

/// Which definitions to prefer in the lookup popup and flashcards.
nonisolated enum DictionaryMode: String, CaseIterable, Identifiable, Sendable {
    case english, japanese, both
    var id: String { rawValue }
    var title: String {
        switch self {
        case .english: "English"
        case .japanese: "日本語 (monolingual)"
        case .both: "Both"
        }
    }
}

/// Study filters for the Vocab tab (POS buckets).
nonisolated enum StudyPosFilter: String, CaseIterable, Identifiable, Sendable {
    case all, verb, noun, adjective, particle, other
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: "Any type"
        case .verb: "Verbs"
        case .noun: "Nouns"
        case .adjective: "Adjectives"
        case .particle: "Particles"
        case .other: "Other"
        }
    }
    func matches(_ pos: String) -> Bool {
        let p = pos.lowercased()
        switch self {
        case .all: return true
        case .verb: return p == "verb"
        case .noun: return p == "noun" || p == "pronoun"
        case .adjective: return p.contains("adjective")
        case .particle: return p == "particle"
        case .other:
            return p != "verb" && p != "noun" && p != "pronoun"
                && !p.contains("adjective") && p != "particle"
        }
    }
}

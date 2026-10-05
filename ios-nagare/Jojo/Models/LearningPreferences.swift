import Foundation
import SwiftUI

/// Appearance for the main app. Light is cream paper. The other three are dark pages
/// with a different accent: sakura pink, plum, or orange.
nonisolated enum AppearanceMode: String, CaseIterable, Identifiable, Sendable {
    case light
    case sakura
    case plum
    case orange

    var id: String { rawValue }

    var title: String {
        switch self {
        case .light: "Light"
        case .sakura: "Sakura"
        case .plum: "Purple"
        case .orange: "Orange"
        }
    }

    var colorScheme: ColorScheme {
        self == .light ? .light : .dark
    }

    /// Older installs stored `system` or `dark`. Those open on the sakura night theme.
    static func resolve(_ raw: String) -> AppearanceMode {
        switch raw {
        case "light": .light
        case "plum", "purple": .plum
        case "orange": .orange
        case "sakura", "dark", "system", "": .sakura
        default: AppearanceMode(rawValue: raw) ?? .sakura
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

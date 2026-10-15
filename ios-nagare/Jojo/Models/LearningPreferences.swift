import Foundation
import SwiftUI

/// The two accents. Light and dark are versions of whichever one is selected.
nonisolated enum AccentTheme: String, CaseIterable, Identifiable, Sendable {
    case sakura, amber

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sakura: "Sakura"
        case .amber: "Amber"
        }
    }
}

/// How strong the halo is on karaoke words and the dictionary word.
nonisolated enum GlowLevel: String, CaseIterable, Identifiable, Sendable {
    case off, soft, glow, liquid

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: "Off"
        case .soft: "Soft"
        case .glow: "Glow"
        case .liquid: "Liquid"
        }
    }

    /// Share of the accent used in the halo. Zero removes it.
    var intensity: Double {
        switch self {
        case .off: 0
        case .soft: 0.35
        case .glow: 0.7
        case .liquid: 1
        }
    }

    var radius: CGFloat {
        switch self {
        case .off: 0
        case .soft: 4
        case .glow: 9
        case .liquid: 16
        }
    }
}

/// Light or dark paper for the selected accent.
nonisolated enum JojoScheme: String, CaseIterable, Identifiable, Sendable {
    case light, dark

    var id: String { rawValue }

    var title: String { self == .light ? "Light" : "Dark" }

    var colorScheme: ColorScheme { self == .light ? .light : .dark }
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

    /// Human label for radar pockets (not the `.all` filter).
    static func normalizedLabel(for pos: String) -> String {
        let p = pos.lowercased()
        if p == "verb" { return "Verbs" }
        if p == "noun" || p == "pronoun" { return "Nouns" }
        if p.contains("adjective") { return "Adjectives" }
        if p == "particle" { return "Particles" }
        return "Other"
    }
}

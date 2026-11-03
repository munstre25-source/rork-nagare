import Foundation
import SwiftUI

/// Rendering presets for the same enriched transcript; independent of content difficulty.
nonisolated enum LearningMode: String, CaseIterable, Identifiable, Sendable {
    case beginner, guided, advanced

    var id: String { rawValue }
    var title: String {
        switch self {
        case .beginner: "Beginner"
        case .guided: "Guided Immersion"
        case .advanced: "Full Immersion"
        }
    }
    var symbol: String {
        switch self {
        case .beginner: "leaf"
        case .guided: "safari"
        case .advanced: "laurel.leading"
        }
    }
    var display: SubtitleDisplaySettings {
        switch self {
        case .beginner: SubtitleDisplaySettings(furigana: true, romaji: true, english: .shown)
        case .guided: SubtitleDisplaySettings(furigana: true, romaji: false, english: .onTap)
        case .advanced: SubtitleDisplaySettings(furigana: false, romaji: false, english: .hidden)
        }
    }
}

nonisolated enum EnglishVisibility: String, CaseIterable, Identifiable, Sendable {
    case shown, onTap, hidden
    var id: String { rawValue }
    var title: String {
        switch self {
        case .shown: "On"
        case .onTap: "Tap"
        case .hidden: "Hidden"
        }
    }
    var next: Self {
        switch self {
        case .shown: .onTap
        case .onTap: .hidden
        case .hidden: .shown
        }
    }
}

/// How furigana sits above Japanese in the karaoke panel.
nonisolated enum FuriganaMode: String, CaseIterable, Identifiable, Sendable {
    case on, unknownOnly, off

    var id: String { rawValue }

    var title: String {
        switch self {
        case .on: "On"
        case .unknownOnly: "Unknown only"
        case .off: "Off"
        }
    }

    var shortLabel: String {
        switch self {
        case .on: "あ"
        case .unknownOnly: "あ·"
        case .off: "あ—"
        }
    }

    var showsAny: Bool { self != .off }

    var next: Self {
        switch self {
        case .on: .unknownOnly
        case .unknownOnly: .off
        case .off: .on
        }
    }

    /// Whether this token should draw furigana under the current mode.
    func shows(for familiarity: SRSState?) -> Bool {
        switch self {
        case .on: return true
        case .off: return false
        case .unknownOnly:
            switch familiarity {
            case .known, .easy: return false
            default: return true
            }
        }
    }
}

nonisolated struct SubtitleDisplaySettings: Equatable, Sendable {
    var japanese: Bool = true
    var furigana: Bool
    var romaji: Bool
    var english: EnglishVisibility
    var tapWords: Bool = true
    var furiganaMode: FuriganaMode = .on

    init(furigana: Bool, romaji: Bool, english: EnglishVisibility,
         japanese: Bool = true, tapWords: Bool = true,
         furiganaMode: FuriganaMode? = nil) {
        self.japanese = japanese
        self.furigana = furigana
        self.romaji = romaji
        self.english = english
        self.tapWords = tapWords
        self.furiganaMode = furiganaMode ?? (furigana ? .on : .off)
    }

    var learningMode: LearningMode? {
        LearningMode.allCases.first {
            $0.display.furigana == furigana
                && $0.display.romaji == romaji
                && $0.display.english == english
                && $0.display.japanese == japanese
                && $0.display.tapWords == tapWords
        }
    }
    var minimalJapanese: Bool { japanese && !furigana && !romaji && english == .hidden }
}

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

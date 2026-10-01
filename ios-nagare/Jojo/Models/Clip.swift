import Foundation

/// A single word-level unit of a transcript line.
nonisolated struct Token: Codable, Hashable, Sendable {
    var surface: String
    /// Kana reading, only present when the surface contains kanji.
    var reading: String?
    var altReadings: [String]
    var romaji: String
    var start: Double
    var end: Double
    var pos: String
    var conjugationClass: String?
    var jlpt: String?
    var definitions: [String]
    var jaDefinitions: [String]
    var formality: String?
    var tappable: Bool
    /// Dictionary form for conjugated stems (e.g. 食べ → 食べる).
    var baseForm: String?
    var baseReading: String?
    var baseRomaji: String?

    enum CodingKeys: String, CodingKey {
        case surface, reading, altReadings, romaji, start, end, pos, conjugationClass, jlpt, definitions, jaDefinitions, formality, tappable, baseForm, baseReading, baseRomaji
        case altReadingsSnake = "alt_readings"
        case conjugationSnake = "conjugation_class"
        case jaDefinitionsSnake = "ja_definitions"
    }

    init(surface: String, reading: String? = nil, altReadings: [String] = [], romaji: String, start: Double, end: Double,
         pos: String, conjugationClass: String? = nil, jlpt: String? = nil, definitions: [String] = [],
         jaDefinitions: [String] = [], formality: String? = nil, tappable: Bool = true,
         baseForm: String? = nil, baseReading: String? = nil, baseRomaji: String? = nil) {
        self.surface = surface
        self.reading = reading
        self.altReadings = altReadings
        self.romaji = romaji
        self.start = start
        self.end = end
        self.pos = pos
        self.conjugationClass = conjugationClass
        self.jlpt = jlpt
        self.definitions = definitions
        self.jaDefinitions = jaDefinitions
        self.formality = formality
        self.tappable = tappable
        self.baseForm = baseForm
        self.baseReading = baseReading
        self.baseRomaji = baseRomaji
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        surface = try c.decode(String.self, forKey: .surface)
        reading = try c.decodeIfPresent(String.self, forKey: .reading)
        altReadings = try c.decodeIfPresent([String].self, forKey: .altReadings)
            ?? c.decodeIfPresent([String].self, forKey: .altReadingsSnake) ?? []
        romaji = try c.decodeIfPresent(String.self, forKey: .romaji) ?? ""
        start = try c.decodeIfPresent(Double.self, forKey: .start) ?? 0
        end = try c.decodeIfPresent(Double.self, forKey: .end) ?? 0
        pos = try c.decodeIfPresent(String.self, forKey: .pos) ?? "word"
        conjugationClass = try c.decodeIfPresent(String.self, forKey: .conjugationClass)
            ?? c.decodeIfPresent(String.self, forKey: .conjugationSnake)
        jlpt = try c.decodeIfPresent(String.self, forKey: .jlpt)
        definitions = try c.decodeIfPresent([String].self, forKey: .definitions) ?? []
        jaDefinitions = try c.decodeIfPresent([String].self, forKey: .jaDefinitions)
            ?? c.decodeIfPresent([String].self, forKey: .jaDefinitionsSnake) ?? []
        formality = try c.decodeIfPresent(String.self, forKey: .formality)
        tappable = try c.decodeIfPresent(Bool.self, forKey: .tappable) ?? (pos != "punctuation")
        baseForm = try c.decodeIfPresent(String.self, forKey: .baseForm)
        baseReading = try c.decodeIfPresent(String.self, forKey: .baseReading)
        baseRomaji = try c.decodeIfPresent(String.self, forKey: .baseRomaji)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(surface, forKey: .surface)
        try c.encodeIfPresent(reading, forKey: .reading)
        try c.encode(altReadings, forKey: .altReadings)
        try c.encode(romaji, forKey: .romaji)
        try c.encode(start, forKey: .start)
        try c.encode(end, forKey: .end)
        try c.encode(pos, forKey: .pos)
        try c.encodeIfPresent(conjugationClass, forKey: .conjugationClass)
        try c.encodeIfPresent(jlpt, forKey: .jlpt)
        try c.encode(definitions, forKey: .definitions)
        try c.encode(jaDefinitions, forKey: .jaDefinitions)
        try c.encodeIfPresent(formality, forKey: .formality)
        try c.encode(tappable, forKey: .tappable)
        try c.encodeIfPresent(baseForm, forKey: .baseForm)
        try c.encodeIfPresent(baseReading, forKey: .baseReading)
        try c.encodeIfPresent(baseRomaji, forKey: .baseRomaji)
    }

    var containsKanji: Bool {
        surface.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) || $0.value == 0x3005 }
    }

    /// Furigana to show above the word, only for kanji-containing surfaces.
    var furigana: String? {
        guard containsKanji, let reading, !reading.isEmpty else { return nil }
        return reading
    }

    var allReadings: [String] {
        ([reading].compactMap { $0 } + altReadings).filter { !$0.isEmpty }
    }

    var dictionaryForm: String { baseForm ?? surface }
    var dictionaryReading: String { baseForm != nil ? (baseReading ?? "") : (reading ?? "") }
    var dictionaryRomaji: String { baseRomaji ?? romaji }
    var isPunctuation: Bool { pos == "punctuation" }
}

/// A transcript line with its translation and timing.
nonisolated struct Line: Codable, Hashable, Sendable {
    var tokens: [Token]
    var translation: String
    var start: Double
    var end: Double

    var text: String { tokens.map(\.surface).joined() }
}

/// A short video clip with its full transcript.
nonisolated struct Clip: Codable, Hashable, Identifiable, Sendable {
    var id: String
    /// YouTube video ID. Seed clips use "PLACEHOLDER_…" until a real ID is swapped in.
    var videoId: String
    var title: String
    var channelName: String
    var channelAvatarColor: String
    var category: String
    var difficulty: String
    var durationSec: Double
    var lines: [Line]
    var thumbnailGradient: [String]

    var categoryKind: ClipCategory { ClipCategory(rawValue: category) ?? .drama }
    var difficultyKind: Difficulty { Difficulty(rawValue: difficulty) ?? .beginner }

    /// True when `videoId` looks like a real 11-character YouTube ID.
    var hasRealVideo: Bool {
        guard videoId.count == 11, !videoId.uppercased().hasPrefix("PLACEHOLDER") else { return false }
        return videoId.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    }

    /// Bundled `Clips/{id}.mp4` (preferred in Simulator / Rork for reliable playback).
    var hasLocalVideo: Bool { Self.bundledVideoURL(for: id) != nil }

    /// Local file or YouTube — anything that isn't the simulated poster.
    var hasPlayableVideo: Bool { hasLocalVideo || hasRealVideo }

    static func bundledVideoURL(for clipId: String) -> URL? {
        let candidates: [(String?, String)] = [
            ("Clips", clipId),
            ("Resources/Clips", clipId),
            (nil, clipId),
        ]
        for (subdir, name) in candidates {
            if let subdir,
               let url = Bundle.main.url(forResource: name, withExtension: "mp4", subdirectory: subdir) {
                return url
            }
            if subdir == nil,
               let url = Bundle.main.url(forResource: name, withExtension: "mp4") {
                return url
            }
        }
        return nil
    }

    var youtubeURL: URL? {
        hasRealVideo ? URL(string: "https://www.youtube.com/watch?v=\(videoId)") : nil
    }

    func lineIndex(at time: Double) -> Int {
        guard !lines.isEmpty else { return 0 }
        var index = 0
        for (i, line) in lines.enumerated() where line.start - 0.45 <= time {
            index = i
        }
        return index
    }
}

nonisolated enum ClipCategory: String, CaseIterable, Codable, Sendable, Identifiable {
    case anime, drama, variety, vtuber, interview, kids, gaming

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .anime: "Anime"
        case .drama: "Slice-of-Life"
        case .variety: "Variety"
        case .vtuber: "VTuber"
        case .interview: "Street Interview"
        case .kids: "Kids"
        case .gaming: "Gaming"
        }
    }

    var symbol: String {
        switch self {
        case .anime: "sparkles"
        case .drama: "cup.and.saucer.fill"
        case .variety: "star.bubble.fill"
        case .vtuber: "person.wave.2.fill"
        case .interview: "mic.fill"
        case .kids: "balloon.2.fill"
        case .gaming: "gamecontroller.fill"
        }
    }

    var sourceType: SourceType {
        switch self {
        case .anime, .kids: .animated
        case .drama, .variety, .interview: .liveAction
        case .vtuber, .gaming: .streamer
        }
    }
}

nonisolated enum SourceType: String, CaseIterable, Sendable, Identifiable {
    case animated, liveAction, streamer
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .animated: "Animated"
        case .liveAction: "Live action"
        case .streamer: "Streams"
        }
    }
}

nonisolated enum Difficulty: String, CaseIterable, Codable, Sendable, Identifiable {
    case beginner = "Beginner"
    case intermediate = "Intermediate"
    case advanced = "Advanced"

    var id: String { rawValue }
    var rank: Int {
        switch self {
        case .beginner: 0
        case .intermediate: 1
        case .advanced: 2
        }
    }
}

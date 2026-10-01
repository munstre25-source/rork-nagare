import Foundation

/// An entry in the bundled local dictionary (~300+ common N5–N3 words).
nonisolated struct DictionaryEntry: Codable, Hashable, Sendable {
    var surface: String
    var readings: [String]
    var romaji: String
    var pos: String
    var jlpt: String?
    var definitions: [String]
    /// Japanese-to-Japanese glosses for monolingual study (optional).
    var jaDefinitions: [String]
    var conjugationClass: String?
    var formality: String?
    var baseForm: String?
    var baseReading: String?
    var baseRomaji: String?

    enum CodingKeys: String, CodingKey {
        case surface, readings, romaji, pos, jlpt, definitions, jaDefinitions, conjugationClass, formality, baseForm, baseReading, baseRomaji
        case jaDefinitionsSnake = "ja_definitions"
    }

    init(surface: String, readings: [String], romaji: String, pos: String, jlpt: String? = nil,
         definitions: [String], jaDefinitions: [String] = [], conjugationClass: String? = nil,
         formality: String? = nil, baseForm: String? = nil, baseReading: String? = nil, baseRomaji: String? = nil) {
        self.surface = surface
        self.readings = readings
        self.romaji = romaji
        self.pos = pos
        self.jlpt = jlpt
        self.definitions = definitions
        self.jaDefinitions = jaDefinitions
        self.conjugationClass = conjugationClass
        self.formality = formality
        self.baseForm = baseForm
        self.baseReading = baseReading
        self.baseRomaji = baseRomaji
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        surface = try c.decode(String.self, forKey: .surface)
        readings = try c.decodeIfPresent([String].self, forKey: .readings) ?? []
        romaji = try c.decodeIfPresent(String.self, forKey: .romaji) ?? ""
        pos = try c.decodeIfPresent(String.self, forKey: .pos) ?? "word"
        jlpt = try c.decodeIfPresent(String.self, forKey: .jlpt)
        definitions = try c.decodeIfPresent([String].self, forKey: .definitions) ?? []
        jaDefinitions = try c.decodeIfPresent([String].self, forKey: .jaDefinitions)
            ?? c.decodeIfPresent([String].self, forKey: .jaDefinitionsSnake) ?? []
        conjugationClass = try c.decodeIfPresent(String.self, forKey: .conjugationClass)
        formality = try c.decodeIfPresent(String.self, forKey: .formality)
        baseForm = try c.decodeIfPresent(String.self, forKey: .baseForm)
        baseReading = try c.decodeIfPresent(String.self, forKey: .baseReading)
        baseRomaji = try c.decodeIfPresent(String.self, forKey: .baseRomaji)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(surface, forKey: .surface)
        try c.encode(readings, forKey: .readings)
        try c.encode(romaji, forKey: .romaji)
        try c.encode(pos, forKey: .pos)
        try c.encodeIfPresent(jlpt, forKey: .jlpt)
        try c.encode(definitions, forKey: .definitions)
        try c.encode(jaDefinitions, forKey: .jaDefinitions)
        try c.encodeIfPresent(conjugationClass, forKey: .conjugationClass)
        try c.encodeIfPresent(formality, forKey: .formality)
        try c.encodeIfPresent(baseForm, forKey: .baseForm)
        try c.encodeIfPresent(baseReading, forKey: .baseReading)
        try c.encodeIfPresent(baseRomaji, forKey: .baseRomaji)
    }
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

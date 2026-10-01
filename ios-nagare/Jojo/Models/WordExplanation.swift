import Foundation

/// The resolved explanation shown in the tap-to-understand popup.
nonisolated struct WordExplanation: Codable, Hashable, Sendable {
    enum Source: String, Codable, Sendable {
        case seed, dictionary, cache, live, fallback
    }

    var word: String
    var readings: [String]
    var romaji: String
    var pos: String
    var conjugationClass: String?
    var jlpt: String?
    var definitions: [String]
    var jaDefinitions: [String]
    var formalityNote: String?
    var source: Source

    /// Builds an instant explanation from the token's own seed data, if it has definitions.
    static func fromToken(_ token: Token) -> WordExplanation? {
        guard !token.definitions.isEmpty || !token.jaDefinitions.isEmpty else { return nil }
        return WordExplanation(
            word: token.surface,
            readings: token.allReadings,
            romaji: token.romaji,
            pos: token.pos,
            conjugationClass: token.conjugationClass,
            jlpt: token.jlpt,
            definitions: token.definitions,
            jaDefinitions: token.jaDefinitions,
            formalityNote: token.formality,
            source: .seed
        )
    }

    static func fromDictionary(_ entry: DictionaryEntry, surface: String) -> WordExplanation {
        WordExplanation(
            word: surface,
            readings: entry.readings,
            romaji: entry.romaji,
            pos: entry.pos,
            conjugationClass: entry.conjugationClass,
            jlpt: entry.jlpt,
            definitions: entry.definitions,
            jaDefinitions: entry.jaDefinitions,
            formalityNote: entry.formality,
            source: .dictionary
        )
    }

    /// Static fallback built from whatever the token carries. Never empty.
    static func fallback(for token: Token) -> WordExplanation {
        WordExplanation(
            word: token.surface,
            readings: token.allReadings,
            romaji: token.romaji,
            pos: token.pos,
            conjugationClass: token.conjugationClass,
            jlpt: token.jlpt,
            definitions: token.definitions.isEmpty ? ["Meaning available when you're back online"] : token.definitions,
            jaDefinitions: token.jaDefinitions,
            formalityNote: token.formality,
            source: .fallback
        )
    }

    func displayDefinitions(mode: DictionaryMode) -> [String] {
        switch mode {
        case .english:
            return definitions.isEmpty ? jaDefinitions : definitions
        case .japanese:
            if !jaDefinitions.isEmpty { return jaDefinitions }
            // Soft monolingual fallback when JA gloss isn't available yet.
            return definitions.isEmpty ? ["（定義を準備中）"] : definitions.map { "（英）\($0)" }
        case .both:
            var out = jaDefinitions
            for d in definitions where !out.contains(d) { out.append(d) }
            return out.isEmpty ? ["Meaning available when you're back online"] : out
        }
    }

    enum CodingKeys: String, CodingKey {
        case word, readings, romaji, pos, conjugationClass, jlpt, definitions, jaDefinitions, formalityNote, source
        case jaDefinitionsSnake = "ja_definitions"
    }

    init(word: String, readings: [String], romaji: String, pos: String, conjugationClass: String?,
         jlpt: String?, definitions: [String], jaDefinitions: [String] = [], formalityNote: String?, source: Source) {
        self.word = word
        self.readings = readings
        self.romaji = romaji
        self.pos = pos
        self.conjugationClass = conjugationClass
        self.jlpt = jlpt
        self.definitions = definitions
        self.jaDefinitions = jaDefinitions
        self.formalityNote = formalityNote
        self.source = source
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        word = try c.decode(String.self, forKey: .word)
        readings = try c.decodeIfPresent([String].self, forKey: .readings) ?? []
        romaji = try c.decodeIfPresent(String.self, forKey: .romaji) ?? ""
        pos = try c.decodeIfPresent(String.self, forKey: .pos) ?? "word"
        conjugationClass = try c.decodeIfPresent(String.self, forKey: .conjugationClass)
        jlpt = try c.decodeIfPresent(String.self, forKey: .jlpt)
        definitions = try c.decodeIfPresent([String].self, forKey: .definitions) ?? []
        jaDefinitions = try c.decodeIfPresent([String].self, forKey: .jaDefinitions)
            ?? c.decodeIfPresent([String].self, forKey: .jaDefinitionsSnake) ?? []
        formalityNote = try c.decodeIfPresent(String.self, forKey: .formalityNote)
        source = try c.decodeIfPresent(Source.self, forKey: .source) ?? .fallback
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(word, forKey: .word)
        try c.encode(readings, forKey: .readings)
        try c.encode(romaji, forKey: .romaji)
        try c.encode(pos, forKey: .pos)
        try c.encodeIfPresent(conjugationClass, forKey: .conjugationClass)
        try c.encodeIfPresent(jlpt, forKey: .jlpt)
        try c.encode(definitions, forKey: .definitions)
        try c.encode(jaDefinitions, forKey: .jaDefinitions)
        try c.encodeIfPresent(formalityNote, forKey: .formalityNote)
        try c.encode(source, forKey: .source)
    }
}

/// Response of the Edge Function for `kind: "lookup"`.
nonisolated struct LookupResponse: Codable, Sendable {
    var word: String
    var readings: [String]?
    var romaji: String?
    var pos: String?
    var conjugationClass: String?
    var definitions: [String]?
    var jaDefinitions: [String]?
    var formalityNote: String?
    var audioHint: String?

    enum CodingKeys: String, CodingKey {
        case word, readings, romaji, pos, definitions
        case conjugationClass = "conjugation_class"
        case jaDefinitions = "ja_definitions"
        case formalityNote = "formality_note"
        case audioHint = "audio_hint"
    }
}

/// Response of the Edge Function for `kind: "context"`, also used for offline fallback.
nonisolated struct ContextExplanation: Codable, Hashable, Sendable {
    var contextualExplanation: String
    var examples: [String]
    var relatedWords: [String]
    var isFallback: Bool = false

    enum CodingKeys: String, CodingKey {
        case contextualExplanation = "contextual_explanation"
        case examples
        case relatedWords = "related_words"
        case isFallback = "is_fallback"
    }

    init(contextualExplanation: String, examples: [String], relatedWords: [String], isFallback: Bool = false) {
        self.contextualExplanation = contextualExplanation
        self.examples = examples
        self.relatedWords = relatedWords
        self.isFallback = isFallback
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        contextualExplanation = try c.decodeIfPresent(String.self, forKey: .contextualExplanation) ?? ""
        examples = try c.decodeIfPresent([String].self, forKey: .examples) ?? []
        relatedWords = try c.decodeIfPresent([String].self, forKey: .relatedWords) ?? []
        isFallback = try c.decodeIfPresent(Bool.self, forKey: .isFallback) ?? false
    }
}

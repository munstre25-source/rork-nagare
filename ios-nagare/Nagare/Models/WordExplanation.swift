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
    var formalityNote: String?
    var source: Source

    /// Builds an instant explanation from the token's own seed data, if it has definitions.
    static func fromToken(_ token: Token) -> WordExplanation? {
        guard !token.definitions.isEmpty else { return nil }
        return WordExplanation(
            word: token.surface,
            readings: token.allReadings,
            romaji: token.romaji,
            pos: token.pos,
            conjugationClass: token.conjugationClass,
            jlpt: token.jlpt,
            definitions: token.definitions,
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
            formalityNote: token.formality,
            source: .fallback
        )
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
    var formalityNote: String?
    var audioHint: String?

    enum CodingKeys: String, CodingKey {
        case word, readings, romaji, pos, definitions
        case conjugationClass = "conjugation_class"
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

import Foundation

/// Bundled local dictionary, checked synchronously before any network call.
nonisolated struct LocalLexicon: Sendable {
    let entries: [String: DictionaryEntry]

    static let empty = LocalLexicon(entries: [:])

    func entry(for surface: String) -> DictionaryEntry? {
        entries[surface]
    }

    /// Instant explanation: seed token data first, then the local dictionary (surface, then base form).
    func instantExplanation(for token: Token) -> WordExplanation? {
        if let seeded = WordExplanation.fromToken(token) { return seeded }
        if let entry = entries[token.surface] { return .fromDictionary(entry, surface: token.surface) }
        if let base = token.baseForm, let entry = entries[base] {
            var explanation = WordExplanation.fromDictionary(entry, surface: token.surface)
            explanation.readings = token.allReadings.isEmpty ? entry.readings : token.allReadings
            explanation.romaji = token.romaji.isEmpty ? entry.romaji : token.romaji
            return explanation
        }
        return nil
    }

    /// Enriches a token with dictionary data (used for remote clips that ship without definitions).
    func enriched(_ token: Token) -> Token {
        guard token.definitions.isEmpty, token.tappable else { return token }
        guard let entry = entries[token.surface] ?? token.baseForm.flatMap({ entries[$0] }) else { return token }
        var copy = token
        copy.definitions = entry.definitions
        if copy.jlpt == nil { copy.jlpt = entry.jlpt }
        if copy.conjugationClass == nil { copy.conjugationClass = entry.conjugationClass }
        if copy.reading == nil, copy.containsKanji { copy.reading = entry.readings.first }
        if copy.romaji.isEmpty { copy.romaji = entry.romaji }
        return copy
    }
}

/// Romaji/kana normalization helpers for search.
nonisolated enum JapaneseText {
    /// Converts katakana to hiragana so searches match either script.
    static func hiragana(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.map { scalar in
            if (0x30A1...0x30F6).contains(scalar.value), let converted = Unicode.Scalar(scalar.value - 0x60) {
                return converted
            }
            return scalar
        }))
    }

    static func normalizedRomaji(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "ā", with: "aa")
            .replacingOccurrences(of: "ō", with: "ou")
            .replacingOccurrences(of: "ū", with: "uu")
    }

    /// Stable FNV-1a hash of a sentence with whitespace and punctuation stripped.
    static func sentenceHash(_ sentence: String) -> String {
        let normalized = sentence.unicodeScalars.filter {
            !CharacterSet.whitespacesAndNewlines.contains($0) && !CharacterSet.punctuationCharacters.contains($0)
                && !"、。!?!?「」…".unicodeScalars.contains($0)
        }
        var hash: UInt64 = 0xcbf29ce484222325
        for scalar in normalized {
            for byte in String(scalar).utf8 {
                hash ^= UInt64(byte)
                hash = hash &* 0x100000001b3
            }
        }
        return String(hash, radix: 16)
    }
}

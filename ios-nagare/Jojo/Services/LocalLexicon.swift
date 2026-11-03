import Foundation

/// Bundled local dictionary, checked synchronously before any network call.
nonisolated struct LocalLexicon: Sendable {
    let entries: [String: DictionaryEntry]

    static let empty = LocalLexicon(entries: [:])

    func entry(for surface: String) -> DictionaryEntry? {
        let normalized = surface.precomposedStringWithCompatibilityMapping
        for key in [surface, normalized, JapaneseText.hiragana(normalized)] {
            if let entry = entries[key],
               !WordExplanation.meaningfulDefinitions(entry.definitions).isEmpty
                || !WordExplanation.meaningfulDefinitions(entry.jaDefinitions).isEmpty {
                return entry
            }
        }
        return nil
    }

    /// Prefer the transcript's base form. If it is absent, resolve common inflections
    /// against real dictionary entries; never assign a meaning by a suffix alone.
    private func entry(for token: Token) -> DictionaryEntry? {
        if let exact = entry(for: token.surface) { return exact }
        if let base = token.baseForm, let exact = entry(for: base) { return exact }
        let pos = token.pos.lowercased()
        let isVerb = pos.contains("verb") && !pos.contains("adverb")
        let rules: [(String, String)]
        if isVerb {
            rules = [
                ("きました", "くる"), ("きます", "くる"), ("きた", "くる"), ("きて", "くる"),
                ("しました", "する"), ("します", "する"), ("した", "する"), ("して", "する"),
                ("来ました", "来る"), ("来ます", "来る"), ("来た", "来る"), ("来て", "来る"),
                ("ませんでした", "る"), ("ました", "る"), ("ません", "る"), ("ます", "る"),
                ("なかった", "る"), ("ない", "る"), ("た", "る"), ("て", "る"),
                ("った", "う"), ("った", "つ"), ("った", "る"),
                ("んだ", "む"), ("んだ", "ぶ"), ("んだ", "ぬ"),
                ("いた", "く"), ("いだ", "ぐ"), ("した", "す"),
                ("って", "う"), ("って", "つ"), ("って", "る"),
                ("んで", "む"), ("んで", "ぶ"), ("んで", "ぬ"),
                ("いて", "く"), ("いで", "ぐ")
            ]
        } else if pos.contains("adj") {
            rules = [("くなかった", "い"), ("くない", "い"), ("かった", "い")]
        } else {
            return nil
        }
        var matches: [String: DictionaryEntry] = [:]
        for (suffix, ending) in rules where token.surface.hasSuffix(suffix) {
            let stem = String(token.surface.dropLast(suffix.count))
            guard !stem.isEmpty, let candidate = entry(for: stem + ending) else { continue }
            let candidatePOS = candidate.pos.lowercased()
            guard (isVerb && candidatePOS.contains("verb") && !candidatePOS.contains("adverb"))
                || (pos.contains("adj") && candidatePOS.contains("adj")) else { continue }
            matches[candidate.surface] = candidate
        }
        // Ambiguous forms keep their saved sentence context rather than a guessed definition.
        return matches.count == 1 ? matches.values.first : nil
    }

    /// Instant explanation: seed token data first, then the local dictionary (surface, then base form).
    func instantExplanation(for token: Token) -> WordExplanation? {
        if var seeded = WordExplanation.fromToken(token) {
            if seeded.jaDefinitions.isEmpty,
               let entry = entry(for: token),
               !entry.jaDefinitions.isEmpty {
                seeded.jaDefinitions = entry.jaDefinitions
            }
            return seeded
        }
        if let entry = entry(for: token) {
            var explanation = WordExplanation.fromDictionary(entry, surface: token.surface)
            explanation.readings = token.allReadings.isEmpty ? entry.readings : token.allReadings
            explanation.romaji = token.romaji.isEmpty ? entry.romaji : token.romaji
            return explanation
        }
        return nil
    }

    /// Enriches a token with dictionary data (used for remote clips that ship without definitions).
    func enriched(_ token: Token) -> Token {
        guard token.tappable else { return token }
        guard token.definitions.isEmpty || token.jaDefinitions.isEmpty else { return token }
        guard let entry = entry(for: token) else { return token }
        var copy = token
        if copy.definitions.isEmpty { copy.definitions = entry.definitions }
        if copy.jaDefinitions.isEmpty { copy.jaDefinitions = entry.jaDefinitions }
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

    /// Hiragana or katakana (including prolonged sound mark).
    static func isKana(_ scalar: Unicode.Scalar) -> Bool {
        let v = scalar.value
        return (0x3041...0x3096).contains(v)
            || (0x30A1...0x30FA).contains(v)
            || v == 0x30FC
            || v == 0x309D || v == 0x309E
            || v == 0x30FD || v == 0x30FE
    }

    /// CJK unified ideograph or iteration mark 々.
    static func isKanji(_ scalar: Unicode.Scalar) -> Bool {
        let v = scalar.value
        return (0x4E00...0x9FFF).contains(v) || v == 0x3005
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

/// One visual piece of a Japanese word: kana alone, or kanji with optional furigana above.
nonisolated struct RubySegment: Hashable, Sendable {
    var text: String
    var reading: String?

    /// Strip matching leading/trailing kana from `surface`/`reading` so furigana sits
    /// only over the kanji core (動いて → [動:うご][いて]). Ambiguous pairs fall back
    /// to a single whole-word segment.
    static func split(surface: String, reading: String?) -> [RubySegment] {
        guard let raw = reading, !raw.isEmpty else {
            return [RubySegment(text: surface, reading: nil)]
        }
        let hasKanji = surface.unicodeScalars.contains(where: JapaneseText.isKanji)
        guard hasKanji else {
            return [RubySegment(text: surface, reading: nil)]
        }

        var chars = Array(surface)
        var kana = Array(JapaneseText.hiragana(raw))
        var leading: [Character] = []
        var trailing: [Character] = []

        while let first = chars.first,
              let scalar = first.unicodeScalars.first,
              JapaneseText.isKana(scalar),
              let kFirst = kana.first,
              JapaneseText.hiragana(String(first)) == String(kFirst) {
            leading.append(first)
            chars.removeFirst()
            kana.removeFirst()
        }

        while let last = chars.last,
              let scalar = last.unicodeScalars.first,
              JapaneseText.isKana(scalar),
              let kLast = kana.last,
              JapaneseText.hiragana(String(last)) == String(kLast) {
            trailing.insert(last, at: 0)
            chars.removeLast()
            kana.removeLast()
        }

        let core = String(chars)
        let coreReading = String(kana)
        // Core must still contain kanji; otherwise the reading didn't match and we fall back.
        guard !core.isEmpty, core.unicodeScalars.contains(where: JapaneseText.isKanji) else {
            return [RubySegment(text: surface, reading: JapaneseText.hiragana(raw))]
        }
        // Empty core reading with leftover kanji is ambiguous (e.g. mismatched data).
        guard !coreReading.isEmpty else {
            return [RubySegment(text: surface, reading: JapaneseText.hiragana(raw))]
        }

        var segments: [RubySegment] = []
        if !leading.isEmpty {
            segments.append(RubySegment(text: String(leading), reading: nil))
        }
        segments.append(RubySegment(text: core, reading: coreReading))
        if !trailing.isEmpty {
            segments.append(RubySegment(text: String(trailing), reading: nil))
        }
        return segments
    }
}

import Foundation

/// Optional pitch-accent hint for the dictionary card.
/// Prefers an explicit lexicon / token value; otherwise estimates a common pattern when confident.
enum PitchAccent {
    /// NHK-style drop index: 0 = heiban, 1 = atamadaka, n = nakadaka / odaka.
    static func resolve(explicit: Int?, reading: String?, surface: String) -> Int? {
        if let explicit, explicit >= 0 { return explicit }
        let kana = JapaneseText.hiragana(reading?.isEmpty == false ? reading! : surface)
        guard kana.count >= 2, kana.count <= 6 else { return nil }
        // Only estimate for short native-looking words; skip punctuation and romaji-only.
        guard kana.unicodeScalars.allSatisfy({ (0x3040...0x309F).contains($0.value) || (0x30A0...0x30FF).contains($0.value) }) else {
            return nil
        }
        // Heuristic: many two-mora particles / light words are heiban; longer verbs often drop after stem.
        if kana.count == 2 { return 0 }
        if kana.hasSuffix("い") && kana.count == 3 { return 0 }
        if kana.hasSuffix("る") || kana.hasSuffix("う") { return 2 }
        return nil
    }

    static func label(_ accent: Int, moraCount: Int) -> String {
        switch accent {
        case 0: return "Heiban (0)"
        case 1: return "Atamadaka (1)"
        case moraCount: return "Odaka (\(accent))"
        default: return "Nakadaka (\(accent))"
        }
    }

    /// Compact chip text, e.g. "Pitch 0".
    static func chip(_ accent: Int) -> String {
        "Pitch \(accent)"
    }
}

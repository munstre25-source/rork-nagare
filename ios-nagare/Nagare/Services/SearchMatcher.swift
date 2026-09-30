import Foundation

/// A clip line containing the searched word.
nonisolated struct SearchHit: Identifiable, Hashable, Sendable {
    let clip: Clip
    let lineIndex: Int
    var id: String { "\(clip.id)#\(lineIndex)" }
}

/// Matches kanji, kana (hiragana or katakana) or romaji queries against tokens.
nonisolated enum SearchMatcher {
    static func tokenMatches(_ token: Token, query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, token.tappable else { return false }
        let isLatin = q.unicodeScalars.allSatisfy { $0.isASCII }
        if isLatin {
            let nq = JapaneseText.normalizedRomaji(q)
            guard nq.count >= 2 else { return JapaneseText.normalizedRomaji(token.romaji) == nq }
            return JapaneseText.normalizedRomaji(token.romaji).hasPrefix(nq)
                || JapaneseText.normalizedRomaji(token.dictionaryRomaji).hasPrefix(nq)
        }
        let hq = JapaneseText.hiragana(q)
        if token.surface.contains(q) || q.contains(token.surface) && token.surface.count >= 2 { return true }
        if token.dictionaryForm.contains(q) { return true }
        let readings = token.allReadings + [token.baseReading].compactMap { $0 }
        if readings.contains(where: { JapaneseText.hiragana($0).hasPrefix(hq) }) { return true }
        return JapaneseText.hiragana(token.surface).hasPrefix(hq)
    }

    static func search(_ query: String, in clips: [Clip]) -> [SearchHit] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        var hits: [SearchHit] = []
        for clip in clips {
            for (index, line) in clip.lines.enumerated() where line.tokens.contains(where: { tokenMatches($0, query: query) }) {
                hits.append(SearchHit(clip: clip, lineIndex: index))
            }
        }
        return hits
    }
}

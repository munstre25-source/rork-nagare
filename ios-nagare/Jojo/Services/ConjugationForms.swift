import Foundation

/// Common conjugation rows for the dictionary card. Uses `baseForm` + `conjugationClass` when present.
enum ConjugationForms {
    struct Row: Identifiable, Hashable, Sendable {
        var id: String { label + surface }
        var label: String
        var surface: String
    }

    static func rows(for token: Token) -> [Row] {
        rows(
            surface: token.surface,
            base: token.baseForm ?? token.surface,
            conjugationClass: token.conjugationClass,
            pos: token.pos
        )
    }

    static func rows(surface: String, base: String, conjugationClass: String?, pos: String) -> [Row] {
        let klass = (conjugationClass ?? "").lowercased()
        let posLower = pos.lowercased()
        guard posLower.contains("verb") || posLower.contains("adj") || !klass.isEmpty else {
            if base != surface {
                return [Row(label: "Dictionary", surface: base), Row(label: "In clip", surface: surface)]
            }
            return []
        }

        if posLower.contains("i-adj") || posLower.contains("い形容") || klass.contains("i-adj") {
            return iAdjective(base: base, surface: surface)
        }
        if posLower.contains("na-adj") || posLower.contains("な形容") || klass.contains("na-adj") {
            return [
                Row(label: "Dictionary", surface: base),
                Row(label: "Adverb", surface: base + "に"),
                Row(label: "Past", surface: base + "だった"),
                Row(label: "In clip", surface: surface)
            ].uniqued()
        }

        if klass.contains("ichidan") || klass.contains("ru-verb") || klass.contains("一段") {
            return ichidan(base: base, surface: surface)
        }
        if klass.contains("suru") || base.hasSuffix("する") {
            return suru(base: base, surface: surface)
        }
        if klass.contains("kuru") || base == "来る" || base == "くる" {
            return [
                Row(label: "Dictionary", surface: base),
                Row(label: "Masu", surface: "来ます"),
                Row(label: "Te", surface: "来て"),
                Row(label: "Nai", surface: "来ない"),
                Row(label: "In clip", surface: surface)
            ].uniqued()
        }
        if klass.contains("godan") || klass.contains("u-verb") || klass.contains("五段") || posLower.contains("verb") {
            return godan(base: base, surface: surface)
        }
        if base != surface {
            return [Row(label: "Dictionary", surface: base), Row(label: "In clip", surface: surface)]
        }
        return []
    }

    private static func ichidan(base: String, surface: String) -> [Row] {
        let stem = base.hasSuffix("る") ? String(base.dropLast()) : base
        return [
            Row(label: "Dictionary", surface: base),
            Row(label: "Masu", surface: stem + "ます"),
            Row(label: "Te", surface: stem + "て"),
            Row(label: "Nai", surface: stem + "ない"),
            Row(label: "Potential", surface: stem + "られる"),
            Row(label: "In clip", surface: surface)
        ].uniqued()
    }

    private static func suru(base: String, surface: String) -> [Row] {
        let stem = base.hasSuffix("する") ? String(base.dropLast(2)) : base
        return [
            Row(label: "Dictionary", surface: base),
            Row(label: "Masu", surface: stem + "します"),
            Row(label: "Te", surface: stem + "して"),
            Row(label: "Nai", surface: stem + "しない"),
            Row(label: "In clip", surface: surface)
        ].uniqued()
    }

    private static func iAdjective(base: String, surface: String) -> [Row] {
        let stem = base.hasSuffix("い") ? String(base.dropLast()) : base
        return [
            Row(label: "Dictionary", surface: base),
            Row(label: "Adverb", surface: stem + "く"),
            Row(label: "Past", surface: stem + "かった"),
            Row(label: "Negative", surface: stem + "くない"),
            Row(label: "In clip", surface: surface)
        ].uniqued()
    }

    private static func godan(base: String, surface: String) -> [Row] {
        guard let last = base.last else {
            return [Row(label: "Dictionary", surface: base), Row(label: "In clip", surface: surface)]
        }
        let stem = String(base.dropLast())
        let map: [Character: (masu: String, te: String, nai: String, pot: String)] = [
            "う": ("います", "って", "わない", "える"),
            "つ": ("ちます", "って", "たない", "てる"),
            "る": ("ります", "って", "らない", "れる"),
            "く": ("きます", "いて", "かない", "ける"),
            "ぐ": ("ぎます", "いで", "がない", "げる"),
            "す": ("します", "して", "さない", "せる"),
            "む": ("みます", "んで", "まない", "める"),
            "ぶ": ("びます", "んで", "ばない", "べる"),
            "ぬ": ("にます", "んで", "なない", "ねる")
        ]
        guard let forms = map[last] else {
            return [Row(label: "Dictionary", surface: base), Row(label: "In clip", surface: surface)]
        }
        return [
            Row(label: "Dictionary", surface: base),
            Row(label: "Masu", surface: stem + forms.masu),
            Row(label: "Te", surface: stem + forms.te),
            Row(label: "Nai", surface: stem + forms.nai),
            Row(label: "Potential", surface: stem + forms.pot),
            Row(label: "In clip", surface: surface)
        ].uniqued()
    }
}

private extension Array where Element == ConjugationForms.Row {
    func uniqued() -> [ConjugationForms.Row] {
        var seen = Set<String>()
        return filter { seen.insert($0.surface + $0.label).inserted }
    }
}

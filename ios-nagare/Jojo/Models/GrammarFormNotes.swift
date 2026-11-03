import Foundation

/// Hand-written one-line notes for common particles and conjugations.
/// No network — keeps the dictionary card useful offline and credit-free.
nonisolated enum GrammarFormNotes {
    struct Note: Hashable, Sendable {
        var form: String
        var meaning: String
    }

    /// True for particles and auxiliaries that should open as a preview, not auto-save.
    static func isGrammarOnly(_ token: Token) -> Bool {
        let pos = token.pos.lowercased()
        if pos == "particle" || pos.contains("particle") { return true }
        if pos == "auxiliary" || pos.contains("aux") { return true }
        if ["は", "が", "を", "に", "で", "の", "と", "へ", "から", "まで", "より",
            "ね", "よ", "な", "か", "さ", "ぞ", "わ", "や", "も", "ば",
            "です", "ます", "だ", "である"].contains(token.surface) {
            return true
        }
        return false
    }

    /// One-line note for the compact card, e.g. "from いる · ている: ongoing action".
    static func line(for token: Token) -> String? {
        guard let note = note(for: token) else {
            if let base = token.baseForm, base != token.surface {
                return "from \(base)"
            }
            return nil
        }
        if let base = token.baseForm, base != token.surface {
            return "from \(base) · \(note.form): \(note.meaning)"
        }
        return "\(note.form): \(note.meaning)"
    }

    static func note(for token: Token) -> Note? {
        let surface = token.surface
        let base = token.baseForm ?? ""
        let reading = JapaneseText.hiragana(token.reading ?? token.baseReading ?? "")
        let conj = (token.conjugationClass ?? "").lowercased()
        let pos = token.pos.lowercased()

        if let particle = particles[surface] {
            return Note(form: surface, meaning: particle)
        }

        // Progressive / resultative ている / てる
        if surface.hasSuffix("ている") || surface.hasSuffix("てる")
            || surface.hasSuffix("でいる") || surface.hasSuffix("でる")
            || reading.hasSuffix("ている") || reading.hasSuffix("てる")
            || conj.contains("teiru") || conj.contains("progressive") {
            return Note(form: "ている", meaning: "ongoing or resulting state")
        }
        if surface.hasSuffix("ています") || surface.hasSuffix("でいます") {
            return Note(form: "ています", meaning: "polite ongoing or resulting state")
        }

        // ちゃう / じゃう / てしまう
        if surface.hasSuffix("ちゃう") || surface.hasSuffix("じゃう")
            || surface.hasSuffix("てしまう") || surface.hasSuffix("でしまう")
            || conj.contains("chaimau") || conj.contains("teshimau") {
            return Note(form: "ちゃう", meaning: "completely / accidentally / regrettably")
        }
        if surface.hasSuffix("ちゃった") || surface.hasSuffix("じゃった")
            || surface.hasSuffix("てしまった") {
            return Note(form: "ちゃった", meaning: "ended up / regrettably did")
        }

        if surface.hasSuffix("たい") || conj.contains("tai") {
            return Note(form: "たい", meaning: "want to…")
        }
        if surface.hasSuffix("ない") && (pos.contains("verb") || conj.contains("nai") || !base.isEmpty) {
            if !["ない"].contains(surface) {
                return Note(form: "ない", meaning: "negative / not…")
            }
        }
        if surface.hasSuffix("ません") {
            return Note(form: "ません", meaning: "polite negative")
        }
        if surface.hasSuffix("ました") {
            return Note(form: "ました", meaning: "polite past")
        }
        if surface.hasSuffix("ます") {
            return Note(form: "ます", meaning: "polite non-past")
        }
        if surface.hasSuffix("た") || surface.hasSuffix("だ"), pos.contains("verb") || !base.isEmpty {
            if surface.count > 1 {
                return Note(form: "た", meaning: "past / completed")
            }
        }
        if surface.hasSuffix("て") || surface.hasSuffix("で"), pos.contains("verb") || conj.contains("te") {
            if surface.count > 1 {
                return Note(form: "て-form", meaning: "connective / request form")
            }
        }
        if surface.hasSuffix("よう") || surface.hasSuffix("おう") || conj.contains("volitional") {
            return Note(form: "volitional", meaning: "let's… / I will…")
        }
        if surface.hasSuffix("れる") || surface.hasSuffix("られる") || conj.contains("passive") || conj.contains("potential") {
            return Note(form: "れる/られる", meaning: "passive or potential")
        }
        if surface.hasSuffix("せる") || surface.hasSuffix("させる") || conj.contains("causative") {
            return Note(form: "せる/させる", meaning: "causative — make/let someone…")
        }
        if surface.hasSuffix("ば") && surface.count > 1 {
            return Note(form: "ば", meaning: "if / when…")
        }
        if surface.hasSuffix("たら") {
            return Note(form: "たら", meaning: "if / when / after…")
        }
        if surface.hasSuffix("そう") && surface.count > 2 {
            return Note(form: "そう", meaning: "looks like / seems…")
        }
        if surface.hasSuffix("すぎる") || surface.hasSuffix("すぎ") {
            return Note(form: "すぎる", meaning: "too much…")
        }
        if surface.hasSuffix("やすい") {
            return Note(form: "やすい", meaning: "easy to…")
        }
        if surface.hasSuffix("にくい") {
            return Note(form: "にくい", meaning: "hard to…")
        }

        return nil
    }

    private static let particles: [String: String] = [
        "は": "marks the topic",
        "が": "marks the subject / new info",
        "を": "marks the direct object",
        "に": "to / at / in (time, place, indirect object)",
        "で": "at / by / with (place of action, means)",
        "の": "possessive / nominalizer",
        "と": "and / with / quotation",
        "へ": "toward (direction)",
        "から": "from / because",
        "まで": "until / as far as",
        "より": "than / from",
        "も": "also / even",
        "ね": "seeks agreement (right?)",
        "よ": "asserts new info",
        "な": "soft command / emotion",
        "か": "question marker",
        "や": "and (non-exhaustive list)",
        "ば": "if (conditional)",
        "さ": "soft assertiveness",
        "ぞ": "strong assertiveness (masculine)",
        "わ": "soft assertiveness",
        "です": "polite copula (is/am/are)",
        "ます": "polite verb ending",
        "だ": "plain copula (is/am/are)",
        "である": "formal written copula",
    ]
}

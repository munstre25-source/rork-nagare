import Foundation

/// Grammar points searchable in the Grammar scope. Ids and titles mirror the server's
/// `grammar_patterns` table (same seed list); the table is the source of truth for matching,
/// this list only renders the browse chips. Keep both in sync when adding patterns.
nonisolated struct GrammarPattern: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let meaning: String
    let jlpt: String?
    /// The surface highlighted inside matching lines.
    let primary: String

    static let all: [GrammarPattern] = [
        GrammarPattern(id: "tai", title: "〜たい", meaning: "want to do", jlpt: "N5", primary: "たい"),
        GrammarPattern(id: "temoii", title: "〜てもいい", meaning: "may, is okay to", jlpt: "N5", primary: "てもいい"),
        GrammarPattern(id: "tekudasai", title: "〜てください", meaning: "please do", jlpt: "N5", primary: "てください"),
        GrammarPattern(id: "nakereba", title: "〜なければならない", meaning: "must, have to", jlpt: "N5", primary: "なければならない"),
        GrammarPattern(id: "tari", title: "〜たり〜たり", meaning: "doing things like", jlpt: "N5", primary: "たり"),
        GrammarPattern(id: "nagara", title: "〜ながら", meaning: "while doing", jlpt: "N5", primary: "ながら"),
        GrammarPattern(id: "tara", title: "〜たら", meaning: "if / when", jlpt: "N5", primary: "たら"),
        GrammarPattern(id: "tokoro", title: "〜ところ", meaning: "about to / just did", jlpt: "N4", primary: "ところ"),
        GrammarPattern(id: "teshimau", title: "〜てしまう / 〜ちゃう", meaning: "finish doing; do by accident", jlpt: "N4", primary: "てしまう"),
        GrammarPattern(id: "teoku", title: "〜ておく", meaning: "do in advance", jlpt: "N4", primary: "ておく"),
        GrammarPattern(id: "temiru", title: "〜てみる", meaning: "try doing", jlpt: "N4", primary: "てみる"),
        GrammarPattern(id: "teiku", title: "〜ていく / 〜てくる", meaning: "change over time", jlpt: "N4", primary: "ていく"),
        GrammarPattern(id: "rashii", title: "〜らしい / 〜そうだ", meaning: "hearsay, appearance", jlpt: "N4", primary: "らしい"),
        GrammarPattern(id: "hazudesu", title: "〜はず", meaning: "supposed to", jlpt: "N4", primary: "はず"),
        GrammarPattern(id: "kamoshirenai", title: "〜かもしれない", meaning: "might, maybe", jlpt: "N4", primary: "かもしれない"),
        GrammarPattern(id: "tsumori", title: "〜つもり", meaning: "intend to", jlpt: "N4", primary: "つもり"),
        GrammarPattern(id: "sugiru", title: "〜すぎる", meaning: "too much", jlpt: "N4", primary: "すぎる"),
        GrammarPattern(id: "yasui", title: "〜やすい / 〜にくい", meaning: "easy / hard to do", jlpt: "N4", primary: "やすい"),
        GrammarPattern(id: "saseru", title: "〜させる / 〜られる", meaning: "causative, passive", jlpt: "N4", primary: "させる"),
        GrammarPattern(id: "tekureru", title: "〜てくれる / 〜てもらう", meaning: "do for someone", jlpt: "N4", primary: "てくれる"),
        GrammarPattern(id: "youtoomou", title: "〜ようと思う", meaning: "think I will", jlpt: "N3", primary: "ようと思う"),
        GrammarPattern(id: "younisuru", title: "〜ようにする", meaning: "make a habit of", jlpt: "N3", primary: "ようにする"),
        GrammarPattern(id: "tame", title: "〜ため（に）", meaning: "for the sake of", jlpt: "N3", primary: "ため"),
        GrammarPattern(id: "tabini", title: "〜たび（に）", meaning: "every time", jlpt: "N3", primary: "たびに"),
        GrammarPattern(id: "kotonisuru", title: "〜ことにする", meaning: "decide to; make a rule of", jlpt: "N3", primary: "ことにする"),
        GrammarPattern(id: "wake", title: "〜わけ", meaning: "reason; no wonder", jlpt: "N3", primary: "わけ"),
        GrammarPattern(id: "bayoroshii", title: "〜ばよかった", meaning: "should have (regret)", jlpt: "N3", primary: "ばよかった"),
        GrammarPattern(id: "sae", title: "〜さえ", meaning: "even", jlpt: "N2", primary: "さえ"),
        GrammarPattern(id: "ue", title: "〜上（に）", meaning: "on top of, moreover", jlpt: "N2", primary: "上に"),
        GrammarPattern(id: "kke", title: "〜っけ", meaning: "was it again?", jlpt: "N2", primary: "っけ"),
    ]
}

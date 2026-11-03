import Foundation

/// Lifetime listening milestones — quiet levels, not XP or leaderboards.
nonisolated enum ImmersionHoursLevel: Int, CaseIterable, Identifiable, Sendable {
    case dawn = 5
    case brook = 25
    case river = 50
    case current = 100
    case torrent = 250
    case ocean = 500

    var id: Int { rawValue }
    var hours: Int { rawValue }

    var title: String {
        switch self {
        case .dawn: "Dawn"
        case .brook: "Brook"
        case .river: "River"
        case .current: "Current"
        case .torrent: "Torrent"
        case .ocean: "Ocean"
        }
    }

    static func current(hours: Double) -> ImmersionHoursLevel? {
        allCases.last { Double($0.hours) <= hours }
    }

    static func next(after hours: Double) -> ImmersionHoursLevel? {
        allCases.first { Double($0.hours) > hours }
    }
}

/// Share of a clip's tappable tokens the learner already knows or finds easy.
nonisolated struct ClipComprehension: Sendable {
    var understood: Int
    var total: Int

    var percent: Int {
        guard total > 0 else { return 0 }
        return Int((Double(understood) / Double(total) * 100).rounded())
    }

    static func measure(clip: Clip, known: (Token) -> SRSState?) -> ClipComprehension {
        let tokens = clip.lines.flatMap(\.tokens).filter { $0.tappable }
        let understood = tokens.filter {
            switch known($0) {
            case .known, .easy, .familiar: return true
            default: return false
            }
        }.count
        return ClipComprehension(understood: understood, total: tokens.count)
    }
}

/// Vocabulary coverage for one YouTube channel / series.
nonisolated struct SeriesMastery: Identifiable, Sendable {
    var id: String { channelName }
    var channelName: String
    var knownUnique: Int
    var seenUnique: Int

    var percent: Int {
        guard seenUnique > 0 else { return 0 }
        return Int((Double(knownUnique) / Double(seenUnique) * 100).rounded())
    }
}

/// Joyo-kanji collection progress derived from known vocab surfaces.
nonisolated struct KanjiWallProgress: Sendable {
    /// Common Joyo subset shipped in-app (grade 1–3 + frequent extras) — enough to feel collectible
    /// without embedding the full 2136-character list.
    static let joyoSeed: [Character] = Array(
        "一二三四五六七八九十百千万円年月日木本山川田人口目耳手足力大小上下中外左右前後南北東西白黒赤青男女子父母兄弟姉妹先生学校友時間分半今来行食飲見聞話読書買売持待立坐歩走出入開閉始終東西南北春秋夏冬花草雨雪風電気車船空海火水金土石犬猫鳥魚"
    )

    var collected: Set<Character>
    var total: Int { Self.joyoSeed.count }
    var count: Int { collected.count }
    var percent: Int {
        guard total > 0 else { return 0 }
        return Int((Double(count) / Double(total) * 100).rounded())
    }

    static func from(knownSurfaces: [String]) -> KanjiWallProgress {
        var set = Set<Character>()
        let seed = Set(joyoSeed)
        for surface in knownSurfaces {
            for ch in surface where seed.contains(ch) {
                set.insert(ch)
            }
        }
        return KanjiWallProgress(collected: set)
    }
}

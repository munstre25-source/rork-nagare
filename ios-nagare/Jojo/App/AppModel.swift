import Foundation
import Observation
import SwiftData

/// Minutes watched on a given day.
nonisolated struct DayMinutes: Identifiable, Sendable {
    let date: Date
    let minutes: Double
    var id: Date { date }
}

/// A word that just became a card, flying toward the Vocab tab.
struct WordFlight: Equatable {
    var id: Int
    var surface: String
    var reading: String
}

/// Destinations opened from the home-screen widget or `jojo://` URLs.
nonisolated enum DeepLink: String, Equatable, Sendable {
    case feed
    case review
}

/// App-wide state: content library, local profile, watch-time tracking, and word saving.
@Observable
@MainActor
final class AppModel {
    let container: ModelContainer
    /// Bumped after a marketing demo restores the user's accent, so the open tabs re-resolve colors.
    var paletteEpoch: Int = 0
    let purchases: PurchaseManager
    let lexicon: LocalLexicon
    let explainService: WordExplainService

    private(set) var profile: UserProfile
    private(set) var clips: [Clip] = []
    private(set) var lookedUpKeys: Set<String> = []
    /// Latest mark for each saved word, so the transcript can show known and familiar words without a fetch per token.
    private(set) var wordStates: [String: SRSState] = [:]
    private(set) var watchLog: [String: Double] = [:]
    /// Increments when the daily goal is reached; the Feed observes it to play the trophy animation.
    private(set) var goalCelebrationCount: Int = 0
    /// Increments when a watch, skip, save, or favorite should reshape the upcoming feed.
    private(set) var tasteRevision: Int = 0
    /// Clip to open in the feed on next appearance (e.g. from Review / Search).
    var pendingFeedClipId: String?
    /// Deep link destination from widgets / URLs (`jojo://review`, `jojo://feed`).
    var pendingDeepLink: DeepLink?
    /// Pushed screens such as a word's detail hide the floating tab bar.
    var hidesMainTabBar: Bool = false
    /// Feed focus: the capsule is faded while a clip plays. FeedView owns the timer.
    var feedChromeHidden: Bool = false
    /// Bumps when follow list changes so the Following feed can refresh.
    private(set) var followRevision: Int = 0
    /// The newest saved word, so the feed can pop it and fly it to Vocab.
    var rewardFlight: WordFlight?
    /// Bumps when a brand-new word is saved so the Vocab tab can animate attention.
    private(set) var vocabBadgePulse: Int = 0
    /// Toast payload when a saved word reappears in the spoken line.
    var cameBackToast: CameBackPayload?
    /// First-session coach step mirrored for the Feed overlay (`nil` when finished/skipped).
    var firstSessionCoach: FirstSessionStep? {
        // Existing installs that already open the main app skip the coach.
        if profile.mainAppOpenCount > 2, profile.firstSessionStep == 0 {
            return nil
        }
        let step = profile.firstSessionStep
        guard profile.onboardingCompleted, step >= 0, step < FirstSessionStep.done.rawValue else { return nil }
        return FirstSessionStep(rawValue: step)
    }

    @ObservationIgnored private let seedClips: [Clip]
    @ObservationIgnored private var cameBackShownKeys: Set<String> = []
    @ObservationIgnored private var lastCameBackProbeKey: String = ""
    @ObservationIgnored private var unsavedWatchSeconds: Double = 0
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var clipsById: [String: Clip] = [:]
    /// Dictionary form or surface form → clip ids that contain it.
    @ObservationIgnored private var clipIdsByWord: [String: [String]] = [:]
    /// `pos|jlpt` → a short list of dictionary forms, for offline related-word suggestions.
    @ObservationIgnored private var formsByPosJLPT: [String: [String]] = [:]
    @ObservationIgnored private var rankedCacheKey = ""
    @ObservationIgnored private var rankedCache: [Clip]?

    var context: ModelContext { container.mainContext }

    init(container: ModelContainer, purchases: PurchaseManager) {
        self.container = container
        self.purchases = purchases
        let lexicon = LocalLexicon(entries: ContentLibrary.loadDictionary())
        self.lexicon = lexicon
        self.explainService = WordExplainService(api: .shared, lexicon: lexicon)
        self.seedClips = ContentLibrary.loadSeedClips()

        let context = container.mainContext
        let existing = (try? context.fetch(FetchDescriptor<UserProfile>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        if let first = existing.first {
            profile = first
            existing.dropFirst().forEach { context.delete($0) }
        } else {
            let created = UserProfile()
            context.insert(created)
            profile = created
        }
        if let data = profile.watchLogData, let log = try? JSONDecoder().decode([String: Double].self, from: data) {
            watchLog = log
        }
        migrateAppearanceIfNeeded()
        if profile.onboardingCompleted {
            JojoPalette.activate(theme: profile.theme, scheme: profile.scheme)
        } else {
            JojoPalette.activateOnboarding()
        }
        rebuildClips()
        reloadLookedUpKeys()
        preloadCaches()
        refreshStreakFreezeIfNeeded()
        ensureWeeklyStatsBucket()
        save()
    }

    // MARK: Persistence

    func save() {
        do {
            try context.save()
        } catch {
            print("[AppModel] save failed: \(error.localizedDescription)")
        }
        WidgetSnapshotPublisher.publish(from: self)
    }

    /// Handles `jojo://feed` and `jojo://review` from widgets / local notifications.
    func handleDeepLink(_ url: URL) {
        guard url.scheme == "jojo" else { return }
        let clipFromQuery = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "clipId" })?
            .value
        if let clipFromQuery, !clipFromQuery.isEmpty {
            pendingFeedClipId = clipFromQuery
        }
        switch url.host?.lowercased() {
        case "review":
            pendingDeepLink = .review
            track("deep_link", props: ["dest": "review"])
        case "feed", nil:
            pendingDeepLink = .feed
            track("deep_link", props: ["dest": "feed"])
        default:
            pendingDeepLink = .feed
        }
    }

    func clearDeepLink() {
        pendingDeepLink = nil
    }

    // MARK: Clips

    func clip(id: String) -> Clip? {
        clipsById[id]
    }

    /// Clips for screen recordings and the onboarding feed. Only lines taken from the video,
    /// with the convenience-store order and the Genki dialogue first.
    func showcaseClips(limit: Int = 3) -> [Clip] {
        let verified = studyLibrary.filter { $0.hasVerifiedTranscript && $0.hasPlayableVideo && !$0.lines.isEmpty }
        let preferred = [
            "immersion-konbini-sayaka",
            "immersion-_8b_ERSJ6_Q-5-45",
            "immersion-komeda-order",
            "immersion-kids-aisatsu",
        ]
        var ordered: [Clip] = []
        for id in preferred {
            if let clip = verified.first(where: { $0.id == id }) {
                ordered.append(clip)
            }
        }
        for clip in verified where !ordered.contains(where: { $0.id == clip.id }) {
            ordered.append(clip)
        }
        if ordered.isEmpty { ordered = studyLibrary }
        return Array(ordered.prefix(max(limit, 1)))
    }

    /// Clips whose transcript contains this dictionary form or surface, in library order.
    func clipsMentioning(_ word: String, limit: Int = 4) -> [Clip] {
        guard !word.isEmpty, let ids = clipIdsByWord[word] else { return [] }
        var result: [Clip] = []
        result.reserveCapacity(min(limit, ids.count))
        for id in ids {
            guard let clip = clipsById[id] else { continue }
            result.append(clip)
            if result.count == limit { break }
        }
        return result
    }

    /// Other dictionary forms with the same part of speech and JLPT tag.
    func relatedForms(pos: String, jlpt: String?, excluding: String, limit: Int = 4) -> [String] {
        let bucket = formsByPosJLPT["\(pos)|\(jlpt ?? "")"] ?? []
        var result: [String] = []
        for form in bucket where form != excluding {
            result.append(form)
            if result.count == limit { break }
        }
        return result
    }

    private func rebuildClips() {
        let remote = ((try? context.fetch(FetchDescriptor<RemoteClip>())) ?? []).compactMap { row -> Clip? in
            try? JSONDecoder().decode(Clip.self, from: row.json)
        }
        var merged = seedClips
        for clip in remote {
            let enriched = enrich(clip)
            if let index = merged.firstIndex(where: { $0.id == clip.id }) {
                merged[index] = enriched
            } else {
                merged.append(enriched)
            }
        }
        // Only clips whose transcript was taken from the video are study material.
        let verified = merged.filter(\.hasVerifiedTranscript)
        clips = verified.isEmpty ? merged : verified
        indexLibrary(merged)
        rankedCache = nil
        rankedCacheKey = ""
        catalogGeneration += 1
    }

    private func indexLibrary(_ library: [Clip]) {
        var byId: [String: Clip] = [:]
        var words: [String: [String]] = [:]
        var related: [String: [String]] = [:]
        byId.reserveCapacity(library.count)
        for clip in library {
            byId[clip.id] = clip
            var seenWords = Set<String>()
            for line in clip.lines {
                for token in line.tokens {
                    remember(token.dictionaryForm, clipId: clip.id, seen: &seenWords, into: &words)
                    if token.surface != token.dictionaryForm {
                        remember(token.surface, clipId: clip.id, seen: &seenWords, into: &words)
                    }
                    guard token.tappable, !token.dictionaryForm.isEmpty else { continue }
                    let key = "\(token.pos)|\(token.jlpt ?? "")"
                    var forms = related[key] ?? []
                    if forms.count < 24, !forms.contains(token.dictionaryForm) {
                        forms.append(token.dictionaryForm)
                        related[key] = forms
                    }
                }
            }
        }
        clipsById = byId
        clipIdsByWord = words
        formsByPosJLPT = related
    }

    private func remember(_ word: String, clipId: String, seen: inout Set<String>, into words: inout [String: [String]]) {
        guard !word.isEmpty, seen.insert(word).inserted else { return }
        words[word, default: []].append(clipId)
    }

    /// Bumped when the synced library changes so For You can append new clips.
    var catalogGeneration: Int = 0

    /// Published clips plus the bundled set. A remote row with the same id replaces the bundle.
    var studyLibrary: [Clip] {
        clips
    }

    private func enrich(_ clip: Clip) -> Clip {
        var copy = clip
        copy.lines = clip.lines.map { line in
            var l = line
            l.tokens = line.tokens.map { lexicon.enriched($0) }
            return l
        }
        return copy
    }

    /// Background, non-blocking clip library sync from Supabase. Bundled clips stay the offline source of truth.
    func startRemoteSync() {
        guard SupabaseAPI.shared.isConfigured, refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshRemoteClips()
                try? await Task.sleep(for: .seconds(30 * 60))
            }
        }
    }

    func refreshRemoteClips() async {
        do {
            let rows = try await SupabaseAPI.shared.fetchPublishedClips()
            guard !rows.isEmpty else { return }
            let existing = (try? context.fetch(FetchDescriptor<RemoteClip>())) ?? []
            var byId: [String: RemoteClip] = [:]
            for row in existing {
                if byId[row.clipId] != nil { context.delete(row) } else { byId[row.clipId] = row }
            }
            let publishedIds = Set(rows.map(\.clip.id))
            for id in byId.keys where !publishedIds.contains(id) {
                if let row = byId[id] { context.delete(row) }
                byId[id] = nil
            }
            for (clip, json) in rows {
                if let row = byId[clip.id] {
                    row.json = json
                    row.updatedAt = Date()
                } else {
                    context.insert(RemoteClip(clipId: clip.id, json: json))
                }
            }
            save()
            rebuildClips()
            print("[AppModel] merged \(rows.count) remote clips")
        } catch {
            print("[AppModel] clip sync skipped: \(error.localizedDescription)")
        }
    }

    /// For You. Onboarding is the cold start. After that, the next clips cluster around
    /// what this person finished, saved, favorited, or skipped. The promised first clip stays
    /// at the top until they've actually watched.
    var forYouClips: [Clip] {
        var ordered = rankedStudyClips()
        if shouldPinFirstClip,
           let first = profile.firstClipId,
           let index = ordered.firstIndex(where: { $0.id == first }),
           index > 0 {
            ordered.insert(ordered.remove(at: index), at: 0)
        }
        return ordered.isEmpty ? studyLibrary : ordered
    }

    /// Writes the current best clip onto the profile so a relaunch opens the same personal feed.
    func assignFirstClip() {
        let id = rankedStudyClips().first?.id
        guard profile.firstClipId != id else { return }
        profile.firstClipId = id
        save()
    }

    /// The best single clip for the user's answers (demo card and Day-1 clip).
    func recommendedClip(preferShort: Bool = false) -> Clip? {
        let candidates = rankedStudyClips()
        if preferShort {
            let short = candidates.prefix(8).filter { clip in
                guard let line = clip.lines.first else { return false }
                return line.end - line.start <= 6 && line.tokens.contains { $0.containsKanji && $0.tappable }
            }
            return short.first ?? candidates.first
        }
        return candidates.first
    }

    /// Liked swipes outrank motivations. A pass beats a motivation for that genre.
    private func rankedStudyClips() -> [Clip] {
        let key = rankingKey()
        if rankedCacheKey == key, let rankedCache { return rankedCache }
        let ranked = computeRankedStudyClips()
        rankedCacheKey = key
        rankedCache = ranked
        return ranked
    }

    private func rankingKey() -> String {
        [
            String(catalogGeneration),
            profile.readingLevel.rawValue,
            profile.gateContentByLevel ? "1" : "0",
            profile.tastesLiked.joined(separator: ","),
            profile.tastesDisliked.joined(separator: ","),
            profile.motivations.joined(separator: ","),
            profile.firstName,
            profile.finishedClipIds.joined(separator: ","),
            profile.favoriteClipIds.joined(separator: ","),
            profile.watchLaterClipIds.joined(separator: ","),
            profile.followedChannelNames.joined(separator: ","),
            profile.tasteTrace.joined(separator: ";")
        ].joined(separator: "|")
    }

    private func computeRankedStudyClips() -> [Clip] {
        let liked = Set(profile.tastesLiked.compactMap(Taste.init(rawValue:)).flatMap(\.categories))
        let disliked = Set(profile.tastesDisliked.compactMap(Taste.init(rawValue:)).flatMap(\.categories))
        let motivated = Set(profile.motivations.compactMap(Motivation.init(rawValue:)).flatMap(\.categories))
            .subtracting(disliked)
        let wanted = liked.union(motivated)
        let level = profile.readingLevel.difficulty.rank

        let withoutPasses = studyLibrary.filter { !disliked.contains($0.categoryKind) }
        let base = withoutPasses.isEmpty ? studyLibrary : withoutPasses
        let inBand: [Clip]
        if profile.gateContentByLevel {
            let gated = base.filter { $0.difficultyKind.rank <= level + 1 }
            inBand = gated.isEmpty ? base : gated
        } else {
            inBand = base
        }
        let matchedInBand = inBand.filter { wanted.contains($0.categoryKind) }
        let matchedAnywhere = base.filter { wanted.contains($0.categoryKind) }
        let preferred = matchedInBand.isEmpty ? matchedAnywhere : matchedInBand
        var pool = preferred
        for clip in inBand where !pool.contains(where: { $0.id == clip.id }) {
            pool.append(clip)
        }
        if pool.isEmpty { pool = studyLibrary }

        let mirror = tasteMirror()
        let prior = mirror.positives == 0 ? 1.0 : max(0.3, 1 - Double(mirror.positives) * 0.15)
        let targetLevel = mirroredLevel(fallback: level, mass: mirror.difficultyMass)

        func score(_ clip: Clip) -> Double {
            var s = 0.0
            let category = clip.categoryKind
            if disliked.contains(category) {
                s -= 80
            } else if liked.contains(category) {
                s += 50 * prior
            } else if motivated.contains(category) {
                s += 28 * prior
            } else if !wanted.isEmpty {
                s -= 18 * prior
            }
            s += mirror.category[clip.category] ?? 0
            s += mirror.channel[clip.channelName] ?? 0
            s += mirror.clip[clip.id] ?? 0
            if clip.category == mirror.lastPositiveCategory { s += 16 }
            if profile.followedChannelNames.contains(clip.channelName) { s += 22 }
            if profile.favoriteClipIds.contains(clip.id) { s += 28 }
            s -= abs(Double(clip.difficultyKind.rank) - targetLevel) * 8
            if clip.hasVerifiedTranscript { s += 4 }
            if let seen = profile.finishedClipIds.firstIndex(of: clip.id) {
                s -= 400 + Double(seen)
            }
            s += feedTieBreak(clip.id)
            return s
        }
        return spreadSimilar(pool.sorted { score($0) > score($1) })
    }

    /// Recent behavior. Newer marks count more, so the feed follows what they just did.
    private struct TasteMirror {
        var category: [String: Double] = [:]
        var channel: [String: Double] = [:]
        var clip: [String: Double] = [:]
        var difficultyMass: [Int: Double] = [:]
        var lastPositiveCategory: String?
        var positives = 0
    }

    private func tasteMirror() -> TasteMirror {
        var mirror = TasteMirror()
        let rows = profile.tasteTrace
        let count = rows.count
        let kindWeight = ["watch": 6.0, "love": 9.0, "save": 3.5, "skip": -7.0]
        for (index, row) in rows.enumerated() {
            let parts = row.split(separator: "\u{1f}", omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 4, let weight = kindWeight[parts[0]] else { continue }
            let recency = count <= 1 ? 1.0 : 0.35 + 0.65 * (Double(index) / Double(count - 1))
            let amount = weight * recency
            mirror.category[parts[1], default: 0] += amount
            mirror.channel[parts[2], default: 0] += amount * 0.85
            mirror.clip[parts[3], default: 0] += amount
            if amount > 0 {
                mirror.positives += 1
                mirror.lastPositiveCategory = parts[1]
                if let watched = clip(id: parts[3]) {
                    mirror.difficultyMass[watched.difficultyKind.rank, default: 0] += amount
                }
            }
        }
        return mirror
    }

    private func mirroredLevel(fallback: Int, mass: [Int: Double]) -> Double {
        let total = mass.values.reduce(0, +)
        guard total > 0 else { return Double(fallback) }
        let watched = mass.reduce(0) { $0 + Double($1.key) * $1.value } / total
        let pull = min(total / 12, 1)
        return Double(fallback) * (1 - pull) + watched * pull
    }

    /// Keeps a run of the same kind from becoming the whole feed. The neighborhood stays, then it breathes.
    private func spreadSimilar(_ ranked: [Clip]) -> [Clip] {
        var rest = ranked
        var out: [Clip] = []
        while !rest.isEmpty {
            if out.count >= 2,
               let previous = out.last?.category,
               out[out.count - 2].category == previous,
               let other = rest.firstIndex(where: { $0.category != previous }) {
                out.append(rest.remove(at: other))
            } else {
                out.append(rest.removeFirst())
            }
        }
        return out
    }

    /// A clip they stayed with, saved from, favorited, or swiped past.
    func noteClipWatched(_ clip: Clip) { rememberTaste("watch", clip: clip) }
    func noteClipSkipped(_ clip: Clip) { rememberTaste("skip", clip: clip) }

    private func rememberTaste(_ kind: String, clip: Clip) {
        if kind == "save" {
            let prefix = "save\u{1f}"
            let suffix = "\u{1f}\(clip.id)"
            if profile.tasteTrace.contains(where: { $0.hasPrefix(prefix) && $0.hasSuffix(suffix) }) { return }
        }
        var rows = profile.tasteTrace
        rows.append([kind, clip.category, clip.channelName, clip.id].joined(separator: "\u{1f}"))
        if rows.count > 40 { rows.removeFirst(rows.count - 40) }
        profile.tasteTrace = rows
        tasteRevision += 1
        save()
    }

    /// Keeps the clip we named during onboarding at the front of the first session.
    private var shouldPinFirstClip: Bool {
        guard profile.onboardingCompleted, profile.firstClipId != nil else { return false }
        return totalWatchSeconds - profile.feedbackBaselineWatchSeconds < 30
    }

    /// Stable per-person shuffle that only breaks ties. Taste and level always win.
    private func feedTieBreak(_ clipId: String) -> Double {
        var hash = 17
        let salt = profile.firstName.lowercased() + "|" + profile.motivations.sorted().joined(separator: ",")
        for byte in salt.utf8 { hash = hash &* 31 &+ Int(byte) }
        for byte in clipId.utf8 { hash = hash &* 31 &+ Int(byte) }
        return Double(abs(hash % 1000)) / 2500.0
    }

    // MARK: Favorites

    func isFavorite(_ clipId: String) -> Bool {
        profile.favoriteClipIds.contains(clipId)
    }

    @discardableResult
    func toggleFavorite(_ clipId: String) -> Bool {
        if let index = profile.favoriteClipIds.firstIndex(of: clipId) {
            profile.favoriteClipIds.remove(at: index)
        } else {
            profile.favoriteClipIds.append(clipId)
        }
        save()
        if isFavorite(clipId), let clip = clip(id: clipId) {
            rememberTaste("love", clip: clip)
        } else {
            tasteRevision += 1
        }
        return isFavorite(clipId)
    }

    // MARK: Watch later / Library

    func isWatchLater(_ clipId: String) -> Bool {
        profile.watchLaterClipIds.contains(clipId)
    }

    @discardableResult
    func toggleWatchLater(_ clipId: String) -> Bool {
        if let index = profile.watchLaterClipIds.firstIndex(of: clipId) {
            profile.watchLaterClipIds.remove(at: index)
        } else {
            profile.watchLaterClipIds.append(clipId)
        }
        save()
        tasteRevision += 1
        return isWatchLater(clipId)
    }

    func hasFinished(_ clipId: String) -> Bool {
        profile.finishedClipIds.contains(clipId)
    }

    /// Clips for Library shelves.
    func libraryClips(shelf: LibraryShelf) -> [Clip] {
        let ids: [String]
        switch shelf {
        case .watched: ids = profile.finishedClipIds.reversed()
        case .saved: ids = profile.favoriteClipIds.reversed()
        case .later: ids = profile.watchLaterClipIds.reversed()
        }
        return ids.compactMap { clip(id: $0) }
    }

    /// Rough clips remaining for today's minute goal (~45s average clip).
    var clipsLeftToday: Int {
        guard !isGoalReached else { return 0 }
        return max(1, Int(ceil(Double(minutesLeft) * 60 / 45)))
    }

    // MARK: Following

    func isFollowing(channel: String) -> Bool {
        profile.followedChannelNames.contains(channel)
    }

    @discardableResult
    func toggleFollow(channel: String) -> Bool {
        if let index = profile.followedChannelNames.firstIndex(of: channel) {
            profile.followedChannelNames.remove(at: index)
        } else {
            profile.followedChannelNames.append(channel)
        }
        followRevision += 1
        tasteRevision += 1
        save()
        track("channel_follow_toggled", props: ["channel": channel, "on": String(isFollowing(channel: channel))])
        return isFollowing(channel: channel)
    }

    /// Clips from followed channels, newest-feeling first (same scoring taste bias as For You).
    var followingClips: [Clip] {
        let followed = Set(profile.followedChannelNames)
        guard !followed.isEmpty else { return [] }
        return forYouClips.filter { followed.contains($0.channelName) }
    }

    /// Saves every tappable token on a line (double-tap gesture). Returns how many were recorded.
    @discardableResult
    func saveLine(clip: Clip, lineIndex: Int) -> Int {
        guard let line = clip.lines[safe: lineIndex] else { return 0 }
        var count = 0
        for token in line.tokens where token.tappable {
            let explanation = lexicon.instantExplanation(for: token)
            _ = recordTap(token: token, explanation: explanation, clip: clip, lineIndex: lineIndex, persist: false)
            count += 1
        }
        if count > 0 {
            rememberTaste("save", clip: clip)
            save()
            track("line_saved", props: ["clip": clip.id, "line": String(lineIndex), "words": String(count)])
        }
        return count
    }

    // MARK: Words

    static func wordKey(for token: Token) -> String {
        SavedWord.makeKey(surface: token.dictionaryForm, reading: token.dictionaryReading)
    }

    func isLookedUp(_ token: Token) -> Bool {
        lookedUpKeys.contains(Self.wordKey(for: token))
    }

    private func reloadLookedUpKeys() {
        let words = (try? context.fetch(FetchDescriptor<SavedWord>())) ?? []
        lookedUpKeys = Set(words.map(\.key))
        wordStates = Dictionary(words.map { ($0.key, $0.state) }, uniquingKeysWith: { _, latest in latest })
    }

    func wordState(for token: Token) -> SRSState? {
        wordStates[Self.wordKey(for: token)]
    }

    private func fetchWord(key: String) -> SavedWord? {
        let descriptor = FetchDescriptor<SavedWord>(predicate: #Predicate { $0.key == key }, sortBy: [SortDescriptor(\.addedAt)])
        let matches = (try? context.fetch(descriptor)) ?? []
        guard let first = matches.first else { return nil }
        for duplicate in matches.dropFirst() {
            first.occurrenceCount += duplicate.occurrenceCount
            context.delete(duplicate)
        }
        return first
    }

    /// Upserts a tapped word with its sentence + clip context and increments its encounter count.
    /// Returns the new occurrence count. `occurrenceCount == 1` means this tap created the flashcard.
    @discardableResult
    func recordTap(token: Token, explanation: WordExplanation?, clip: Clip, lineIndex: Int, persist: Bool = true) -> Int {
        let key = Self.wordKey(for: token)
        let line = clip.lines[safe: lineIndex]
        let word: SavedWord
        let isNew: Bool
        if let existing = fetchWord(key: key) {
            word = existing
            isNew = false
        } else {
            isNew = true
            let readings = token.baseForm != nil
                ? [token.baseReading].compactMap { $0 }
                : token.allReadings
            word = SavedWord(
                key: key,
                surface: token.dictionaryForm,
                readings: readings,
                romaji: token.dictionaryRomaji,
                pos: token.pos,
                conjugationClass: token.conjugationClass,
                jlpt: token.jlpt,
                definitions: explanation?.definitions ?? token.definitions,
                jaDefinitions: explanation?.jaDefinitions ?? token.jaDefinitions
            )
            word.contextSentence = line?.text ?? ""
            word.contextSurface = token.surface
            word.contextClipId = clip.id
            word.contextLineIndex = lineIndex
            word.dueAt = Date()
            context.insert(word)
        }
        word.occurrenceCount += 1
        if word.contextSentence.isEmpty, let line {
            word.contextSentence = line.text
            word.contextSurface = token.surface
            word.contextClipId = clip.id
            word.contextLineIndex = lineIndex
        }
        lookedUpKeys.insert(key)
        wordStates[key] = word.state
        if isNew {
            vocabBadgePulse += 1
            noteWeeklyWordSaved()
            noteFirstSessionTap()
            let reading = word.primaryReading
            rewardFlight = WordFlight(
                id: vocabBadgePulse,
                surface: word.surface,
                reading: reading == word.surface ? "" : reading
            )
        }
        if persist {
            rememberTaste("save", clip: clip)
            save()
        }
        return word.occurrenceCount
    }

    /// Mark a word known, familiar, or still learning without leaving the clip.
    func paint(token: Token, explanation: WordExplanation?, clip: Clip, lineIndex: Int, mark: SRSState) {
        _ = recordTap(token: token, explanation: explanation, clip: clip, lineIndex: lineIndex, persist: false)
        guard let word = fetchWord(key: Self.wordKey(for: token)) else { return }
        apply(mark, to: word)
        if mark != .new { noteFirstSessionGood() }
    }

    func paint(_ word: SavedWord, mark: SRSState) {
        apply(mark, to: word)
    }

    private func apply(_ mark: SRSState, to word: SavedWord) {
        switch mark {
        case .known:
            word.state = .known
            word.intervalStepIndex = SRS.maxStep
            word.dueAt = Date().addingTimeInterval(365 * 86_400)
        case .easy:
            word.state = .easy
            word.intervalStepIndex = 3
            word.dueAt = Date().addingTimeInterval(21 * 86_400)
        case .familiar:
            word.state = .familiar
            word.intervalStepIndex = 2
            word.dueAt = Date().addingTimeInterval(7 * 86_400)
        case .learning:
            word.state = .learning
            word.intervalStepIndex = 0
            word.dueAt = Date()
        case .new:
            word.state = .new
            word.intervalStepIndex = 0
            word.dueAt = Date()
        }
        word.lastReviewedAt = Date()
        wordStates[word.key] = word.state
        save()
    }

    /// Due cards the learner actually meets, most-seen first.
    func relevantDueKeys(limit: Int = 10) -> [String] {
        let words = (try? context.fetch(FetchDescriptor<SavedWord>())) ?? []
        return words
            .filter { $0.dueAt <= Date() && $0.state != .known }
            .sorted { lhs, rhs in
                if lhs.occurrenceCount != rhs.occurrenceCount {
                    return lhs.occurrenceCount > rhs.occurrenceCount
                }
                return lhs.dueAt < rhs.dueAt
            }
            .prefix(limit)
            .map(\.key)
    }

    /// POS / JLPT pockets with the most struggling cards.
    func weakWordPockets(limit: Int = 3) -> [WeakWordPocket] {
        let words = (try? context.fetch(FetchDescriptor<SavedWord>())) ?? []
        let struggling = words.filter { $0.state == .new || $0.state == .learning || ($0.state == .familiar && $0.occurrenceCount >= 2) }
        guard !struggling.isEmpty else { return [] }

        var byPos: [String: [SavedWord]] = [:]
        for word in struggling {
            let label = StudyPosFilter.normalizedLabel(for: word.pos)
            byPos[label, default: []].append(word)
        }
        var pockets: [WeakWordPocket] = byPos
            .map { key, group in
                let keys = group.sorted { $0.occurrenceCount > $1.occurrenceCount }.prefix(8).map(\.key)
                return WeakWordPocket(
                    title: key,
                    subtitle: "\(group.count) words still soft — short review tightens this pocket",
                    keys: Array(keys)
                )
            }
            .sorted { $0.keys.count > $1.keys.count }

        let n5 = struggling.filter { $0.jlpt == "N5" }
        if n5.count >= 3 {
            pockets.insert(
                WeakWordPocket(
                    title: "N5 verbs & particles",
                    subtitle: "Core beginner forms that keep showing up",
                    keys: Array(n5.prefix(8).map(\.key))
                ),
                at: 0
            )
        }
        return Array(pockets.prefix(limit))
    }

    /// When a spoken token matches a saved word that isn't known yet, surface a one-shot toast.
    func noteSpokenWordCameBack(token: Token, clipId: String) {
        let key = Self.wordKey(for: token)
        guard key != lastCameBackProbeKey else { return }
        lastCameBackProbeKey = key
        guard lookedUpKeys.contains(key), wordStates[key] != .known else { return }
        let day = Self.dayKey(Date())
        let toastKey = "\(day)|\(key)"
        guard !cameBackShownKeys.contains(toastKey) else { return }
        cameBackShownKeys.insert(toastKey)
        let gloss = fetchWord(key: key)?.gloss ?? token.definitions.first ?? ""
        cameBackToast = CameBackPayload(surface: token.surface, gloss: gloss, wordKey: key, clipId: clipId)
        track("word_came_back", props: ["word": token.surface])
    }

    func dismissCameBackToast() {
        cameBackToast = nil
    }

    // MARK: First-session win

    func advanceFirstSession(to step: FirstSessionStep) {
        guard profile.firstSessionStep >= 0, profile.firstSessionStep < FirstSessionStep.done.rawValue else { return }
        if step.rawValue > profile.firstSessionStep {
            profile.firstSessionStep = step.rawValue
            save()
        }
    }

    func noteFirstSessionTap() {
        advanceFirstSession(to: .hear)
    }

    func noteFirstSessionHeard() {
        advanceFirstSession(to: .good)
    }

    func noteFirstSessionGood() {
        advanceFirstSession(to: .done)
        track("first_session_win")
    }

    func skipFirstSessionCoach() {
        profile.firstSessionStep = -1
        save()
    }

    // MARK: Streak freeze

    /// Refreshes the once-per-week freeze allowance and patches a missed day when eligible.
    func refreshStreakFreezeIfNeeded() {
        let week = Self.weekKey(Date())
        var changed = false
        if profile.streakFreezeWeekKey != week {
            profile.streakFreezeWeekKey = week
            profile.streakFreezeRemaining = 1
            profile.streakFreezeUsedDay = ""
            changed = true
        }
        if applyStreakFreezeIfNeeded() {
            changed = true
        } else if changed {
            save()
        }
    }

    /// If yesterday was missed but the day before was active, consume one freeze.
    @discardableResult
    private func applyStreakFreezeIfNeeded() -> Bool {
        guard profile.streakFreezeRemaining > 0, profile.streakFreezeUsedDay.isEmpty else { return false }
        let calendar = Calendar.current
        let today = Date()
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
              let dayBefore = calendar.date(byAdding: .day, value: -2, to: today) else { return false }
        let todayKey = Self.dayKey(today)
        let yKey = Self.dayKey(yesterday)
        let beforeKey = Self.dayKey(dayBefore)
        // Only freeze when today hasn't started and yesterday is empty but the streak was alive.
        guard (watchLog[todayKey] ?? 0) < 60,
              (watchLog[yKey] ?? 0) < 60,
              (watchLog[beforeKey] ?? 0) >= 60 else { return false }
        watchLog[yKey] = 60
        profile.streakFreezeRemaining = 0
        profile.streakFreezeUsedDay = yKey
        persistWatchLog()
        track("streak_freeze_used", props: ["day": yKey])
        return true
    }

    static func weekKey(_ date: Date) -> String {
        let cal = Calendar.current
        let week = cal.component(.weekOfYear, from: date)
        let year = cal.component(.yearForWeekOfYear, from: date)
        return String(format: "%04d-W%02d", year, week)
    }

    func ensureWeeklyStatsBucket() {
        let week = Self.weekKey(Date())
        guard profile.weeklyStatsWeekKey != week else { return }
        profile.weeklyStatsWeekKey = week
        profile.weeklyReviewCount = 0
        profile.weeklyWordsSaved = 0
        save()
    }

    func noteWeeklyWordSaved() {
        ensureWeeklyStatsBucket()
        profile.weeklyWordsSaved += 1
        save()
    }

    func markWeeklyReportSeen() {
        profile.lastWeeklyReportWeek = Self.weekKey(Date())
        save()
    }

    var shouldOfferWeeklyReport: Bool {
        guard profile.onboardingCompleted else { return false }
        return profile.lastWeeklyReportWeek != Self.weekKey(Date())
            && Calendar.current.component(.weekday, from: Date()) == 1 // Sunday nudge
            && weeklyMinutes.contains { $0.minutes > 0 }
    }

    func buildWeeklyReport() -> WeeklyLearningReport {
        ensureWeeklyStatsBucket()
        let minutes = Int(weeklyMinutes.reduce(0) { $0 + $1.minutes }.rounded())
        let goalDays = weeklyMinutes.filter { $0.minutes * 60 >= dailyGoalSeconds }.count
        let words = (try? context.fetch(FetchDescriptor<SavedWord>())) ?? []
        let top = words.sorted { $0.occurrenceCount > $1.occurrenceCount }.prefix(5).map(\.surface)
        let weak = weakWordPockets(limit: 1).first?.title
        let headline: String
        if minutes >= profile.dailyGoalMinutes * 5 {
            headline = "Strong week"
        } else if minutes > 0 {
            headline = "You showed up"
        } else {
            headline = "Quiet week"
        }
        return WeeklyLearningReport(
            headline: headline,
            subtitle: minutes > 0
                ? "\(minutes) minutes in real Japanese — streak \(currentStreak)."
                : "Open For You for a few minutes and next Sunday will look different.",
            minutesWatched: minutes,
            wordsSaved: profile.weeklyWordsSaved,
            cardsReviewed: profile.weeklyReviewCount,
            streak: currentStreak,
            goalDays: goalDays,
            dayMinutes: weeklyMinutes,
            topWords: Array(top),
            weakPocketTitle: weak
        )
    }

    /// Clip teaser used by contextual local notifications.
    func reminderClipTeaser() -> (title: String, channel: String, clipId: String)? {
        let words = (try? context.fetch(FetchDescriptor<SavedWord>())) ?? []
        if let due = words.filter({ $0.dueAt <= Date() && !$0.contextClipId.isEmpty }).sorted(by: { $0.dueAt < $1.dueAt }).first,
           let clip = clip(id: due.contextClipId) {
            return (clip.title, clip.channelName, clip.id)
        }
        if let id = profile.firstClipId, let clip = clip(id: id) {
            return (clip.title, clip.channelName, clip.id)
        }
        if let clip = forYouClips.first {
            return (clip.title, clip.channelName, clip.id)
        }
        return nil
    }

    /// Saves a word read from a photo or screenshot. The sentence is the line it was found in.
    @discardableResult
    func saveCaptured(hit: CaptureHit) -> Bool {
        let word: SavedWord
        let isNew: Bool
        if let existing = fetchWord(key: hit.key) {
            word = existing
            isNew = false
        } else {
            isNew = true
            word = SavedWord(
                key: hit.key,
                surface: hit.surface,
                readings: hit.reading.isEmpty ? [] : [hit.reading],
                romaji: hit.romaji,
                pos: hit.pos,
                conjugationClass: hit.conjugationClass,
                jlpt: hit.jlpt,
                definitions: hit.definitions,
                jaDefinitions: hit.jaDefinitions
            )
            word.contextSentence = hit.sentence
            word.contextSurface = hit.surface
            word.contextClipId = ""
            word.contextLineIndex = 0
            word.dueAt = Date()
            context.insert(word)
        }
        word.occurrenceCount += 1
        if word.contextSentence.isEmpty {
            word.contextSentence = hit.sentence
            word.contextSurface = hit.surface
        }
        lookedUpKeys.insert(hit.key)
        wordStates[hit.key] = word.state
        if isNew { vocabBadgePulse += 1 }
        save()
        track("capture_word_saved", props: ["surface": hit.surface, "new": String(isNew)])
        return isNew
    }

    func markVocabSaveCoachSeen() {
        guard !profile.didShowVocabSaveCoach else { return }
        profile.didShowVocabSaveCoach = true
        save()
    }

    /// Keeps the in-sentence explanation on the saved word so review can show it offline.
    /// A fallback note fills an empty card. A live note replaces whatever is stored.
    func rememberContext(_ note: String, token: Token, preferExisting: Bool) {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let word = fetchWord(key: Self.wordKey(for: token)) else { return }
        if preferExisting, !word.contextNote.isEmpty { return }
        guard word.contextNote != trimmed else { return }
        word.contextNote = trimmed
        save()
    }

    /// Upgrades a saved word's definitions once a live explanation arrives.
    func updateDefinitions(for token: Token, with explanation: WordExplanation) {
        guard explanation.source == .live || explanation.source == .cache,
              let word = fetchWord(key: Self.wordKey(for: token)) else { return }
        word.definitions = explanation.definitions
        if !explanation.jaDefinitions.isEmpty { word.jaDefinitions = explanation.jaDefinitions }
        if word.conjugationClass == nil { word.conjugationClass = explanation.conjugationClass }
        save()
    }

    func persistCache(_ payload: CachePayload?) {
        guard let payload else { return }
        let key = payload.key
        let existing = (try? context.fetch(FetchDescriptor<CachedExplanation>(predicate: #Predicate { $0.cacheKey == key }))) ?? []
        if let row = existing.first {
            row.payload = payload.data
            row.createdAt = Date()
        } else {
            context.insert(CachedExplanation(cacheKey: payload.key, kind: payload.kind, payload: payload.data))
        }
        save()
    }

    private func preloadCaches() {
        let rows = (try? context.fetch(FetchDescriptor<CachedExplanation>())) ?? []
        guard !rows.isEmpty else { return }
        var entries: [String: Data] = [:]
        for row in rows { entries[row.cacheKey] = row.payload }
        let service = explainService
        Task { await service.preload(entries) }
    }

    // MARK: Review scheduling

    func answer(_ word: SavedWord, good: Bool) {
        if good {
            let interval = SRS.goodInterval(fromStep: word.intervalStepIndex)
            word.intervalStepIndex = min(word.intervalStepIndex + 1, SRS.maxStep)
            word.dueAt = Date().addingTimeInterval(interval)
            if interval >= SRS.knownThreshold {
                word.state = .known
            } else if word.state == .easy || word.state == .familiar {
                // Keep manual paint marks through Good until the known threshold.
            } else {
                word.state = .learning
            }
            if firstSessionCoach == .good || firstSessionCoach == .hear {
                noteFirstSessionGood()
            }
        } else {
            word.intervalStepIndex = 0
            word.dueAt = Date().addingTimeInterval(SRS.againInterval)
            word.state = .learning
        }
        word.lastReviewedAt = Date()
        wordStates[word.key] = word.state
        ensureWeeklyStatsBucket()
        profile.weeklyReviewCount += 1
        save()
        refreshAllReminders()
    }

    // MARK: Watch time & goal

    static func dayKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    var todayWatchedSeconds: Double { watchLog[Self.dayKey(Date())] ?? 0 }
    var dailyGoalSeconds: Double { Double(max(profile.dailyGoalMinutes, 1) * 60) }
    var goalProgress: Double { min(todayWatchedSeconds / dailyGoalSeconds, 1) }
    var isGoalReached: Bool { todayWatchedSeconds >= dailyGoalSeconds }
    var minutesLeft: Int { max(0, Int(ceil((dailyGoalSeconds - todayWatchedSeconds) / 60))) }
    var totalWatchSeconds: Double { watchLog.values.reduce(0, +) }

    /// Puts a finished clip behind ones the learner has not seen. Finishing it again keeps it at the back.
    func markClipFinished(_ id: String) {
        guard !id.isEmpty else { return }
        var ids = profile.finishedClipIds
        ids.removeAll { $0 == id }
        ids.append(id)
        let changed = ids != profile.finishedClipIds
        if changed { profile.finishedClipIds = ids }
        if let clip = clip(id: id) {
            rememberTaste("watch", clip: clip)
        } else if changed {
            save()
        }
    }

    func addWatch(seconds: Double) {
        let key = Self.dayKey(Date())
        let wasReached = isGoalReached
        watchLog[key, default: 0] += seconds
        unsavedWatchSeconds += seconds
        if !wasReached, isGoalReached, profile.lastGoalCelebratedDay != key {
            profile.lastGoalCelebratedDay = key
            goalCelebrationCount += 1
            Haptics.success()
            NotificationService.cancelStreakAtRisk()
            track("daily_goal_reached", props: ["minutes": String(profile.dailyGoalMinutes)])
            persistWatchLog()
        } else if unsavedWatchSeconds >= 10 {
            persistWatchLog()
        }
    }

    func persistWatchLog() {
        unsavedWatchSeconds = 0
        profile.watchLogData = try? JSONEncoder().encode(watchLog)
        profile.streak = currentStreak
        save()
    }

    /// Consecutive days with at least one minute watched, ending today (or yesterday if today isn't started).
    /// A once-per-week soft freeze can patch a single missed day into the watch log via `refreshStreakFreezeIfNeeded()`.
    var currentStreak: Int {
        let calendar = Calendar.current
        var day = Date()
        if (watchLog[Self.dayKey(day)] ?? 0) < 60 {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }
        var streak = 0
        while (watchLog[Self.dayKey(day)] ?? 0) >= 60 {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return streak
    }

    var streakFreezeAvailable: Bool {
        profile.streakFreezeRemaining > 0
    }

    /// Minutes watched for each of the last 7 days (oldest first).
    var weeklyMinutes: [DayMinutes] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<7).reversed().compactMap { offset -> DayMinutes? in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return DayMinutes(date: date, minutes: (watchLog[Self.dayKey(date)] ?? 0) / 60)
        }
    }

    func setDailyGoal(_ minutes: Int) {
        profile.dailyGoalMinutes = minutes
        save()
    }

    /// Older builds stored the accent in `appearanceMode` (`sakura`, `plum`, `orange`, `system`).
    /// Light and dark now apply to whichever accent is selected. Lavender becomes Sakura; Orange becomes Amber.
    private func migrateAppearanceIfNeeded() {
        switch profile.appearanceMode {
        case "plum", "purple":
            profile.accentTheme = AccentTheme.sakura.rawValue
            profile.appearanceMode = JojoScheme.dark.rawValue
        case "orange":
            profile.accentTheme = AccentTheme.amber.rawValue
            profile.appearanceMode = JojoScheme.dark.rawValue
        case "sakura", "system":
            profile.accentTheme = AccentTheme.sakura.rawValue
            profile.appearanceMode = JojoScheme.dark.rawValue
        case "light", "dark":
            migrateAccentThemeIfNeeded()
        default:
            profile.appearanceMode = JojoScheme.dark.rawValue
            migrateAccentThemeIfNeeded()
        }
        migrateAccentThemeIfNeeded()
    }

    /// Maps retired accent names onto Sakura or Amber.
    private func migrateAccentThemeIfNeeded() {
        switch profile.accentTheme {
        case "plum", "purple":
            profile.accentTheme = AccentTheme.sakura.rawValue
        case "orange":
            profile.accentTheme = AccentTheme.amber.rawValue
        default:
            if AccentTheme(rawValue: profile.accentTheme) == nil {
                profile.accentTheme = AccentTheme.sakura.rawValue
            }
        }
    }

    func setTheme(_ theme: AccentTheme) {
        profile.theme = theme
        JojoPalette.activate(theme: theme, scheme: profile.scheme)
        paletteEpoch += 1
        save()
    }

    func setScheme(_ scheme: JojoScheme) {
        profile.scheme = scheme
        JojoPalette.activate(theme: profile.theme, scheme: scheme)
        paletteEpoch += 1
        save()
    }

    func setGlowLevel(_ level: GlowLevel) {
        profile.glow = level
        save()
    }

    /// Puts the saved theme back after a Sakura-only marketing demo.
    func restorePalette() {
        JojoPalette.activate(theme: profile.theme, scheme: profile.scheme)
        paletteEpoch += 1
    }

    func setSubtitleMode(_ mode: SubtitleMode) {
        profile.subtitles = mode
        save()
    }

    func setShowFurigana(_ enabled: Bool) {
        profile.showFurigana = enabled
        save()
    }

    func setShowRomaji(_ enabled: Bool) {
        profile.showRomaji = enabled
        save()
    }

    func setDictionaryMode(_ mode: DictionaryMode) {
        profile.dictionary = mode
        save()
    }

    func setHideDailyGoalBar(_ hide: Bool) {
        profile.hideDailyGoalBar = hide
        save()
    }

    func setFadeWatchChrome(_ enabled: Bool) {
        profile.fadeWatchChrome = enabled
        if !enabled { feedChromeHidden = false }
        save()
    }

    func setGateContentByLevel(_ enabled: Bool) {
        profile.gateContentByLevel = enabled
        save()
    }

    func setReadingLevel(_ level: ReadingLevel) {
        profile.readingLevel = level
        save()
    }

    func setReminders(_ enabled: Bool) async {
        if enabled {
            let granted = await NotificationService.requestAuthorization()
            profile.remindersEnabled = granted
            if granted {
                refreshAllReminders()
            }
        } else {
            profile.remindersEnabled = false
            NotificationService.cancelReminders()
        }
        save()
    }

    func refreshStreakReminder() {
        guard profile.remindersEnabled, !isGoalReached else { return }
        NotificationService.scheduleStreakAtRisk(streak: currentStreak)
    }

    /// Re-schedule daily, review, and streak-at-risk notifications from current local state.
    func refreshAllReminders() {
        guard profile.remindersEnabled else { return }
        let teaser = reminderClipTeaser()
        NotificationService.scheduleDailyReminder(clipTitle: teaser?.title, channel: teaser?.channel, clipId: teaser?.clipId)
        NotificationService.scheduleReviewReminder(dueCount: dueWordCount, clipTitle: teaser?.title, clipId: teaser?.clipId)
        if isGoalReached {
            NotificationService.cancelStreakAtRisk()
        } else {
            NotificationService.scheduleStreakAtRisk(streak: currentStreak, clipTitle: teaser?.title, clipId: teaser?.clipId)
        }
        refreshTrialReminder()
    }

    /// Trial-end nudge from the entitlement expiration, including when reminders are turned on after purchase.
    func refreshTrialReminder() {
        guard profile.remindersEnabled else {
            NotificationService.cancelTrialReminder()
            return
        }
        // Customer info may still be loading. Leave a reminder that was already scheduled.
        guard let status = purchases.status else { return }
        guard purchases.isSubscribed,
              status.isInTrial,
              let expiration = status.expirationDate,
              expiration.timeIntervalSinceNow > 60 else {
            NotificationService.cancelTrialReminder()
            return
        }
        NotificationService.scheduleTrialReminder(endingAt: expiration)
    }

    var dueWordCount: Int {
        let words = (try? context.fetch(FetchDescriptor<SavedWord>())) ?? []
        let now = Date()
        return words.filter { $0.dueAt <= now }.count
    }

    // MARK: Onboarding

    func setOnboardingStep(_ step: OnboardingStep) {
        profile.onboardingStep = step.rawValue
        save()
    }

    func setFirstName(_ name: String) {
        profile.firstName = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(24))
        save()
    }

    /// Their name when we have one, otherwise a warm stand-in so copy always reads naturally.
    var displayName: String {
        profile.firstName.isEmpty ? "friend" : profile.firstName
    }

    /// Remembers the word tapped in the onboarding demo so it can come back as their first card.
    func noteFirstTappedWord(_ token: Token) {
        guard profile.firstTappedWordKey.isEmpty else { return }
        profile.firstTappedWordKey = Self.wordKey(for: token)
        save()
    }

    func markFlashcardTried() {
        guard !profile.didTryFlashcard else { return }
        profile.didTryFlashcard = true
        save()
    }

    func savedWord(key: String) -> SavedWord? {
        fetchWord(key: key)
    }

    /// Release onboarding never invents watch history or saved words. Debug builds may.
    /// Nonisolated so it can be a default argument; it only reads the build configuration.
    nonisolated static var seedsDemoOnOnboarding: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    func completeOnboarding(seedDemo: Bool = AppModel.seedsDemoOnOnboarding) {
        restorePalette()
        assignFirstClip()
        if seedDemo, Self.seedsDemoOnOnboarding {
            seedDemoDataIfNeeded()
        }
        profile.onboardingCompleted = true
        profile.onboardingCompletedAt = Date()
        profile.lastWelcomedDay = Self.dayKey(Date())
        // Baselines exclude seeded watch history + seed vocab from the soft ask.
        profile.feedbackBaselineWatchSeconds = totalWatchSeconds
        profile.feedbackBaselineWordCount = savedWordCount
        save()
        track("onboarding_completed", props: ["first_clip": profile.firstClipId ?? "none"])
    }

    // MARK: Feedback prompt

    /// Minimum time after onboarding before we soft-ask. Seeded demo data must not short-circuit this.
    private static let feedbackCooldown: TimeInterval = 48 * 3600
    /// New watch time (beyond the onboarding baseline) that counts as enough value.
    private static let feedbackWatchDeltaSeconds: Double = 10 * 60
    /// New saved words (beyond the onboarding baseline) that count as enough value.
    private static let feedbackWordDelta: Int = 5
    /// At least this many main-app opens after onboarding.
    private static let feedbackMinOpens: Int = 3

    private var savedWordCount: Int {
        ((try? context.fetch(FetchDescriptor<SavedWord>())) ?? []).count
    }

    /// Once a day, after a previous study day, the due count and streak spring in.
    func claimWelcomeHome() -> (due: Int, streak: Int)? {
        let today = Self.dayKey(Date())
        guard profile.onboardingCompleted, profile.lastWelcomedDay != today else { return nil }
        profile.lastWelcomedDay = today
        let due = dueWordCount
        let streak = currentStreak
        save()
        guard due > 0 || streak > 0 else { return nil }
        return (due, streak)
    }

    /// Call when the main tabs appear. Returns true when the enjoy/feedback sheet should show.
    @discardableResult
    func noteMainAppOpenAndShouldAskFeedback() -> Bool {
        guard profile.onboardingCompleted else { return false }
        ensureFeedbackBaselinesIfNeeded()
        profile.mainAppOpenCount += 1
        save()
        return shouldPresentFeedbackPrompt
    }

    /// Legacy profiles (completed before baselines existed) get a fresh cool-down from now.
    private func ensureFeedbackBaselinesIfNeeded() {
        guard profile.onboardingCompleted, profile.onboardingCompletedAt == nil else { return }
        profile.onboardingCompletedAt = Date()
        profile.feedbackBaselineWatchSeconds = totalWatchSeconds
        profile.feedbackBaselineWordCount = savedWordCount
    }

    /// Soft ask only after cool-down + real post-onboarding engagement (watch or new cards).
    /// Seeded demo watch/words are excluded via baselines taken at `completeOnboarding()`.
    var shouldPresentFeedbackPrompt: Bool {
        guard profile.onboardingCompleted else { return false }
        let state = profile.feedbackPromptState
        if state == "completed" { return false }
        if state == "deferred",
           let until = profile.feedbackPromptDeferredUntil,
           until > Date() {
            return false
        }
        guard let completedAt = profile.onboardingCompletedAt,
              Date().timeIntervalSince(completedAt) >= Self.feedbackCooldown else {
            return false
        }
        guard profile.mainAppOpenCount >= Self.feedbackMinOpens else { return false }

        let watchDelta = totalWatchSeconds - profile.feedbackBaselineWatchSeconds
        let wordDelta = savedWordCount - profile.feedbackBaselineWordCount
        return watchDelta >= Self.feedbackWatchDeltaSeconds || wordDelta >= Self.feedbackWordDelta
    }

    func deferFeedbackPrompt(days: Int) {
        profile.feedbackPromptState = "deferred"
        profile.feedbackPromptDeferredUntil = Calendar.current.date(byAdding: .day, value: days, to: Date())
        save()
    }

    func completeFeedbackPrompt() {
        profile.feedbackPromptState = "completed"
        profile.feedbackPromptDeferredUntil = nil
        save()
    }

    /// True when RevenueCat reports a trial cancel and we haven't surveyed this period yet.
    var shouldPresentCancellationSurvey: Bool {
        guard purchases.pendingCancellationSurvey else { return false }
        let exp = purchases.status?.expirationDate?.timeIntervalSince1970 ?? 0
        if exp > 0, abs(profile.cancellationSurveyExpiration - exp) < 1 {
            return false
        }
        return true
    }

    func markCancellationSurveyHandled() {
        let exp = purchases.status?.expirationDate?.timeIntervalSince1970 ?? Date().timeIntervalSince1970
        profile.cancellationSurveyExpiration = exp
        purchases.clearCancellationSurvey()
        save()
    }

    // MARK: Demo data

    /// Seeds 36 saved words (with real clip context) and a short watch history so no screen is empty.
    func seedDemoDataIfNeeded() {
        guard !profile.didSeedDemoData else { return }
        let entries = ContentLibrary.loadSeedVocab()
        let now = Date()
        for entry in entries {
            guard let clip = clip(id: entry.clipId),
                  let line = clip.lines[safe: entry.lineIndex],
                  let token = line.tokens.first(where: { $0.surface == entry.surface }) else { continue }
            let key = Self.wordKey(for: token)
            if let existing = fetchWord(key: key) {
                existing.occurrenceCount += entry.occurrenceCount
                continue
            }
            let explanation = lexicon.instantExplanation(for: token)
            let word = SavedWord(
                key: key,
                surface: token.dictionaryForm,
                readings: token.baseForm != nil ? [token.baseReading].compactMap { $0 } : token.allReadings,
                romaji: token.dictionaryRomaji,
                pos: token.pos,
                conjugationClass: token.conjugationClass,
                jlpt: token.jlpt,
                definitions: explanation?.definitions ?? token.definitions,
                jaDefinitions: explanation?.jaDefinitions ?? token.jaDefinitions
            )
            word.contextSentence = entry.contextSentence
            word.contextSurface = token.surface
            word.contextClipId = entry.clipId
            word.contextLineIndex = entry.lineIndex
            word.occurrenceCount = entry.occurrenceCount
            word.srsState = entry.srsState
            word.intervalStepIndex = entry.intervalStepIndex
            word.addedAt = now.addingTimeInterval(-Double(entry.addedDaysAgo) * 86_400 - Double(entries.count) * 60)
            word.dueAt = now.addingTimeInterval(entry.dueOffsetHours * 3600)
            context.insert(word)
        }
        let calendar = Calendar.current
        let demoMinutes: [Double] = [8, 12, 6, 14, 9, 11]
        for (offset, minutes) in demoMinutes.enumerated() {
            guard let date = calendar.date(byAdding: .day, value: -(offset + 1), to: now) else { continue }
            let key = Self.dayKey(date)
            if watchLog[key] == nil { watchLog[key] = minutes * 60 }
        }
        profile.didSeedDemoData = true
        persistWatchLog()
        reloadLookedUpKeys()
    }

    func resetDemoData() {
        ((try? context.fetch(FetchDescriptor<SavedWord>())) ?? []).forEach { context.delete($0) }
        ((try? context.fetch(FetchDescriptor<CustomDeck>())) ?? []).forEach { context.delete($0) }
        watchLog = [:]
        profile.favoriteClipIds = []
        profile.watchLaterClipIds = []
        profile.tasteTrace = []
        profile.lastGoalCelebratedDay = ""
        profile.didSeedDemoData = false
        save()
        seedDemoDataIfNeeded()
        track("demo_data_reset")
    }

    /// Apple 5.1.1-style deletion: wipe all on-device learning data and return to onboarding.
    /// Jojo has no cloud account; App Store subscriptions are canceled in Apple ID settings.
    func deleteAllUserData() {
        Haptics.warning()
        NotificationService.cancelAll()

        ((try? context.fetch(FetchDescriptor<SavedWord>())) ?? []).forEach { context.delete($0) }
        ((try? context.fetch(FetchDescriptor<CustomDeck>())) ?? []).forEach { context.delete($0) }
        ((try? context.fetch(FetchDescriptor<CachedExplanation>())) ?? []).forEach { context.delete($0) }
        ((try? context.fetch(FetchDescriptor<RemoteClip>())) ?? []).forEach { context.delete($0) }

        watchLog = [:]
        lookedUpKeys = []
        wordStates = [:]
        pendingFeedClipId = nil
        pendingDeepLink = nil
        goalCelebrationCount = 0
        unsavedWatchSeconds = 0

        let defaults = UserDefaults.standard
        // Entitlement cache and the debug bypass are local leftovers. RevenueCat keeps its own anonymous ID.
        defaults.removeObject(forKey: "nagare.entitlement.cached")
        defaults.removeObject(forKey: "nagare.debug.bypass")
        defaults.removeObject(forKey: "nagare.local.anon.id")
        defaults.removeObject(forKey: "nagare.analytics.log")
        defaults.removeObject(forKey: "nagare.explain.calllog")
        ResumePlaybackStore.clear()

        let fresh = UserProfile()
        context.delete(profile)
        context.insert(fresh)
        profile = fresh
        JojoPalette.activateOnboarding()
        save()
        rebuildClips()
        track("account_data_deleted")
    }
}

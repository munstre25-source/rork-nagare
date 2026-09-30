import Foundation
import Observation
import SwiftData

/// Minutes watched on a given day.
nonisolated struct DayMinutes: Identifiable, Sendable {
    let date: Date
    let minutes: Double
    var id: Date { date }
}

/// App-wide state: content library, local profile, watch-time tracking, and word saving.
@Observable
@MainActor
final class AppModel {
    let container: ModelContainer
    let purchases: PurchaseManager
    let lexicon: LocalLexicon
    let explainService: WordExplainService

    private(set) var profile: UserProfile
    private(set) var clips: [Clip] = []
    private(set) var lookedUpKeys: Set<String> = []
    private(set) var watchLog: [String: Double] = [:]
    /// Increments when the daily goal is reached; the Feed observes it to play the trophy animation.
    private(set) var goalCelebrationCount: Int = 0
    /// Clip to open in the feed on next appearance (e.g. from Review / Search).
    var pendingFeedClipId: String?

    @ObservationIgnored private let seedClips: [Clip]
    @ObservationIgnored private var unsavedWatchSeconds: Double = 0
    @ObservationIgnored private var refreshTask: Task<Void, Never>?

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
        rebuildClips()
        reloadLookedUpKeys()
        preloadCaches()
        save()
    }

    // MARK: Persistence

    func save() {
        do {
            try context.save()
        } catch {
            print("[AppModel] save failed: \(error.localizedDescription)")
        }
    }

    // MARK: Clips

    func clip(id: String) -> Clip? {
        clips.first { $0.id == id }
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
        clips = merged
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

    /// For You ordering: taste match + closeness to the user's level, with the Day-1 clip first.
    var forYouClips: [Clip] {
        let liked = Set(profile.tastesLiked.compactMap(Taste.init(rawValue:)).flatMap(\.categories))
        let disliked = Set(profile.tastesDisliked.compactMap(Taste.init(rawValue:)).flatMap(\.categories))
        let level = (ReadingLevel(rawValue: profile.level) ?? .beginner).difficulty.rank
        func score(_ clip: Clip) -> Double {
            var s = 0.0
            if liked.contains(clip.categoryKind) { s += 3 }
            if disliked.contains(clip.categoryKind) { s -= 3 }
            s -= Double(abs(clip.difficultyKind.rank - level)) * 1.5
            s += Double(abs(clip.id.utf8.reduce(7) { ($0 &* 31 &+ Int($1)) % 997 })) / 997.0
            return s
        }
        var ordered = clips.sorted { score($0) > score($1) }
        if let first = profile.firstClipId, let index = ordered.firstIndex(where: { $0.id == first }) {
            ordered.insert(ordered.remove(at: index), at: 0)
        }
        return ordered
    }

    /// The best single clip for the user's answers (used for the demo and Day-1 clip).
    func recommendedClip(preferShort: Bool = false) -> Clip? {
        let candidates = forYouClips
        if preferShort {
            let short = candidates.prefix(4).filter { clip in
                guard let line = clip.lines.first else { return false }
                return line.end - line.start <= 6 && line.tokens.contains { $0.containsKanji && $0.tappable }
            }
            return short.first ?? clip(id: "kissa-stories-01") ?? candidates.first
        }
        return candidates.first ?? clip(id: "kissa-stories-01")
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
        return isFavorite(clipId)
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
    @discardableResult
    func recordTap(token: Token, explanation: WordExplanation?, clip: Clip, lineIndex: Int) -> Int {
        let key = Self.wordKey(for: token)
        let line = clip.lines[safe: lineIndex]
        let word: SavedWord
        if let existing = fetchWord(key: key) {
            word = existing
        } else {
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
                definitions: explanation?.definitions ?? token.definitions
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
        save()
        return word.occurrenceCount
    }

    /// Upgrades a saved word's definitions once a live explanation arrives.
    func updateDefinitions(for token: Token, with explanation: WordExplanation) {
        guard explanation.source == .live || explanation.source == .cache,
              let word = fetchWord(key: Self.wordKey(for: token)) else { return }
        word.definitions = explanation.definitions
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
            word.state = interval >= SRS.knownThreshold ? .known : .learning
        } else {
            word.intervalStepIndex = 0
            word.dueAt = Date().addingTimeInterval(SRS.againInterval)
            word.state = .learning
        }
        word.lastReviewedAt = Date()
        save()
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

    func setReminders(_ enabled: Bool) async {
        if enabled {
            let granted = await NotificationService.requestAuthorization()
            profile.remindersEnabled = granted
            if granted {
                NotificationService.scheduleDailyReminder()
                if !isGoalReached { NotificationService.scheduleStreakAtRisk(streak: currentStreak) }
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

    // MARK: Onboarding

    func setOnboardingStep(_ step: OnboardingStep) {
        profile.onboardingStep = step.rawValue
        save()
    }

    func completeOnboarding() {
        profile.firstClipId = recommendedClip()?.id
        seedDemoDataIfNeeded()
        profile.onboardingCompleted = true
        save()
        track("onboarding_completed", props: ["first_clip": profile.firstClipId ?? "none"])
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
                definitions: explanation?.definitions ?? token.definitions
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
        profile.lastGoalCelebratedDay = ""
        profile.didSeedDemoData = false
        save()
        seedDemoDataIfNeeded()
        track("demo_data_reset")
    }
}

//
//  JojoTests.swift
//  JojoTests
//

import Foundation
import Testing
import SwiftData
@testable import Jojo

@MainActor
struct JojoTests {

    @Test func savedWordKeyJoinsSurfaceAndReading() {
        #expect(SavedWord.makeKey(surface: "食べる", reading: "たべる") == "食べる|たべる")
        #expect(SavedWord.makeKey(surface: "は", reading: "") == "は|")
    }

    @Test func feedMirrorsTheClipsTheyStayWith() throws {
        let app = try makeApp()
        let drama = app.forYouClips.filter { $0.category == "drama" }
        let other = app.forYouClips.first { $0.category != "drama" }
        try #require(drama.count >= 2)
        try #require(other != nil)
        app.noteClipWatched(drama[0])
        app.noteClipSkipped(other!)
        let upcoming = app.forYouClips.filter { $0.id != drama[0].id && $0.id != other!.id }
        #expect(upcoming.first?.category == "drama")
        let skippedIndex = app.forYouClips.firstIndex { $0.id == other!.id }
        let mirroredIndex = app.forYouClips.firstIndex { $0.id == drama[1].id }
        if let skippedIndex, let mirroredIndex {
            #expect(mirroredIndex < skippedIndex)
        }
    }

    @Test func rankedFeedIsNonEmpty() throws {
        let clips = ContentLibrary.loadSeedClips()
        try #require(!clips.isEmpty)
        let app = try makeApp()
        #expect(!app.forYouClips.isEmpty)
        #expect(app.recommendedClip() != nil)
    }

    @Test func showcasePlaysVerifiedClips() throws {
        let app = try makeApp()
        let clips = app.showcaseClips(limit: 2)
        #expect(clips.count == 2)
        let allVerified = clips.allSatisfy { $0.hasVerifiedTranscript }
        #expect(allVerified)
        #expect(Set(clips.map(\.id)).count == clips.count)
    }

    @Test func onboardingWithoutDemoSeedLeavesProgressEmpty() throws {
        let app = try makeApp()
        app.completeOnboarding(seedDemo: false)
        let words = try app.context.fetch(FetchDescriptor<SavedWord>())
        #expect(words.isEmpty)
        #expect(app.totalWatchSeconds == 0)
        #expect(app.profile.onboardingCompleted)
        #expect(!app.profile.didSeedDemoData)
        #expect(!app.forYouClips.isEmpty)
    }

    @Test func offlineExplainFallsBackFromTheToken() {
        let lexicon = LocalLexicon(entries: [:])
        let token = Token(
            surface: "天気",
            reading: "てんき",
            romaji: "tenki",
            start: 0,
            end: 1,
            pos: "noun",
            jlpt: "N5",
            definitions: ["weather"]
        )
        let explanation = lexicon.instantExplanation(for: token)
        #expect(explanation?.definitions.first == "weather")
    }

    @Test func purchaseOutcomeFailedCarriesItsMessage() {
        let outcome = PurchaseOutcome.failed("You look offline. Check your connection and try again.")
        guard case .failed(let message) = outcome else {
            Issue.record("Expected a failed purchase outcome")
            return
        }
        #expect(!message.isEmpty)
    }

    @Test func learningModesChangePresentationWithoutChangingContentOrLevel() throws {
        let app = try makeApp()
        let clips = app.forYouClips
        let level = app.profile.readingLevel
        for mode in LearningMode.allCases {
            app.setLearningMode(mode)
            #expect(app.profile.subtitleDisplay == mode.display)
            #expect(app.profile.subtitleDisplay.learningMode == mode)
            #expect(app.profile.tapWordsEnabled)
            #expect(app.forYouClips == clips)
            #expect(app.profile.readingLevel == level)
        }
        let profiles = try app.context.fetch(FetchDescriptor<UserProfile>())
        #expect(profiles.first?.subtitleDisplay == LearningMode.advanced.display)
    }

    @Test func individualAidsAndLegacySubtitleChoicesRemainUsable() throws {
        let app = try makeApp()
        app.setLearningMode(.guided)
        #expect(app.profile.subtitleDisplay.english == .onTap)
        app.setShowRomaji(true)
        #expect(app.profile.subtitleDisplay.learningMode == nil)
        app.setTapWordsEnabled(false)
        #expect(!app.profile.subtitleDisplay.tapWords)
        app.setEnglishVisibility(.hidden)
        #expect(app.profile.subtitles == .japanese)
        app.setSubtitleMode(.english)
        #expect(!app.profile.subtitleDisplay.japanese)
        #expect(app.profile.subtitleDisplay.english == .shown)
        app.setLearningMode(.beginner)
        #expect(app.profile.subtitleDisplay == LearningMode.beginner.display)
    }

    @Test func additiveSubtitleDefaultsPreserveExistingProfiles() {
        let profile = UserProfile()
        profile.subtitles = .japanese
        profile.showFurigana = false
        profile.showRomaji = false
        #expect(profile.subtitleDisplay.english == .hidden)
        #expect(profile.subtitleDisplay.learningMode == .advanced)
        profile.subtitles = .both
        #expect(profile.subtitleDisplay.english == .shown)
        profile.englishVisibility = "unknown-future-value"
        #expect(profile.subtitleDisplay.english == .shown)
    }

    @Test func reviewQueueExcludesKnownAndUsesTheSameDueRulesEverywhere() throws {
        let app = try makeApp()
        let now = Date()
        let frequent = makeWord("frequent", state: .learning, due: now.addingTimeInterval(-60), seen: 5)
        let rare = makeWord("rare", state: .new, due: now.addingTimeInterval(-120), seen: 1)
        let known = makeWord("known", state: .known, due: now.addingTimeInterval(-120), seen: 99)
        let future = makeWord("future", state: .familiar, due: now.addingTimeInterval(3600), seen: 10)
        for word in [frequent, rare, known, future] { app.context.insert(word) }
        try app.context.save()
        #expect(ReviewQueue.due(in: [known, rare, future, frequent], at: now).map(\.key) == ["frequent", "rare"])
        #expect(ReviewQueue.session(in: [known, rare, future, frequent], at: now).map(\.key) == ["frequent", "rare"])
        #expect(app.relevantDueKeys() == ["frequent", "rare"])
        #expect(app.dueWordCount == 2)
        #expect(ReviewQueue.label(for: [frequent, rare], at: now) == "Review 2 cards")
        #expect(!known.isDueForReview(at: now))
    }

    @Test func earlyPracticeIsExplicitAndCanRespectAFilteredWordList() {
        let now = Date()
        let future = makeWord("future", state: .learning, due: now.addingTimeInterval(600), seen: 1)
        let known = makeWord("known", state: .known, due: now.addingTimeInterval(-60), seen: 9)
        #expect(ReviewQueue.due(in: [future, known], at: now).isEmpty)
        let practice = ReviewQueue.session(in: [future, known], at: now)
        #expect(practice.map(\.key) == ["future"])
        #expect(ReviewQueue.label(for: practice, at: now) == "Practice 1 card")
        #expect(ReviewQueue.session(in: [known], at: now).isEmpty)
        #expect(ReviewQueue.session(in: [future], limit: 0, at: now).isEmpty)
        future.dueAt = now
        #expect(future.isDueForReview(at: now))
    }

    @Test func searchEmptyStateUsesOnlyTheSelectedScope() {
        #expect(!SearchScope.words.hasLocalResults(wordCount: 0, clipCount: 3, grammarCount: 2))
        #expect(!SearchScope.grammar.hasLocalResults(wordCount: 4, clipCount: 3, grammarCount: 0))
        #expect(!SearchScope.sentences.hasLocalResults(wordCount: 4, clipCount: 0, grammarCount: 2))
        #expect(SearchScope.all.hasLocalResults(wordCount: 0, clipCount: 1, grammarCount: 0))
    }

    @Test func dailyPlanSeparatesActivitiesAndCalendarDays() throws {
        let suite = "jojo.plan.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let today = Date()
        let tomorrow = try #require(Calendar.current.date(byAdding: .day, value: 1, to: today))
        #expect(!DailyPlanProgress.isDone(.review, on: today, defaults: defaults))
        DailyPlanProgress.mark(.review, on: today, defaults: defaults)
        #expect(DailyPlanProgress.isDone(.review, on: today, defaults: defaults))
        #expect(!DailyPlanProgress.isDone(.watch, on: today, defaults: defaults))
        #expect(!DailyPlanProgress.isDone(.review, on: tomorrow, defaults: defaults))
    }

    @Test func onboardingNormalizesAnswersAndPersonalizesAssistance() throws {
        let app = try makeApp()
        app.updateOnboardingPreferences(motivations: ["travel", "travel", "unknown"], liked: ["learning", "learning"], disliked: ["learning", "anime", "unknown"], level: .beginner)
        #expect(app.profile.motivations == ["travel"])
        #expect(app.profile.tastesLiked == ["learning"])
        #expect(app.profile.tastesDisliked == ["anime"])
        #expect(app.profile.subtitleDisplay == LearningMode.beginner.display)
        #expect(app.forYouClips.allSatisfy { $0.difficultyKind.rank <= 1 })
        let promised = app.profile.firstClipId
        app.completeOnboarding()
        #expect(app.forYouClips.first?.id == promised)
        #expect(!app.profile.didSeedDemoData)
        #expect(app.totalWatchSeconds == 0)
    }

    @Test func onboardingLevelGateIsNotBypassedByAChosenGenre() throws {
        let app = try makeApp()
        for taste in Taste.allCases {
            app.updateOnboardingPreferences(liked: [taste.rawValue], disliked: [], level: .beginner)
            #expect(app.forYouClips.allSatisfy { $0.difficultyKind.rank <= 1 })
        }
        app.updateOnboardingPreferences(level: .advanced)
        #expect(app.profile.subtitleDisplay == LearningMode.advanced.display)
        #expect(app.profile.gateContentByLevel)
    }

    @Test func podcastsAreAnIndependentInterestAndNeverAChildAudienceShortcut() {
        #expect(Taste.podcasts.categories == [.podcast])
        #expect(ClipCategory.podcast.sourceType == .liveAction)
        #expect(!Motivation.travel.categories.contains(.kids))
        #expect(Motivation.travel.categories.contains(.drama))
    }

    @Test func annualComparisonUsesActualTwelveMonthBaseline() throws {
        let comparison = try #require(SubscriptionPriceComparison(annualPrice: 60, monthlyPrice: 10, annualCurrency: "USD", monthlyCurrency: "USD", annualMonths: 12, monthlyMonths: 1))
        #expect(comparison.annualMonthlyEquivalent == 5)
        #expect(comparison.twelveMonthsAtMonthlyPrice == 120)
        #expect(comparison.annualSavings == 60)
        #expect(comparison.savingsPercent == 50)
        #expect(comparison.hasSavings)
    }

    @Test func annualSavingsNeverInventsADiscountOrMixesCurrencies() throws {
        #expect(SubscriptionPriceComparison(annualPrice: 60, monthlyPrice: 10, annualCurrency: "USD", monthlyCurrency: "EUR", annualMonths: 12, monthlyMonths: 1) == nil)
        #expect(SubscriptionPriceComparison(annualPrice: 60, monthlyPrice: 10, annualCurrency: nil, monthlyCurrency: "USD", annualMonths: 12, monthlyMonths: 1) == nil)
        #expect(SubscriptionPriceComparison(annualPrice: 60, monthlyPrice: 10, annualCurrency: "USD", monthlyCurrency: "USD", annualMonths: 6, monthlyMonths: 1) == nil)
        #expect(SubscriptionPriceComparison(annualPrice: 0, monthlyPrice: 10, annualCurrency: "USD", monthlyCurrency: "USD", annualMonths: 12, monthlyMonths: 1) == nil)
        let higher = try #require(SubscriptionPriceComparison(annualPrice: 130, monthlyPrice: 10, annualCurrency: "USD", monthlyCurrency: "USD", annualMonths: 12, monthlyMonths: 1))
        #expect(!higher.hasSavings)
        #expect(higher.annualSavings == 0)
        #expect(higher.savingsPercent == 0)
    }

    @Test func annualPercentageDoesNotRoundSavingsUp() throws {
        let comparison = try #require(SubscriptionPriceComparison(annualPrice: Decimal(string: "59.99")!, monthlyPrice: Decimal(string: "9.99")!, annualCurrency: "USD", monthlyCurrency: "USD", annualMonths: 12, monthlyMonths: 1))
        #expect(comparison.annualSavings == Decimal(string: "59.89")!)
        #expect(comparison.savingsPercent == 49)
        let yen = try #require(SubscriptionPriceComparison(annualPrice: 12000, monthlyPrice: 1500, annualCurrency: "JPY", monthlyCurrency: "JPY", annualMonths: 12, monthlyMonths: 1))
        #expect(yen.annualMonthlyEquivalent == 1000)
        #expect(yen.annualSavings == 6000)
    }

    @Test func vocabularyProgressCountsKnownAndDistinctPracticeOnTheLocalDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 3 * 3600))
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 12)))
        let start = calendar.startOfDay(for: now)
        let known = makeWord("known", state: .known, due: now, seen: 1)
        known.lastReviewedAt = now.addingTimeInterval(-60)
        let duplicate = makeWord("known", state: .known, due: now, seen: 1)
        duplicate.lastReviewedAt = now.addingTimeInterval(-10)
        let practiced = makeWord("practice", state: .learning, due: now, seen: 1)
        practiced.lastReviewedAt = start
        let yesterday = makeWord("yesterday", state: .known, due: now, seen: 1)
        yesterday.lastReviewedAt = start.addingTimeInterval(-1)
        let untouched = makeWord("untouched", state: .new, due: now, seen: 1)
        let future = makeWord("future", state: .learning, due: now, seen: 1)
        future.lastReviewedAt = now.addingTimeInterval(60)
        let progress = VocabularyProgress(words: [known, duplicate, practiced, yesterday, untouched, future],
                                          dailyGoal: 5, now: now, calendar: calendar)
        #expect(progress.savedCount == 5)
        #expect(progress.learnedCount == 2)
        #expect(progress.practicedToday == 2)
        #expect(progress.remaining == 3)
        #expect(progress.fraction == 0.4)
        #expect(!progress.goalReached)

        let tomorrow = try #require(calendar.date(byAdding: .day, value: 1, to: start))
        #expect(VocabularyProgress(words: [known, practiced], dailyGoal: 5, now: tomorrow,
                                   calendar: calendar).practicedToday == 0)
    }

    @Test func vocabularyTargetPersistsAndRepeatedAnswersCountOnce() throws {
        let app = try makeApp()
        let word = makeWord("practice-once", state: .new, due: .now, seen: 1)
        app.context.insert(word)
        app.setDailyVocabularyGoal(5)
        app.answer(word, good: true)
        app.answer(word, good: true)
        let profiles = try app.context.fetch(FetchDescriptor<UserProfile>())
        #expect(profiles.first?.dailyVocabularyGoal == 5)
        let progress = VocabularyProgress(words: [word], dailyGoal: app.profile.dailyVocabularyGoal)
        #expect(progress.practicedToday == 1)
        #expect(progress.learnedCount == 0)
        app.paint(word, mark: .known)
        #expect(VocabularyProgress(words: [word], dailyGoal: 1).learnedCount == 1)
        #expect(VocabularyProgress(words: [word], dailyGoal: 1).fraction == 1)
    }

    @Test func landscapeTheaterPlacesTheCompleteVideoNearTheUpperThirdWhenItFits() {
        let size = CGSize(width: 402, height: 800)
        let layout = LandscapeTheaterGeometry.make(in: size, preferredCaptionHeight: 220, controlsHeight: 0)
        let videoCenter = layout.videoTop + layout.videoSize.height / 2
        #expect(videoCenter >= size.height * 0.30)
        #expect(videoCenter <= size.height * 0.38)
        #expect(abs(layout.videoSize.width / layout.videoSize.height - 16.0 / 9) < 0.001)
        #expect(layout.videoTop > 12)
        #expect(layout.videoSize.width <= size.width - 24)
        #expect(layout.videoTop + layout.videoSize.height + 6 + layout.captionHeight <= size.height - 12)
    }

    @Test func landscapeTheaterFitsVideoWordsAndRevealedControlsInsideTheSafeViewport() {
        for size in [CGSize(width: 320, height: 480), CGSize(width: 393, height: 650),
                     CGSize(width: 430, height: 820), CGSize(width: 768, height: 900)] {
            for captionHeight: CGFloat in [0, 220, 440] {
                for controlsHeight: CGFloat in [0, 88, 140] {
                    let layout = LandscapeTheaterGeometry.make(in: size, preferredCaptionHeight: captionHeight,
                                                              controlsHeight: controlsHeight)
                    let gaps = CGFloat((layout.captionHeight > 0 ? 1 : 0) + (layout.controlsHeight > 0 ? 1 : 0)) * 6
                    #expect(layout.videoTop >= 0)
                    #expect(layout.videoSize.height > 0)
                    #expect(layout.controlsHeight == controlsHeight)
                    #expect(layout.videoTop + layout.videoSize.height + layout.captionHeight
                            + layout.controlsHeight + gaps <= size.height - 12 + 0.01)
                }
            }
        }
    }

    @Test func allFeedPagersSnapToOneCompleteViewport() {
        #expect(SingleClipPerSwipeBehavior.settledOffset(original: 0, proposed: 850,
                                                        viewportHeight: 700, contentHeight: 2800) == 700)
        #expect(SingleClipPerSwipeBehavior.settledOffset(original: 700, proposed: 2500,
                                                        viewportHeight: 700, contentHeight: 2800) == 1400)
        #expect(SingleClipPerSwipeBehavior.settledOffset(original: 2100, proposed: 4000,
                                                        viewportHeight: 700, contentHeight: 2800) == 2100)
        #expect(SingleClipPerSwipeBehavior.settledOffset(original: 0, proposed: -400,
                                                        viewportHeight: 700, contentHeight: 2800) == 0)
        for height: CGFloat in [480, 620, 780] {
            let offset = SingleClipPerSwipeBehavior.settledOffset(original: height * 2, proposed: height * 2 + 30,
                                                                 viewportHeight: height, contentHeight: height * 5)
            #expect(offset == height * 2)
        }
    }


    @Test func missingMeaningIsStatusAndNeverADictionaryDefinition() throws {
        let token = Token(surface: "未知の試験語", romaji: "test", start: 0, end: 1, pos: "noun",
                          definitions: ["Meaning available when you're back online"])
        let fallback = WordExplanation.fallback(for: token)
        #expect(!fallback.hasMeaning)
        for mode: DictionaryMode in [.english, .japanese, .both] {
            #expect(fallback.displayDefinitions(mode: mode).isEmpty)
        }
        let decoded = try JSONDecoder().decode(WordExplanation.self, from: JSONEncoder().encode(fallback))
        #expect(decoded.definitions.isEmpty)
    }

    @Test func savedMeaningIsAvailableBeforeAsyncCachePreload() throws {
        let app = try makeApp()
        let clip = try #require(app.clips.first)
        let token = Token(surface: "未登録試験語", romaji: "test", start: 0, end: 1, pos: "noun")
        let meaning = WordExplanation(word: token.surface, readings: [], romaji: token.romaji, pos: token.pos,
                                      conjugationClass: nil, jlpt: nil, definitions: ["saved test meaning"],
                                      formalityNote: nil, source: .live)
        _ = app.recordTap(token: token, explanation: meaning, clip: clip, lineIndex: 0, persist: false)
        #expect(app.localWordExplanation(for: token, sentence: "")?.definitions == ["saved test meaning"])
        let empty = WordExplanation(word: token.surface, readings: [], romaji: "", pos: token.pos,
                                    conjugationClass: nil, jlpt: nil, definitions: [],
                                    formalityNote: nil, source: .live)
        app.updateDefinitions(for: token, with: empty)
        #expect(app.localWordExplanation(for: token, sentence: "")?.definitions == ["saved test meaning"])
    }

    @Test func persistedMeaningResolvesSynchronouslyWithoutNetwork() throws {
        let app = try makeApp()
        let token = Token(surface: "永続試験語", romaji: "test", start: 0, end: 1, pos: "noun")
        let payload = Data(#"{"word":"永続試験語","definitions":["persisted meaning"]}"#.utf8)
        app.persistCache(CachePayload(key: WordExplainService.lookupKey(for: token, sentence: ""),
                                      kind: "lookup", data: payload))
        #expect(app.localWordExplanation(for: token, sentence: "")?.definitions == ["persisted meaning"])
    }

    @Test func desuNeHasABundledOfflineMeaning() throws {
        let app = try makeApp()
        let token = Token(surface: "ですね", romaji: "desu ne", start: 0, end: 1, pos: "expression")
        let meaning = try #require(app.localWordExplanation(for: token, sentence: "いい天気ですね"))
        #expect(meaning.source == .dictionary)
        #expect(meaning.definitions.joined().contains("agreement"))
        #expect(!meaning.jaDefinitions.isEmpty)
    }

    @Test func unknownOfflineContextDoesNotInventAWordMeaning() throws {
        let app = try makeApp()
        let clip = try #require(app.clips.first)
        let token = Token(surface: "未収録試験語", romaji: "test", start: 0, end: 1, pos: "noun")
        let selection = WordLookupController.Selection(clip: clip, lineIndex: 0, tokenIndex: 0, token: token)
        let context = WordLookupController.offlineContext(for: selection, app: app)
        #expect(context.contextualExplanation.contains("isn't saved"))
        #expect(!context.contextualExplanation.contains("this word"))
        if !selection.translation.isEmpty {
            #expect(context.contextualExplanation.contains(selection.translation))
        }
    }


    @Test func publishedPageCacheIsStableAndPreservesSubtitleData() throws {
        let clip = try #require(ContentLibrary.loadSeedClips().first)
        let lines = try JSONSerialization.jsonObject(with: JSONEncoder().encode(clip.lines))
        let row: [String: Any] = ["id": clip.id, "title": clip.title, "video_id": clip.videoId,
                                  "duration_sec": clip.durationSec, "lines": lines]
        let first = try SupabaseAPI.decodePublishedPage(JSONSerialization.data(withJSONObject: [row]))
        let second = try SupabaseAPI.decodePublishedPage(JSONSerialization.data(withJSONObject: [row], options: [.sortedKeys]))
        #expect(first.rowCount == 1)
        #expect(first.clips.first?.json == second.clips.first?.json)
        #expect(first.clips.first?.clip.lines == clip.lines)
        let persisted = try #require(first.clips.first?.json)
        #expect(try JSONDecoder().decode(Clip.self, from: persisted).lines == clip.lines)
    }

    @Test func invalidPublishedPagesCannotRetireTheCachedCatalog() throws {
        let empty = try SupabaseAPI.decodePublishedPage(Data("[]".utf8))
        #expect(empty.rowCount == 0)
        #expect(empty.clips.isEmpty)
        #expect(throws: SupabaseError.self) {
            try SupabaseAPI.decodePublishedPage(Data(#"[{"id":"broken","title":12}]"#.utf8))
        }
    }

    private func makeWord(_ key: String, state: SRSState, due: Date, seen: Int) -> SavedWord {
        let word = SavedWord(key: key, surface: key, readings: [], romaji: key, pos: "noun",
                             conjugationClass: nil, jlpt: nil, definitions: [key])
        word.state = state
        word.dueAt = due
        word.occurrenceCount = seen
        return word
    }

    private func makeApp() throws -> AppModel {
        let schema = Schema([
            SavedWord.self,
            CachedExplanation.self,
            UserProfile.self,
            RemoteClip.self,
            CustomDeck.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        // Offline ranking tests do not inherit a previous simulator's live catalog
        // retirement snapshot. Restore it immediately after constructing the fixture.
        let keys = ["jojo.catalog.publishedVideoIds", "jojo.catalog.publishedClipIds"]
        let stored = Dictionary(uniqueKeysWithValues: keys.compactMap { key in
            UserDefaults.standard.object(forKey: key).map { (key, $0) }
        })
        for key in keys { UserDefaults.standard.removeObject(forKey: key) }
        defer {
            for key in keys {
                if let value = stored[key] { UserDefaults.standard.set(value, forKey: key) }
                else { UserDefaults.standard.removeObject(forKey: key) }
            }
        }
        return AppModel(container: container, purchases: PurchaseManager())
    }
}

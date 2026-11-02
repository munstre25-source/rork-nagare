import Foundation
import SwiftData

/// Locally cached Edge Function response.
@Model
final class CachedExplanation {
    var cacheKey: String = ""
    var kind: String = "lookup"
    var payload: Data = Data()
    var createdAt: Date = Date()

    init(cacheKey: String, kind: String, payload: Data) {
        self.cacheKey = cacheKey
        self.kind = kind
        self.payload = payload
    }
}

/// A clip fetched from the Supabase clip library, stored as JSON.
@Model
final class RemoteClip {
    var clipId: String = ""
    var json: Data = Data()
    var updatedAt: Date = Date()

    init(clipId: String, json: Data) {
        self.clipId = clipId
        self.json = json
    }
}

/// A user-created review deck filtered by channel or topic.
@Model
final class CustomDeck {
    var name: String = ""
    var filterKind: String = "channel"
    var filterValue: String = ""
    var createdAt: Date = Date()

    init(name: String, filterKind: String, filterValue: String) {
        self.name = name
        self.filterKind = filterKind
        self.filterValue = filterValue
    }
}

/// Single local profile holding onboarding answers, goals, streak and settings.
@Model
final class UserProfile {
    var createdAt: Date = Date()
    var motivations: [String] = []
    var tastesLiked: [String] = []
    var tastesDisliked: [String] = []
    var level: String = "beginner"
    var onboardingStep: Int = 0
    var onboardingCompleted: Bool = false
    var dailyGoalMinutes: Int = 10
    /// Separate from watch minutes: distinct words reviewed or rated each day.
    var dailyVocabularyGoal: Int = 10
    var streak: Int = 0
    var watchLogData: Data?
    var remindersEnabled: Bool = false
    var notificationsAsked: Bool = false
    var favoriteClipIds: [String] = []
    /// Hearts guide the personal feed; bookmarks remain a separate save action.
    var likedClipIds: [String] = []
    /// Clip ids the learner has played through. For You keeps these behind clips they have not finished.
    var finishedClipIds: [String] = []
    /// Want-to-watch shelf in Library (Save for later).
    var watchLaterClipIds: [String] = []
    /// Recent watch, skip, save, and favorite marks. For You clusters the next clips around these.
    var tasteTrace: [String] = []
    /// Channel names the user follows (For You / Following split).
    var followedChannelNames: [String] = []
    var lastGoalCelebratedDay: String = ""
    /// Calendar day the welcome-back burst already played, so it shows once a day.
    var lastWelcomedDay: String = ""
    var didSeedDemoData: Bool = false
    var firstClipId: String?

    // Learning preferences. New installs open on Sakura dark with neon glow.
    var accentTheme: String = AccentTheme.sakura.rawValue
    /// `light` or `dark`. Older installs stored the accent name here; `AppModel` migrates those.
    var appearanceMode: String = JojoScheme.dark.rawValue
    /// `off`, `soft`, `glow`, or `liquid`. Controls the halo on karaoke and dictionary words.
    var glowLevel: String = GlowLevel.glow.rawValue
    var subtitleMode: String = SubtitleMode.both.rawValue
    var showFurigana: Bool = true
    var showRomaji: Bool = false
    /// Additive defaults preserve older profiles and their existing subtitle choices.
    var englishVisibility: String = EnglishVisibility.shown.rawValue
    var tapWordsEnabled: Bool = true
    /// Acknowledged the one-time karaoke invitation; reset with the local profile.
    var subtitleSetupCompleted: Bool = false
    var dictionaryMode: String = DictionaryMode.english.rawValue
    var hideDailyGoalBar: Bool = false
    /// While a clip is playing, the tab capsule and For You / Explore switch fade until the next touch.
    var fadeWatchChrome: Bool = true
    var autoAdvanceEnabled: Bool = true
    /// A short pause after the video or quick check before the next page scrolls up.
    var autoAdvancePauseSeconds: Double = 0.5
    /// When true, For You only surfaces clips at the user's level or one step harder.
    var gateContentByLevel: Bool = true

    /// What the learner asked to be called. Empty means "no name given".
    var firstName: String = ""
    /// The word tapped during the onboarding demo, replayed as their first flashcard.
    var firstTappedWordKey: String = ""
    /// They rated a card by hand during onboarding, so the review UI is already familiar.
    var didTryFlashcard: Bool = false
    /// One-shot coach after the first word tap that explains flashcards.
    var didShowVocabSaveCoach: Bool = false
    /// First-session win coach: tap → hear → Good. `-1` skipped, `0…2` in progress, `3` done.
    var firstSessionStep: Int = 0
    /// Soft streak freeze remaining this week (0 or 1).
    var streakFreezeRemaining: Int = 1
    /// ISO week key (`yyyy-ww`) when the freeze last refreshed.
    var streakFreezeWeekKey: String = ""
    /// Day key that was patched by a freeze (counts toward streak once).
    var streakFreezeUsedDay: String = ""
    /// Calendar week key of the weekly report the learner already opened.
    var lastWeeklyReportWeek: String = ""
    /// Review answers counted this week (for the weekly report).
    var weeklyReviewCount: Int = 0
    /// Words saved this week (reset with the week key).
    var weeklyWordsSaved: Int = 0
    /// Week key (`yyyy-ww`) for weekly counters.
    var weeklyStatsWeekKey: String = ""

    /// Onboarding: Instagram / TikTok / App Store / etc.
    var acquisitionSource: String = ""
    /// none | deferred | completed
    var feedbackPromptState: String = "none"
    var feedbackPromptDeferredUntil: Date?
    /// Sessions in the main app (after onboarding) — used to time the enjoy/feedback ask.
    var mainAppOpenCount: Int = 0
    /// When onboarding finished; feedback cool-down starts here (nil = legacy / not yet migrated).
    var onboardingCompletedAt: Date?
    /// `totalWatchSeconds` snapshot at onboarding end so seeded demo watch doesn't unlock feedback.
    var feedbackBaselineWatchSeconds: Double = 0
    /// Saved-word count at onboarding end so seeded vocab doesn't unlock feedback.
    var feedbackBaselineWordCount: Int = 0
    /// Expiration timestamp (timeIntervalSince1970) we already surveyed for after a trial cancel.
    var cancellationSurveyExpiration: Double = 0

    init() {}

    var theme: AccentTheme {
        get { AccentTheme(rawValue: accentTheme) ?? .sakura }
        set { accentTheme = newValue.rawValue }
    }

    var scheme: JojoScheme {
        get { JojoScheme(rawValue: appearanceMode) ?? .dark }
        set { appearanceMode = newValue.rawValue }
    }

    var glow: GlowLevel {
        get { GlowLevel(rawValue: glowLevel) ?? .soft }
        set { glowLevel = newValue.rawValue }
    }

    var subtitles: SubtitleMode {
        get { SubtitleMode(rawValue: subtitleMode) ?? .both }
        set { subtitleMode = newValue.rawValue }
    }

    var subtitleDisplay: SubtitleDisplaySettings {
        SubtitleDisplaySettings(
            japanese: subtitles.showsJapanese,
            furigana: showFurigana,
            romaji: showRomaji,
            english: subtitles.showsEnglish ? (EnglishVisibility(rawValue: englishVisibility) ?? .shown) : .hidden,
            tapWords: tapWordsEnabled
        )
    }

    var dictionary: DictionaryMode {
        get { DictionaryMode(rawValue: dictionaryMode) ?? .english }
        set { dictionaryMode = newValue.rawValue }
    }

    var readingLevel: ReadingLevel {
        get { ReadingLevel(rawValue: level) ?? .beginner }
        set { level = newValue.rawValue }
    }
}

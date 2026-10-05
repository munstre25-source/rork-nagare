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
    var streak: Int = 0
    var watchLogData: Data?
    var remindersEnabled: Bool = false
    var notificationsAsked: Bool = false
    var favoriteClipIds: [String] = []
    /// Channel names the user follows (For You / Following split).
    var followedChannelNames: [String] = []
    var lastGoalCelebratedDay: String = ""
    var didSeedDemoData: Bool = false
    var firstClipId: String?

    // Learning preferences (defaults keep existing behaviour).
    var appearanceMode: String = AppearanceMode.system.rawValue
    var subtitleMode: String = SubtitleMode.both.rawValue
    var showFurigana: Bool = true
    var showRomaji: Bool = false
    var dictionaryMode: String = DictionaryMode.english.rawValue
    var hideDailyGoalBar: Bool = false
    /// While a clip is playing, the tab capsule and For You / Explore switch fade until the next touch.
    var fadeWatchChrome: Bool = true
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

    var appearance: AppearanceMode {
        get { AppearanceMode(rawValue: appearanceMode) ?? .system }
        set { appearanceMode = newValue.rawValue }
    }

    var subtitles: SubtitleMode {
        get { SubtitleMode(rawValue: subtitleMode) ?? .both }
        set { subtitleMode = newValue.rawValue }
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

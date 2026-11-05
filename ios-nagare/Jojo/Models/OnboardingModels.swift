import Foundation

nonisolated enum Motivation: String, CaseIterable, Identifiable, Sendable {
    case anime, vtubers, travel, heritage, fun, work
    var id: String { rawValue }
    var title: String {
        switch self {
        case .anime: "Watch anime without subtitles"
        case .vtubers: "Follow VTubers & streams"
        case .travel: "Travel"
        case .heritage: "Connect with heritage"
        case .fun: "Just for fun"
        case .work: "Work or study in Japan"
        }
    }
    /// Two-line tile label for the grid.
    var shortTitle: String {
        switch self {
        case .anime: "Anime without subtitles"
        case .vtubers: "VTubers & streams"
        case .travel: "Travel in Japan"
        case .heritage: "Family & heritage"
        case .fun: "Just for fun"
        case .work: "Work or study"
        }
    }
    var symbol: String {
        switch self {
        case .anime: "sparkles.tv.fill"
        case .vtubers: "dot.radiowaves.left.and.right"
        case .travel: "airplane.departure"
        case .heritage: "house.and.flag.fill"
        case .fun: "face.smiling.inverse"
        case .work: "briefcase.fill"
        }
    }

    /// Genres this reason should pull forward when a swipe didn't pass them.
    var categories: [ClipCategory] {
        switch self {
        case .anime: [.anime]
        case .vtubers: [.vtuber, .gaming]
        case .travel: [.drama, .interview, .learning, .variety]
        case .heritage: [.drama, .interview]
        case .fun: [.variety, .anime]
        case .work: [.interview, .learning]
        }
    }
}

/// What makes Japanese hard for this learner. Device-only; shapes coach copy and the plan.
nonisolated enum LearningChallenge: String, CaseIterable, Identifiable, Sendable {
    case listening, start, motivation, grammar, kanji, vocab
    var id: String { rawValue }
    var title: String {
        switch self {
        case .listening: "Native speed is too fast"
        case .start: "Not sure where to start"
        case .motivation: "Staying motivated"
        case .grammar: "Grammar"
        case .kanji: "Reading kanji"
        case .vocab: "Words don't stick"
        }
    }
    var symbol: String {
        switch self {
        case .listening: "ear.fill"
        case .start: "map.fill"
        case .motivation: "flame.fill"
        case .grammar: "text.book.closed.fill"
        case .kanji: "character.ja"
        case .vocab: "brain.head.profile"
        }
    }
    /// How Jojo answers this challenge on the plan screen.
    var answer: String {
        switch self {
        case .listening: "Slow any line to 0.5x and loop it"
        case .start: "Clips picked for your level, in order"
        case .motivation: "Daily goal, streaks and real shows"
        case .grammar: "Ask Jojo why a sentence works"
        case .kanji: "Furigana above every kanji"
        case .vocab: "Spaced review with the original clip"
        }
    }
}

/// The five self-assessment steps, from brand new to near-fluent.
nonisolated enum SelfLevel: Int, CaseIterable, Identifiable, Sendable {
    case new, kana, basics, everyday, fluent
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .new: "Brand new"
        case .kana: "I know some words"
        case .basics: "Simple conversations"
        case .everyday: "Everyday Japanese"
        case .fluent: "Almost fluent"
        }
    }
    var subtitle: String {
        switch self {
        case .new: "こんにちは is about it"
        case .kana: "Kana, greetings, a few phrases"
        case .basics: "I can introduce myself and order food"
        case .everyday: "I follow slow shows with subtitles"
        case .fluent: "I want natural, fast speech"
        }
    }
    var jlpt: JLPTStep {
        switch self {
        case .new, .kana: .n5
        case .basics: .n4
        case .everyday: .n3
        case .fluent: .n1
        }
    }
    var readingLevel: ReadingLevel { jlpt.readingLevel }
}

/// Device-only answers the plan screens read back.
enum OnboardingPrefs {
    static let challengesKey = "jojo.onboarding.challenges"
    static let goalMonthsKey = "jojo.onboarding.goalMonths"
    static let streakGoalKey = "jojo.onboarding.streakGoal"
    static let selfLevelKey = "jojo.onboarding.selfLevel"

    static var challenges: [LearningChallenge] {
        let raw = UserDefaults.standard.stringArray(forKey: challengesKey) ?? []
        return LearningChallenge.allCases.filter { raw.contains($0.rawValue) }
    }

    static func targetDate(months: Int, from now: Date = Date()) -> Date {
        Calendar.current.date(byAdding: .month, value: months, to: now) ?? now
    }

    static func monthYear(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).year())
    }
}

/// When the daily reminder fires. Hours match Settings.
nonisolated enum StudyWindow: Int, CaseIterable, Identifiable, Sendable {
    case morning = 8, afternoon = 13, evening = 19, night = 22
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .morning: "Morning"
        case .afternoon: "Afternoon"
        case .evening: "Evening"
        case .night: "Night"
        }
    }
    var range: String {
        switch self {
        case .morning: "6 – 11 am"
        case .afternoon: "12 – 5 pm"
        case .evening: "6 – 9 pm"
        case .night: "9 pm – late"
        }
    }
    var symbol: String {
        switch self {
        case .morning: "sunrise.fill"
        case .afternoon: "sun.max.fill"
        case .evening: "sunset.fill"
        case .night: "moon.stars.fill"
        }
    }
    var plural: String {
        switch self {
        case .morning: "mornings"
        case .afternoon: "afternoons"
        case .evening: "evenings"
        case .night: "nights"
        }
    }
    var timeLabel: String {
        switch self {
        case .morning: "08:00"
        case .afternoon: "13:00"
        case .evening: "19:00"
        case .night: "22:00"
        }
    }
}

nonisolated enum Taste: String, CaseIterable, Identifiable, Sendable {
    case anime, drama, variety, vtuberGaming, interviews, kids, learning, podcasts
    var id: String { rawValue }
    var title: String {
        switch self {
        case .anime: "Anime"
        case .drama: "J-Drama & Slice-of-Life"
        case .variety: "Variety Shows"
        case .vtuberGaming: "VTuber & Gaming"
        case .interviews: "Street Interviews"
        case .kids: "Kids' Shows"
        case .learning: "Learn Japanese"
        case .podcasts: "Podcasts"
        }
    }
    var subtitle: String {
        switch self {
        case .anime: "Big emotions, iconic lines"
        case .drama: "Cafés, konbini, everyday talk"
        case .variety: "Food trips, quizzes, laughter"
        case .vtuberGaming: "Stream chatter & hype"
        case .interviews: "Real people, real answers"
        case .kids: "Stories and shows made for children"
        case .learning: "Clear speech and useful words"
        case .podcasts: "Natural conversations and longer listening"
        }
    }
    var symbol: String {
        switch self {
        case .anime: "sparkles"
        case .drama: "cup.and.saucer.fill"
        case .variety: "star.bubble.fill"
        case .vtuberGaming: "gamecontroller.fill"
        case .interviews: "mic.fill"
        case .kids: "balloon.2.fill"
        case .learning: "book.closed.fill"
        case .podcasts: "waveform"
        }
    }
    var gradient: [String] {
        switch self {
        case .anime: ["#0B1030", "#2B2F7A", "#F29E4C"]
        case .drama: ["#3B2414", "#8A4B22", "#E3A35B"]
        case .variety: ["#2B1405", "#9C3D10", "#F2B134"]
        case .vtuberGaming: ["#1B0F2E", "#5B2A86", "#FF8FAB"]
        case .interviews: ["#10261A", "#2E7D4F", "#F6E27F"]
        case .kids: ["#1E3A5F", "#3FA7D6", "#FFD23F"]
        case .learning: ["#17322E", "#4B8F7A", "#E6C36A"]
        case .podcasts: ["#17223D", "#5265A8", "#C6AAEC"]
        }
    }
    var categories: [ClipCategory] {
        switch self {
        case .anime: [.anime]
        case .drama: [.drama]
        case .variety: [.variety]
        case .vtuberGaming: [.vtuber, .gaming]
        case .interviews: [.interview]
        case .kids: [.kids]
        case .learning: [.learning]
        case .podcasts: [.podcast]
        }
    }
}

nonisolated enum ReadingLevel: String, CaseIterable, Identifiable, Sendable {
    case beginner, intermediate, advanced
    var id: String { rawValue }
    var title: String {
        switch self {
        case .beginner: "Beginner (N5–N4)"
        case .intermediate: "Intermediate (N3–N2)"
        case .advanced: "Advanced (N2–N1)"
        }
    }
    var difficulty: Difficulty {
        switch self {
        case .beginner: .beginner
        case .intermediate: .intermediate
        case .advanced: .advanced
        }
    }
}

nonisolated enum AcquisitionSource: String, CaseIterable, Identifiable, Sendable {
    case instagram, tiktok, webSearch = "web_search", appStore = "app_store", youtube, friend, other
    var id: String { rawValue }
    var title: String {
        switch self {
        case .instagram: "Instagram"
        case .tiktok: "TikTok"
        case .webSearch: "Web search / Google"
        case .appStore: "App Store"
        case .youtube: "YouTube"
        case .friend: "Friend / word of mouth"
        case .other: "Somewhere else"
        }
    }
    var symbol: String {
        switch self {
        case .instagram: "camera"
        case .tiktok: "music.note"
        case .webSearch: "magnifyingglass"
        case .appStore: "apple.logo"
        case .youtube: "play.rectangle.fill"
        case .friend: "person.2.fill"
        case .other: "ellipsis.circle"
        }
    }
}

/// Every onboarding screen. Raw values are frozen because `profile.onboardingStep`
/// persists them — new screens are appended and slotted into `flow` instead.
nonisolated enum OnboardingStep: Int, CaseIterable, Sendable {
    case splash = 0
    case valueCaptions = 1
    case valueTap = 2
    case valueFlashcards = 3
    case motivation = 4
    case taste = 5
    case level = 6
    case demo = 7
    case socialProof = 8
    case dailyGoal = 9
    case journey = 10
    case notifications = 11
    case trialTimeline = 12
    case appReview = 13
    /// Where did you hear about Jojo?
    case acquisition = 14
    case paywall = 15
    case welcome = 16
    /// What should Jojo call you?
    case name = 17
    /// Hands-on flashcard rating before the App Store ask.
    case flashcardTry = 18
    /// Theme and text-glow setup, immediately before the paywall.
    case look = 19
    /// What makes Japanese hard for you?
    case challenges = 20
    /// Drill vs real speech, with an honest labelled estimate.
    case comparison = 21
    /// Months-to-goal slider.
    case fluencyGoal = 22
    /// Reminder time of day (replaces the notification soft-ask in the flow).
    case studyWindow = 23
    /// 7 / 14 / 30 / 50 day streak pledge.
    case streakCommit = 24
    /// Animated "building your plan" beat.
    case buildingPlan = 25
    /// Summary of every answer.
    case planReady = 26
    /// Bell: we remind you before the trial ends.
    case trialReminder = 27

    /// Presentation order. Legacy experience/demo steps stay on the enum so saved state still decodes,
    /// but production onboarding only gathers settings that personalize the learner's real feed.
    static let flow: [OnboardingStep] = [
        .splash,
        .name,
        .motivation, .level, .challenges, .comparison,
        .taste, .acquisition,
        .fluencyGoal, .dailyGoal, .studyWindow, .streakCommit,
        .buildingPlan, .planReady,
        .look, .trialReminder,
        .paywall, .welcome
    ]

    var flowIndex: Int { Self.flow.firstIndex(of: self) ?? 0 }

    func advanced(by offset: Int) -> OnboardingStep? {
        Self.flow[safe: flowIndex + offset]
    }

    var analyticsName: String {
        switch self {
        case .splash: "splash"
        case .valueCaptions, .valueTap, .valueFlashcards: "valueprop"
        case .name: "name"
        case .motivation: "motivation"
        case .taste: "taste"
        case .level: "level"
        case .demo: "demo"
        case .flashcardTry: "flashcard_try"
        case .socialProof: "socialproof"
        case .dailyGoal: "dailygoal"
        case .journey: "journey"
        case .notifications: "notifications"
        case .trialTimeline: "trial_timeline"
        case .appReview: "appreview"
        case .acquisition: "acquisition"
        case .paywall: "paywall"
        case .welcome: "welcome"
        case .look: "look"
        case .challenges: "challenges"
        case .comparison: "comparison"
        case .fluencyGoal: "fluency_goal"
        case .studyWindow: "study_window"
        case .streakCommit: "streak_commit"
        case .buildingPlan: "building_plan"
        case .planReady: "plan_ready"
        case .trialReminder: "trial_reminder"
        }
    }

    var allowsBack: Bool {
        switch self {
        case .splash, .paywall, .welcome, .buildingPlan: false
        default: true
        }
    }

    var showsProgress: Bool {
        switch self {
        case .splash, .paywall, .welcome, .buildingPlan: false
        default: true
        }
    }

    /// Night-sakura for the whole funnel — cream remains available for other surfaces.
    var surface: BrandSurface { .night }
}

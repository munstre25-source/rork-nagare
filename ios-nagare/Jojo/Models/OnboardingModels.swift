import Foundation

nonisolated enum Motivation: String, CaseIterable, Identifiable, Sendable {
    case anime, vtubers, travel, heritage, fun
    var id: String { rawValue }
    var title: String {
        switch self {
        case .anime: "Watch anime without subtitles"
        case .vtubers: "Follow VTubers & streams"
        case .travel: "Travel"
        case .heritage: "Connect with heritage"
        case .fun: "Just for fun"
        }
    }
    var symbol: String {
        switch self {
        case .anime: "sparkles.tv.fill"
        case .vtubers: "dot.radiowaves.left.and.right"
        case .travel: "airplane.departure"
        case .heritage: "house.and.flag.fill"
        case .fun: "face.smiling.inverse"
        }
    }

    /// Genres this reason should pull forward when a swipe didn't pass them.
    var categories: [ClipCategory] {
        switch self {
        case .anime: [.anime]
        case .vtubers: [.vtuber, .gaming]
        case .travel: [.variety, .interview]
        case .heritage: [.drama, .interview]
        case .fun: [.variety, .anime]
        }
    }
}

nonisolated enum Taste: String, CaseIterable, Identifiable, Sendable {
    case anime, drama, variety, vtuberGaming, interviews, kids
    var id: String { rawValue }
    var title: String {
        switch self {
        case .anime: "Anime"
        case .drama: "J-Drama & Slice-of-Life"
        case .variety: "Variety Shows"
        case .vtuberGaming: "VTuber & Gaming"
        case .interviews: "Street Interviews"
        case .kids: "Kids' Shows"
        }
    }
    var subtitle: String {
        switch self {
        case .anime: "Big emotions, iconic lines"
        case .drama: "Cafés, konbini, everyday talk"
        case .variety: "Food trips, quizzes, laughter"
        case .vtuberGaming: "Stream chatter & hype"
        case .interviews: "Real people, real answers"
        case .kids: "The easiest way in"
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

    /// Presentation order. `trialTimeline` stays on the enum so a saved step still decodes.
    /// The live feed demo comes just before the review ask, once the person has scrolled and tapped a word.
    static let flow: [OnboardingStep] = [
        .splash,
        .valueCaptions, .valueTap, .valueFlashcards,
        .flashcardTry,
        .name, .acquisition,
        .motivation, .taste, .level,
        .socialProof,
        .dailyGoal, .journey, .notifications,
        .demo,
        .appReview,
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
        }
    }

    var allowsBack: Bool {
        switch self {
        case .splash, .valueCaptions, .paywall, .welcome: false
        default: true
        }
    }

    var showsProgress: Bool {
        switch self {
        case .splash, .valueCaptions, .valueTap, .valueFlashcards, .paywall, .welcome: false
        default: true
        }
    }

    /// Night-sakura for the whole funnel — cream remains available for other surfaces.
    var surface: BrandSurface { .night }
}

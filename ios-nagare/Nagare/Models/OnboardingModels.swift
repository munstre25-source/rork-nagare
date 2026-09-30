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
    var difficulty: Difficulty {
        switch self {
        case .beginner: .beginner
        case .intermediate: .intermediate
        case .advanced: .advanced
        }
    }
}

/// Every onboarding screen, persisted by raw value so the flow resumes exactly where it was left.
nonisolated enum OnboardingStep: Int, CaseIterable, Sendable {
    case splash = 0
    case valueCaptions, valueTap, valueFlashcards
    case motivation, taste, level, demo, socialProof, dailyGoal, journey, notifications, trialTimeline, paywall, welcome

    var analyticsName: String {
        switch self {
        case .splash: "splash"
        case .valueCaptions, .valueTap, .valueFlashcards: "valueprop"
        case .motivation: "motivation"
        case .taste: "taste"
        case .level: "level"
        case .demo: "demo"
        case .socialProof: "socialproof"
        case .dailyGoal: "dailygoal"
        case .journey: "journey"
        case .notifications: "notifications"
        case .trialTimeline: "trial_timeline"
        case .paywall: "paywall"
        case .welcome: "welcome"
        }
    }

    var allowsBack: Bool {
        switch self {
        case .splash, .valueCaptions, .welcome: false
        default: true
        }
    }

    var showsProgress: Bool {
        switch self {
        case .splash, .valueCaptions, .valueTap, .valueFlashcards, .paywall, .welcome: false
        default: true
        }
    }
}

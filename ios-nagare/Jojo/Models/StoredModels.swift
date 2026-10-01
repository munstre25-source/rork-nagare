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
    var lastGoalCelebratedDay: String = ""
    var didSeedDemoData: Bool = false
    var firstClipId: String?

    init() {}
}

//
//  JojoTests.swift
//  JojoTests
//

import Testing
import SwiftData
@testable import Jojo

@MainActor
struct JojoTests {

    @Test func savedWordKeyJoinsSurfaceAndReading() {
        #expect(SavedWord.makeKey(surface: "食べる", reading: "たべる") == "食べる|たべる")
        #expect(SavedWord.makeKey(surface: "は", reading: "") == "は|")
    }

    @Test func rankedFeedIsNonEmpty() throws {
        let clips = ContentLibrary.loadSeedClips()
        try #require(!clips.isEmpty)
        let app = try makeApp()
        #expect(!app.forYouClips.isEmpty)
        #expect(app.recommendedClip() != nil)
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
        return AppModel(container: container, purchases: PurchaseManager())
    }
}

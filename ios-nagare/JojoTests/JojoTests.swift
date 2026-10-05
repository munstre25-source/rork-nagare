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
        #expect(clips.allSatisfy(\.hasVerifiedTranscript))
        #expect(clips[0].id == "immersion-konbini-sayaka")
        #expect(clips[1].id == "immersion-_8b_ERSJ6_Q-5-45")
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

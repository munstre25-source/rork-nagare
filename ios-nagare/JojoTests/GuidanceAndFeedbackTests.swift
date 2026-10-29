//
//  GuidanceAndFeedbackTests.swift
//  JojoTests
//
//  Experience-prompt thresholds, analytics sanitizing, and guided-tour persistence.
//

import Foundation
import Testing
@testable import Jojo

@MainActor
struct GuidanceAndFeedbackTests {

    private func freshDefaults() -> UserDefaults {
        let name = "jojo.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    // MARK: Experience prompt

    @Test func thresholdsNeedBothSwipesAndFlashcards() {
        let swipes = FeedbackPromptConfig.minMeaningfulSwipes
        let cards = FeedbackPromptConfig.minFlashcardActions
        #expect(!ExperiencePromptStore.thresholdsMet(swipes: swipes - 1, flashcardActions: cards))
        #expect(!ExperiencePromptStore.thresholdsMet(swipes: swipes, flashcardActions: cards - 1))
        #expect(ExperiencePromptStore.thresholdsMet(swipes: swipes, flashcardActions: cards))
    }

    @Test func promptCountsUntilShownThenStops() {
        let store = ExperiencePromptStore(defaults: freshDefaults())
        for _ in 0..<FeedbackPromptConfig.minMeaningfulSwipes { store.noteMeaningfulSwipe() }
        #expect(!store.thresholdsMet)
        for _ in 0..<FeedbackPromptConfig.minFlashcardActions { store.noteFlashcardAction() }
        #expect(store.thresholdsMet)

        store.markShown()
        let before = store.meaningfulSwipes
        store.noteMeaningfulSwipe()
        #expect(store.meaningfulSwipes == before)
        #expect(store.hasShown)

        store.reset()
        #expect(!store.hasShown)
        #expect(store.meaningfulSwipes == 0)
    }

    // MARK: Analytics sanitizer

    @Test func sanitizerDropsContentAndFreeText() {
        let out = AnalyticsSanitizer.props([
            "word": "食べる",
            "message": "hello",
            "step": "3",
            "clip": "clip_42",
            "note": "has spaces in it",
            "BadKey": "x",
        ])
        #expect(out == ["step": "3", "clip": "clip_42"])
    }

    @Test func sanitizerCapsValueLengthAndCount() {
        var raw: [String: String] = [:]
        for i in 0..<30 { raw["k\(i)"] = String(repeating: "a", count: 200) }
        let out = AnalyticsSanitizer.props(raw)
        #expect(out.count == AnalyticsSanitizer.maxProps)
        #expect(out.values.allSatisfy { $0.count == AnalyticsSanitizer.maxValueLength })
    }

    @Test func eventNamesAreSnakeCase() {
        #expect(AnalyticsSanitizer.isValidName("guide_step_viewed"))
        #expect(!AnalyticsSanitizer.isValidName("Guide Step"))
        #expect(!AnalyticsSanitizer.isValidName("x"))
    }

    // MARK: Guided tour

    @Test func tourAdvancesInOrderAndCompletes() {
        var state = GuidanceState()
        state.start()
        #expect(state.step == .discover)
        for _ in 0..<(TourStep.allCases.count - 1) { state.advance() }
        #expect(state.step == .returnTomorrow)
        state.advance()
        #expect(state.tour == .completed)
        #expect(state.isTourFinished)
    }

    @Test func lateEventsDoNotSkipSteps() {
        var state = GuidanceState()
        state.start()
        state.advance(from: .practice) // not current, ignored
        #expect(state.step == .discover)
        state.jump(to: .learn)
        #expect(state.step == .learn)
        state.jump(to: .watch) // never backwards
        #expect(state.step == .learn)
    }

    @Test func skipAndTipsPersist() throws {
        let defaults = freshDefaults()
        let center = GuidanceCenter(defaults: defaults)
        center.startTourIfNeeded(legacyFinished: false)
        #expect(center.tourStep == .discover)
        center.skipTour()
        #expect(center.tourStep == nil)

        center.requestTip(.vocabReview)
        #expect(center.activeTip == .vocabReview)
        center.dismissTip()

        let reloaded = GuidanceCenter(defaults: defaults)
        #expect(reloaded.state.tour == .skipped)
        #expect(reloaded.state.isDismissed(.vocabReview))
        reloaded.requestTip(.vocabReview)
        #expect(reloaded.activeTip == nil)

        reloaded.resetTips()
        reloaded.requestTip(.vocabReview)
        #expect(reloaded.activeTip == .vocabReview)
    }

    @Test func legacyUsersSkipTheTour() {
        let center = GuidanceCenter(defaults: freshDefaults())
        center.startTourIfNeeded(legacyFinished: true)
        #expect(center.tourStep == nil)
        #expect(center.state.tour == .completed)
    }

    @Test func realActionsMoveTheTour() {
        let center = GuidanceCenter(defaults: freshDefaults())
        center.startTourIfNeeded(legacyFinished: false)
        center.observe("word_tapped")
        #expect(center.tourStep == .learn)
        center.observe("word_heard")
        #expect(center.tourStep == .returnTomorrow)
        center.noteOpenedVocab()
        #expect(center.state.tour == .completed)
    }
}

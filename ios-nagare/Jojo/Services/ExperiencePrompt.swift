import Foundation

/// Every threshold for the "How's your Jojo experience so far?" prompt lives here.
nonisolated enum FeedbackPromptConfig {
    /// User-initiated feed swipes after watching the previous clip for at least `minDwellSeconds`.
    static let minMeaningfulSwipes = 5
    /// New flashcards saved from clips plus flashcards graded in review.
    static let minFlashcardActions = 3
    /// A swipe only counts when the learner actually stayed on the previous clip this long.
    static let minDwellSeconds: TimeInterval = 2
    /// Wait after arriving somewhere calm before asking, so it never feels like an interruption.
    static let calmDelaySeconds: Double = 1.2
}

/// Counters and the one-time "shown" flag for the experience prompt, persisted in UserDefaults.
/// Pure value logic so it is unit-testable with a throwaway defaults suite.
nonisolated struct ExperiencePromptStore {
    private let defaults: UserDefaults
    private enum Key {
        static let swipes = "jojo.experiencePrompt.swipes"
        static let actions = "jojo.experiencePrompt.flashcardActions"
        static let shown = "jojo.experiencePrompt.shown"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var meaningfulSwipes: Int { defaults.integer(forKey: Key.swipes) }
    var flashcardActions: Int { defaults.integer(forKey: Key.actions) }
    var hasShown: Bool { defaults.bool(forKey: Key.shown) }

    var thresholdsMet: Bool {
        Self.thresholdsMet(swipes: meaningfulSwipes, flashcardActions: flashcardActions)
    }

    static func thresholdsMet(swipes: Int, flashcardActions: Int) -> Bool {
        swipes >= FeedbackPromptConfig.minMeaningfulSwipes
            && flashcardActions >= FeedbackPromptConfig.minFlashcardActions
    }

    /// Counting stops once the prompt has been shown; nothing more is needed.
    func noteMeaningfulSwipe() {
        guard !hasShown else { return }
        defaults.set(meaningfulSwipes + 1, forKey: Key.swipes)
    }

    func noteFlashcardAction() {
        guard !hasShown else { return }
        defaults.set(flashcardActions + 1, forKey: Key.actions)
    }

    func markShown() {
        defaults.set(true, forKey: Key.shown)
    }

    func reset() {
        [Key.swipes, Key.actions, Key.shown].forEach { defaults.removeObject(forKey: $0) }
    }
}

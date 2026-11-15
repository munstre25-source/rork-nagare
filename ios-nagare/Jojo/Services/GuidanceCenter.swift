import SwiftUI

/// Real controls the guided tour and tips can point at.
nonisolated enum CoachAnchor: String, Sendable, CaseIterable {
    case video
    case transcript
    case popupCard
    case popupSpeaker
    case exploreSwitch
    case library
    case vocabDock
    case profileDock
    case settings
    case vocabReview
    case exploreImport
}

nonisolated enum CoachSurface: Equatable, Sendable {
    case feed, explore, vocab, profile
}

/// The guided first session: the core learning loop, then the app map learners need afterward.
nonisolated enum TourStep: Int, CaseIterable, Sendable, Codable {
    // Keep the original raw values stable for tours persisted by older builds.
    case discover = 0, watch = 1, understand = 2, learn = 3, practice = 4, returnTomorrow = 5
    case explore = 6, library = 7, profile = 8, settings = 9

    static let allCases: [TourStep] = [
        .discover, .watch, .understand, .learn, .practice,
        .explore, .library, .profile, .settings, .returnTomorrow,
    ]

    var sequenceIndex: Int { Self.allCases.firstIndex(of: self) ?? 0 }

    var next: TourStep? {
        let index = sequenceIndex + 1
        return Self.allCases.indices.contains(index) ? Self.allCases[index] : nil
    }

    var requiredSurface: CoachSurface? {
        switch self {
        case .settings: .profile
        case .returnTomorrow: nil
        default: .feed
        }
    }

    var anchor: CoachAnchor {
        switch self {
        case .discover: .video
        case .watch, .understand: .transcript
        case .learn: .popupCard
        case .practice: .popupSpeaker
        case .explore: .exploreSwitch
        case .library: .library
        case .profile: .profileDock
        case .settings: .settings
        case .returnTomorrow: .vocabDock
        }
    }

    var eyebrow: String {
        switch self {
        case .discover: "Discover"
        case .watch: "Watch"
        case .understand: "Understand"
        case .learn: "Learn"
        case .practice: "Practice"
        case .explore: "Explore"
        case .library: "Library"
        case .profile: "Progress"
        case .settings: "Make it yours"
        case .returnTomorrow: "Come back"
        }
    }

    var title: String {
        switch self {
        case .discover: "Real Japanese, one clip at a time"
        case .watch: "Read along as they speak"
        case .understand: "Tap a word you don't know"
        case .learn: "It's saved as a flashcard"
        case .practice: "Hear it, then say it"
        case .explore: "Choose what you want to learn"
        case .library: "Keep the clips you care about"
        case .profile: "See your progress grow"
        case .settings: "Tune Jojo to how you learn"
        case .returnTomorrow: "Your words wait here"
        }
    }

    var message: String {
        switch self {
        case .discover: "Swipe up anytime for the next clip."
        case .watch: "Each word lights up the moment it's spoken."
        case .understand: "Any word in the lines works. Jojo explains it right away."
        case .learn: "No save button needed. Jojo keeps the word and the sentence you found it in."
        case .practice: "Tap the speaker, then say the word out loud."
        case .explore: "Switch to Explore for search, grammar, speaking scenes, JLPT paths, and your own videos."
        case .library: "Watched, liked, saved, and Watch Later clips all live behind this button."
        case .profile: "Open Profile for your streak, activity, achievements, mastery, and learning history."
        case .settings: "The gear holds subtitles, glow, playback, reminders, exports, goals, and account controls."
        case .returnTomorrow: "Open Vocab for a quick review tomorrow. A few minutes a day is plenty."
        }
    }

    /// Shown after the learner has been on an action step for a while without doing it.
    var stuckHint: String? {
        switch self {
        case .understand: "Tip: pause the clip if it's too fast, then tap any word in the lines."
        case .practice: "The speaker is the small button on the word card."
        case .profile: "Tap Profile in the bottom bar. You can use Next if you want to stay here."
        case .settings: "Tap the gear in the top-right. You can use Next to finish without opening it."
        default: nil
        }
    }

    /// The step that waits for the learner to tap a word shows no Next button at first
    /// (the next steps need the word card). Skip is always available.
    var waitsForAction: Bool { self == .understand || self == .profile || self == .settings }

    var primaryLabel: String { self == .returnTomorrow ? "Got it" : "Next" }
}

/// One-time contextual tips outside the tour.
nonisolated enum CoachTip: String, Sendable, CaseIterable {
    case vocabReview
    case exploreImport

    var anchor: CoachAnchor {
        switch self {
        case .vocabReview: .vocabReview
        case .exploreImport: .exploreImport
        }
    }

    var title: String {
        switch self {
        case .vocabReview: "Review in two minutes"
        case .exploreImport: "Learn from any video"
        }
    }

    var message: String {
        switch self {
        case .vocabReview: "Cards come back right before you'd forget them. Tap here when some are ready."
        case .exploreImport: "Paste a YouTube link and Jojo turns it into a lesson you can tap through."
        }
    }
}

/// Persisted tour progress and dismissed tips. Separate from the view so it is unit-testable.
nonisolated struct GuidanceState: Codable, Equatable, Sendable {
    enum Tour: String, Codable, Sendable { case notStarted, active, completed, skipped }
    var tour: Tour = .notStarted
    var step: TourStep = .discover
    var dismissedTips: Set<String> = []

    var isTourFinished: Bool { tour == .completed || tour == .skipped }

    mutating func start() {
        tour = .active
        step = .discover
    }

    /// Moves forward one step; finishing the last step completes the tour.
    mutating func advance() {
        guard tour == .active else { return }
        if let next = step.next {
            step = next
        } else {
            tour = .completed
        }
    }

    /// Moves forward to `target` if it is ahead of the current step (never backwards).
    mutating func jump(to target: TourStep) {
        guard tour == .active, target.sequenceIndex > step.sequenceIndex else { return }
        step = target
    }

    /// Only advances when `from` is the current step, so late or repeated events are ignored.
    mutating func advance(from expected: TourStep) {
        guard tour == .active, step == expected else { return }
        advance()
    }

    mutating func skip() {
        guard tour == .active else { return }
        tour = .skipped
    }

    mutating func dismiss(_ tip: CoachTip) { dismissedTips.insert(tip.rawValue) }
    func isDismissed(_ tip: CoachTip) -> Bool { dismissedTips.contains(tip.rawValue) }
}

/// Runs the guided first session and one-time tips. Coach marks point at real controls; the dim
/// layer never takes touches, so the learner can always do the thing being explained.
@MainActor
@Observable
final class GuidanceCenter {
    static let shared = GuidanceCenter()
    static let storageKey = "jojo.guidance.state"
    static let stuckDelay: Duration = .seconds(12)
    static let watchSecondsToAdvance: Double = 5

    private(set) var state: GuidanceState
    /// Set by the main tabs so a step only appears where its real control is visible.
    var currentSurface: CoachSurface = .feed
    /// Set by the main tabs while one of their own sheets is up.
    var blockedByPresentation = false
    private(set) var activeTip: CoachTip?
    private(set) var showStuckHint = false
    /// Bumped when the frame of the anchor currently in use changes.
    private(set) var frameRevision = 0
    /// Asks the main tabs to jump to the feed (after "Replay tour" in Help).
    private(set) var feedRequestTick = 0

    @ObservationIgnored private var frames: [CoachAnchor: CGRect] = [:]
    @ObservationIgnored private var stuckTask: Task<Void, Never>?
    @ObservationIgnored private var watchedOnStep: Double = 0
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode(GuidanceState.self, from: data) {
            state = saved
        } else {
            state = GuidanceState()
        }
    }

    // MARK: Tour

    var tourStep: TourStep? { state.tour == .active ? state.step : nil }

    /// The step to draw right now (nil while hidden behind another surface).
    var visibleTourStep: TourStep? {
        guard let step = tourStep,
              step.requiredSurface == nil || step.requiredSurface == currentSurface,
              !blockedByPresentation,
              !SpeechPractice.isListening else { return nil }
        return step
    }

    /// New learners get the tour on their first feed visit. Anyone who already finished or
    /// skipped the old first-session coach, or has used the app a few times, counts as done.
    func startTourIfNeeded(legacyFinished: Bool) {
        guard state.tour == .notStarted else { return }
        if legacyFinished {
            state.tour = .completed
            persist()
            return
        }
        state.start()
        persist()
        enteredStep()
    }

    func replayTour() {
        state.start()
        persist()
        feedRequestTick += 1
        enteredStep()
    }

    func next() {
        guard let step = tourStep else { return }
        state.advance(from: step)
        afterAdvance()
    }

    func skipTour() {
        guard let step = tourStep else { return }
        state.skip()
        persist()
        stuckTask?.cancel()
        showStuckHint = false
        track("guide_skipped", props: ["step": String(step.rawValue)])
    }

    /// Event hook from `Analytics.track`: real actions move the tour forward.
    func observe(_ event: String) {
        switch event {
        case "word_tapped":
            // Tapping a word early (during Discover/Watch) counts too.
            if let step = tourStep, step.sequenceIndex <= TourStep.understand.sequenceIndex {
                state.jump(to: .learn)
                afterAdvance()
            }
        case "word_heard":
            if let step = tourStep, step == .learn || step == .practice {
                state.jump(to: .explore)
                afterAdvance()
            }
        default:
            break
        }
    }

    /// Playback ticks. The Watch step continues by itself after a few seconds of watching.
    func noteWatched(seconds: Double) {
        guard tourStep == .watch, visibleTourStep != nil else { return }
        watchedOnStep += seconds
        if watchedOnStep >= Self.watchSecondsToAdvance {
            state.advance(from: .watch)
            afterAdvance()
        }
    }

    /// The learner opened Vocab on the last step: that's the return action.
    func noteOpenedVocab() {
        guard tourStep == .returnTomorrow else { return }
        state.advance(from: .returnTomorrow)
        afterAdvance()
    }

    func noteOpenedExplore() { advanceTour(from: .explore) }
    func noteOpenedLibrary() { advanceTour(from: .library) }
    func noteOpenedProfile() { advanceTour(from: .profile) }
    func noteOpenedSettings() { advanceTour(from: .settings) }

    private func advanceTour(from step: TourStep) {
        guard tourStep == step else { return }
        state.advance(from: step)
        afterAdvance()
    }

    private func afterAdvance() {
        persist()
        if state.tour == .completed {
            stuckTask?.cancel()
            showStuckHint = false
            track("guide_completed")
        } else {
            enteredStep()
        }
    }

    private func enteredStep() {
        watchedOnStep = 0
        showStuckHint = false
        stuckTask?.cancel()
        let step = state.step
        track("guide_step_viewed", props: ["step": String(step.rawValue), "step_name": step.eyebrow.lowercased().replacingOccurrences(of: " ", with: "_")])
        if step.stuckHint != nil {
            stuckTask = Task { [weak self] in
                try? await Task.sleep(for: Self.stuckDelay)
                guard !Task.isCancelled, let self, self.tourStep == step else { return }
                self.showStuckHint = true
            }
        }
    }

    // MARK: Tips

    /// Shows a tip once, only after the tour is out of the way and when its control is on screen.
    func requestTip(_ tip: CoachTip) {
        guard state.isTourFinished, !state.isDismissed(tip), activeTip == nil else { return }
        activeTip = tip
    }

    /// The tip's screen went away; it may show again next time (it was never dismissed).
    func withdrawTip(_ tip: CoachTip) {
        if activeTip == tip { activeTip = nil }
    }

    func dismissTip() {
        guard let tip = activeTip else { return }
        state.dismiss(tip)
        activeTip = nil
        persist()
    }

    func resetTips() {
        state.dismissedTips = []
        persist()
    }

    /// "Delete my data": back to a first-run guide.
    func resetAll() {
        stuckTask?.cancel()
        state = GuidanceState()
        activeTip = nil
        showStuckHint = false
        persist()
    }

    // MARK: Anchors

    /// Anchors this screen currently cares about.
    func wants(_ anchor: CoachAnchor) -> Bool {
        tourStep?.anchor == anchor || activeTip?.anchor == anchor
    }

    func frame(for anchor: CoachAnchor) -> CGRect? {
        _ = frameRevision
        return frames[anchor]
    }

    func setFrame(_ rect: CGRect?, for anchor: CoachAnchor) {
        let old = frames[anchor]
        frames[anchor] = rect
        if old != rect, wants(anchor) { frameRevision &+= 1 }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(state) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }
}

extension View {
    /// Reports this control's on-screen frame so a coach mark can point at it.
    /// `active` keeps off-screen copies (e.g. neighbouring feed pages) from overwriting it.
    func coachTarget(_ anchor: CoachAnchor, active: Bool = true) -> some View {
        modifier(CoachTargetModifier(anchor: anchor, active: active))
    }
}

private struct CoachTargetModifier: ViewModifier {
    let anchor: CoachAnchor
    let active: Bool

    func body(content: Content) -> some View {
        content.background {
            if active {
                GeometryReader { proxy in
                    let rect = proxy.frame(in: .global)
                    Color.clear
                        .onAppear { GuidanceCenter.shared.setFrame(rect, for: anchor) }
                        .onChange(of: rect) { _, new in GuidanceCenter.shared.setFrame(new, for: anchor) }
                        .onDisappear { GuidanceCenter.shared.setFrame(nil, for: anchor) }
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
    }
}

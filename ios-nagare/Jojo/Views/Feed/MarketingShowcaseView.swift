#if DEBUG
import SwiftUI
import SwiftData

/// Silent marketing walkthroughs for screen-recording.
/// Four core cuts tell the same For You story on Sakura/Amber × neon/non-neon dark.
/// One full tour walks onboarding → core tabs → every appearance (dark neon, non-neon, light).
nonisolated enum MarketingScript: String, CaseIterable, Identifiable, Sendable {
    case coreSakuraDarkNeon
    case coreSakuraDarkOff
    case coreAmberDarkNeon
    case coreAmberDarkOff
    case fullTour

    var id: String { rawValue }

    enum Kind { case core, fullTour }

    var kind: Kind {
        switch self {
        case .fullTour: .fullTour
        default: .core
        }
    }

    var scheme: JojoScheme {
        switch self {
        case .fullTour: .dark
        default: .dark
        }
    }

    /// Locked accent for core cuts. Full tour cycles accents itself.
    var accent: AccentTheme {
        switch self {
        case .coreSakuraDarkNeon, .coreSakuraDarkOff, .fullTour: .sakura
        case .coreAmberDarkNeon, .coreAmberDarkOff: .amber
        }
    }

    /// Neon = `.glow`; non-neon = `.off`.
    var glow: GlowLevel {
        switch self {
        case .coreSakuraDarkNeon, .coreAmberDarkNeon: .glow
        case .coreSakuraDarkOff, .coreAmberDarkOff: .off
        case .fullTour: .glow
        }
    }

    var videoLabel: String {
        switch self {
        case .coreSakuraDarkNeon: return "Video 1"
        case .coreSakuraDarkOff: return "Video 2"
        case .coreAmberDarkNeon: return "Video 3"
        case .coreAmberDarkOff: return "Video 4"
        case .fullTour: return "Video 5"
        }
    }

    var title: String {
        switch self {
        case .coreSakuraDarkNeon: return "Video 1 · Sakura dark neon"
        case .coreSakuraDarkOff: return "Video 2 · Sakura dark"
        case .coreAmberDarkNeon: return "Video 3 · Amber dark neon"
        case .coreAmberDarkOff: return "Video 4 · Amber dark"
        case .fullTour: return "Video 5 · Full app tour"
        }
    }

    var subtitle: String {
        switch kind {
        case .core:
            let neon = glow == .off ? "glow off" : "neon glow"
            return "Same core story on \(accent.title) dark (\(neon)): For You scrolls 3 clips, theater video, word tap → dictionary → save animation → flashcards."
        case .fullTour:
            return "Onboarding → For You → Vocab → Explore → Search → Library → Profile, then every look: dark neon, dark non-neon, and light (Sakura + Amber)."
        }
    }

    var beats: [String] {
        switch kind {
        case .core:
            return [
                "For You opens in \(accent.title) dark\(glow == .off ? "" : " neon")",
                "Library · For You/Explore · Search chrome, then theater mode",
                "Scroll through three clips",
                "Tap a word — dictionary card, conjugation, paint ladder",
                "Flashcard is born and flies to Vocab",
                "Review cards: reveal, Again / Good"
            ]
        case .fullTour:
            return [
                "Onboarding: value, flashcards, then pick a look",
                "For You core: scroll, tap, save, flashcards",
                "Vocab → Explore → Search a word → Library",
                "Profile / settings",
                "Sakura and Amber: dark neon, dark, and light"
            ]
        }
    }
}

/// Full-screen scripted product showcase for screen-recording Jojo marketing clips.
/// DEBUG builds only — never shown in App Store / production UI.
struct MarketingShowcaseView: View {
    var initialScript: MarketingScript = .coreSakuraDarkNeon
    /// Accent hint from Profile. Core scripts lock their own accent; full tour starts here.
    var accent: AccentTheme = .sakura
    /// When true, skips the picker and starts the walkthrough immediately (launch play buttons).
    var autoBegin: Bool = false

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var phase: Phase = .prep
    @State private var selectedScript: MarketingScript = .coreSakuraDarkNeon
    @State private var demoAccent: AccentTheme = .sakura
    @State private var demoScheme: JojoScheme = .dark
    @State private var coordinator = PlaybackCoordinator()
    @State private var lookup = WordLookupController()
    @State private var feedClips: [Clip] = []
    @State private var currentId: String?
    @State private var stage: Stage = .feed
    @State private var showFlashcard: Bool = false
    @State private var flashRevealed: Bool = false
    @State private var flashWord: SavedWord?
    @State private var flashIndex: Int = 0
    @State private var flashWords: [SavedWord] = []
    @State private var scriptTask: Task<Void, Never>?
    @State private var explorePath: LearningPath?
    @State private var watchId: String?
    @State private var exploreHighlight: String?
    @State private var vocabHighlight: String?
    @State private var tabHighlight: AppTab = .feed
    @State private var didAutoBegin: Bool = false
    @State private var bornCard: BornCardPayload?
    /// Mirrors the feed focus fade so the recording shows the capsule and For You switch disappearing.
    @State private var watchChromeVisible: Bool = true
    /// For You only. Starts at the usual frame, then the existing control enlarges it.
    @State private var demoVideoExpanded: Bool = false
    /// Name shown on Feed, Vocab, and Profile after a theme change.
    @State private var themeCaption: String?
    /// Open theme menu during the theme tour. The checked accent is the one on screen.
    @State private var themeMenu: AccentTheme?
    /// Theme, paper, and glow to put back when the recording ends.
    @State private var parkedAccent: AccentTheme?
    @State private var parkedScheme: JojoScheme?
    @State private var parkedGlow: GlowLevel?
    /// Profile scroll target during the theme tour. Nil keeps the theme row.
    @State private var profileAnchor: String?
    /// Word the clip-search beat looks up.
    @State private var demoSearchQuery: String = ""
    /// Full-tour onboarding panel index.
    @State private var onboardingBeat: Int = 0

    private enum Phase { case prep, running, done }
    private enum Stage { case onboarding, feed, explore, watching, vocab, search, library, analytics, flashcard }

    var body: some View {
        ZStack {
            Color.bgPlayer.ignoresSafeArea()
            switch phase {
            case .prep:
                prepScreen
            case .running:
                showcaseStage
                    .id("\(demoAccent.rawValue)-\(demoScheme.rawValue)")
            case .done:
                doneScreen
            }
        }
        .environment(coordinator)
        .environment(lookup)
        .preferredColorScheme(demoScheme.colorScheme)
        .onAppear {
            selectedScript = initialScript
            demoAccent = initialScript.kind == .core ? initialScript.accent : accent
            if parkedAccent == nil {
                parkedAccent = app.profile.theme
                parkedScheme = app.profile.scheme
                parkedGlow = app.profile.glow
            }
            applyLook(accent: demoAccent, scheme: initialScript.scheme, glow: initialScript.glow)
            if autoBegin, !didAutoBegin {
                didAutoBegin = true
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(350))
                    beginShowcase(initialScript)
                }
            }
        }
        .onChange(of: selectedScript) { _, script in
            demoAccent = script.kind == .core ? script.accent : demoAccent
            applyLook(accent: demoAccent, scheme: script.scheme, glow: script.glow)
        }
        .onDisappear {
            scriptTask?.cancel()
            coordinator.stop()
            lookup.dismiss()
            if let parkedAccent, let parkedScheme {
                app.setScheme(parkedScheme)
                app.setTheme(parkedAccent)
            }
            if let parkedGlow {
                app.setGlowLevel(parkedGlow)
            }
            if app.profile.onboardingCompleted {
                app.restorePalette()
            } else {
                JojoPalette.activateOnboarding()
            }
        }
        .onChange(of: currentId) { _, newId in
            guard phase == .running, stage == .feed,
                  !showFlashcard,
                  let newId, let clip = feedClips.first(where: { $0.id == newId }) else { return }
            coordinator.activate(clip, startLine: richestLine(on: clip).index, loopLine: true)
        }
    }

    // MARK: Prep

    private var prepScreen: some View {
        VStack(spacing: Spacing.l) {
            HStack {
                Button("Cancel") { dismiss() }
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
            }
            Spacer(minLength: 0)
            Image(systemName: "record.circle")
                .font(.system(size: 40))
                .foregroundStyle(Color.jojoOrange)
            Text("Marketing demos")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
            Text("DEBUG only. Four theme cuts of the current For You story, plus one full-app tour. Start a screen recording, then tap Begin.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.s)

            ScrollView {
            VStack(spacing: Spacing.m) {
                ForEach(MarketingScript.allCases) { script in
                    Button {
                        Haptics.selection()
                        selectedScript = script
                        demoAccent = script.accent
                    } label: {
                        VStack(alignment: .leading, spacing: Spacing.s) {
                            HStack {
                                Text(script.title)
                                    .font(.headline.weight(.bold))
                                    .foregroundStyle(.white)
                                Spacer()
                                Image(systemName: selectedScript == script ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedScript == script ? Color(hex: "#FF7EB8") : .white.opacity(0.35))
                            }
                            Text(script.subtitle)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.6))
                                .multilineTextAlignment(.leading)
                        }
                        .padding(Spacing.l)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            selectedScript == script ? Color(hex: "#6A2458") : Color.white.opacity(0.06),
                            in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                                .strokeBorder(selectedScript == script ? Color(hex: "#FF7EB8") : Color.white.opacity(0.08), lineWidth: 1.5)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Spacing.l)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(selectedScript.beats.enumerated()), id: \.offset) { i, beat in
                    scriptBeatRow("\(i + 1)", beat)
                }
            }
            .padding(Spacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .padding(.horizontal, Spacing.l)
            .animation(.snappy, value: selectedScript)
            }
            .scrollIndicators(.hidden)

            Spacer(minLength: 0)
            Button {
                Haptics.medium()
                beginShowcase(selectedScript)
            } label: {
                Label("Begin \(selectedScript.title)", systemImage: "play.fill")
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, Spacing.l)
            .padding(.bottom, Spacing.xl)
        }
        .padding(.horizontal, Spacing.l)
        .padding(.top, Spacing.m)
    }

    private func scriptBeatRow(_ n: String, _ text: String) -> some View {
        HStack(spacing: Spacing.m) {
            Text(n)
                .font(.caption.weight(.bold))
                .foregroundStyle(.black)
                .frame(width: 22, height: 22)
                .background(Color.jojoOrange, in: Circle())
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))
        }
    }

    // MARK: Running stage

    private var showcaseStage: some View {
        VStack(spacing: 0) {
            Group {
                switch stage {
                case .onboarding:
                    onboardingChrome
                case .feed:
                    feedChrome
                case .explore:
                    ExploreHomeView(onOpenFeed: {}, scriptedPath: explorePath, featuredClips: feedReel)
                case .watching:
                    if let first = feedReel.first {
                        ClipQueueScreen(
                            clips: feedReel,
                            startId: first.id,
                            startLine: richestLine(on: first).index,
                            loopLine: true,
                            forcedId: watchId,
                            loopPlayback: true,
                            preferMinimized: true
                        )
                    } else {
                        Color.watchBackground
                    }
                case .vocab:
                    VocabView()
                case .search:
                    SearchView(initialQuery: demoSearchQuery, embedded: true)
                case .library:
                    LibraryView(presentedModally: true)
                case .analytics:
                    ProfileView()
                        .environment(\.marketingScrollsToTheme, themeMenu != nil)
                        .environment(\.marketingProfileAnchor, profileAnchor)
                case .flashcard:
                    if let flashWord {
                        flashcardBeat(flashWord)
                            .transition(.asymmetric(
                                insertion: .modifier(active: CardFlip(angle: -92), identity: CardFlip(angle: 0)).combined(with: .opacity),
                                removal: .opacity
                            ))
                    } else {
                        Color.watchBackground
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.4), value: stage)

            if stage != .flashcard && stage != .watching && stage != .onboarding {
                showcaseTabBar
                    .opacity(stage == .feed && !watchChromeVisible ? 0 : 1)
                    .offset(y: stage == .feed && !watchChromeVisible ? 14 : 0)
                    .animation(.easeInOut(duration: 0.45), value: watchChromeVisible)
            }
        }
        .overlay(alignment: .top) {
            if let themeCaption {
                Text(themeCaption)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .background(Color.sakuraButton, in: Capsule())
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .overlay(alignment: .topTrailing) {
            if themeMenu != nil {
                themeMenuCard
                    .padding(.top, 108)
                    .padding(.trailing, 28)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .topTrailing)))
            }
        }
        .overlay {
            if let bornCard {
                BornFlashcard(surface: bornCard.surface, romaji: bornCard.romaji, gloss: bornCard.gloss) {
                    self.bornCard = nil
                }
            }
        }
        .allowsHitTesting(false)
    }

    private var showcaseTabBar: some View {
        JojoDock(selection: $tabHighlight, vocabBadge: walkthroughDueVocabCount)
            .padding(.horizontal, 16)
            .padding(.bottom, 6)
    }

    /// Match the app's dock: this is a review notification, never a decorative card count.
    private var walkthroughDueVocabCount: Int {
        app.relevantDueKeys(limit: 99).count
    }

    /// The same three choices as Profile’s Theme menu, held open for the recording.
    private var themeMenuCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(AccentTheme.allCases.enumerated()), id: \.element.id) { index, theme in
                HStack {
                    Text(theme.title)
                        .font(.body)
                        .foregroundStyle(.primary)
                    Spacer(minLength: 12)
                    if themeMenu == theme {
                        Image(systemName: "checkmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Color.designOrangeDeep)
                    }
                }
                .padding(.horizontal, 16)
                .frame(minWidth: 168, minHeight: 44)
                if index < AccentTheme.allCases.count - 1 {
                    Divider().padding(.leading, 16)
                }
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
    }

    // MARK: For You chrome

    /// Matches live FeedView: Library · For You/Explore · Search above the goal bar, then the pager.
    private var feedChrome: some View {
        VStack(spacing: 0) {
            if !demoVideoExpanded {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        Image(systemName: "books.vertical")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 44, height: 44)
                            .accessibilityLabel("Library")
                        Spacer(minLength: 0)
                        CenteredModeSwitch(forYouSelected: true, onForYou: {}, onExplore: {})
                        Spacer(minLength: 0)
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 44, height: 44)
                            .accessibilityLabel("Search clips by word")
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 2)

                    DailyGoalBar(hidesAfterCompletion: true)
                        .opacity(watchChromeVisible ? 1 : 0)
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            GeometryReader { geo in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(feedReel) { clip in
                            ClipStageView(
                                clip: clip,
                                showsChannelRow: true,
                                immersiveFeed: true,
                                videoExpanded: demoVideoExpanded,
                                onToggleVideoSize: {},
                                onActivate: { coordinator.activate(clip, startLine: richestLine(on: clip).index, loopLine: true) }
                            )
                            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                            .clipped()
                            .id(clip.id)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $currentId)
                .scrollDisabled(true)
            }
        }
        .background(Color.canvas.ignoresSafeArea())
        .animation(.easeInOut(duration: 0.35), value: demoVideoExpanded)
    }

    /// Up to three verified clips for the For You reel.
    private var feedReel: [Clip] {
        Array(feedClips.prefix(3))
    }

    /// Full-tour onboarding panels (silent, for screen recording).
    private var onboardingChrome: some View {
        let panels: [(title: String, detail: String)] = [
            ("Jojo 流れ", "Scroll, listen, and flow into Japanese."),
            ("Tap any word", "The dictionary opens on the clip. Paint how well you know it."),
            ("Flashcards grow", "Every tap becomes a card. Review keeps words sticky."),
            ("Pick your look", "Sakura or Amber. Neon or clean. Light or dark — then the feed.")
        ]
        let panel = panels[min(onboardingBeat, panels.count - 1)]
        return ZStack {
            JojoBrandBackground(scene: .templeDusk, showsHills: true)
            VStack(spacing: 18) {
                JojoMascot(height: 140, floats: true, pose: .cheer)
                Text(panel.title)
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text(panel.detail)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.82))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
                HStack(spacing: 8) {
                    ForEach(0..<panels.count, id: \.self) { i in
                        Capsule()
                            .fill(i == onboardingBeat ? Color.sakuraPink : Color.white.opacity(0.25))
                            .frame(width: i == onboardingBeat ? 22 : 8, height: 6)
                    }
                }
                .padding(.top, 8)
            }
            .padding(24)
        }
        .environment(\.brandSurface, .night)
        .environment(\.colorScheme, .dark)
    }

    // MARK: Flashcard

    private func flashcardBeat(_ word: SavedWord) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                ZStack {
                    ReviewWordmark()
                    HStack {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(FlashcardInk.ink)
                            .frame(width: 44, height: 44)
                        Spacer()
                    }
                }
                HStack(spacing: 10) {
                    GeometryReader { proxy in
                        let progress = flashWords.isEmpty ? 0.2 : Double(flashIndex + 1) / Double(max(flashWords.count, 1))
                        ZStack(alignment: .leading) {
                            Capsule().fill(FlashcardInk.ink.opacity(0.14))
                            Capsule().fill(Color.sakuraButton)
                                .frame(width: proxy.size.width * progress)
                        }
                    }
                    .frame(height: 8)
                    Text("\(flashIndex + 1)/\(max(flashWords.count, 1))")
                        .font(.subheadline.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(FlashcardInk.muted)
                }
            }
            .padding(.horizontal, Spacing.l)
            .padding(.top, Spacing.s)

            ZStack {
                if !flashRevealed {
                    FlashcardHero(
                        surface: word.surface,
                        reading: word.primaryReading,
                        romaji: word.romaji,
                        pos: word.pos,
                        jlpt: word.jlpt,
                        hint: "Tap to reveal"
                    )
                    .padding(.horizontal, Spacing.l)
                }
                if flashRevealed {
                    VStack(spacing: 0) {
                        FittedFlashcard {
                            KikuFlashcardBack(word: word) { _ in }
                                .padding(.horizontal, Spacing.l)
                                .padding(.top, Spacing.s)
                                .padding(.bottom, Spacing.s)
                                .allowsHitTesting(false)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        VStack(spacing: 12) {
                            HStack(spacing: 12) {
                                ReviewGradeButton(title: "Again", interval: SRS.againLabel, good: false)
                                ReviewGradeButton(
                                    title: "Good",
                                    interval: SRS.label(SRS.goodInterval(fromStep: word.intervalStepIndex)),
                                    good: true
                                )
                            }
                        }
                        .padding(.horizontal, Spacing.l)
                        .padding(.bottom, Spacing.l)
                    }
                    .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                }
            }
            .modifier(CardTurnModifier(angle: flashRevealed ? 180 : 0))
            .animation(.spring(response: 0.62, dampingFraction: 0.78), value: flashRevealed)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background { ReviewStageBackground() }
    }

    // MARK: Done

    private var doneScreen: some View {
        VStack(spacing: Spacing.l) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color.jojoOrange)
            Text("Showcase finished")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
            Text("Stop your screen recording.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.xl)
            Spacer()
            if let next = nextCoreScript(after: selectedScript) {
                Button("Record \(next.title)") {
                    selectedScript = next
                    demoAccent = next.accent
                    phase = .prep
                    resetShowcaseState()
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, Spacing.l)
            }
            Button("Run again") {
                phase = .prep
                resetShowcaseState()
            }
            .font(.headline)
            .foregroundStyle(.white.opacity(0.85))
            .frame(minHeight: 48)
            Button("Done") { dismiss() }
                .font(.headline)
                .foregroundStyle(.white.opacity(0.6))
                .frame(minHeight: 44)
                .padding(.bottom, Spacing.xl)
        }
    }

    // MARK: Scripts

    private func demoFeedClips() -> [Clip] {
        app.showcaseClips(limit: 3)
    }

    private func applyLook(accent: AccentTheme, scheme: JojoScheme, glow: GlowLevel) {
        demoAccent = accent
        demoScheme = scheme
        app.setScheme(scheme)
        app.setTheme(accent)
        app.setGlowLevel(glow)
        JojoPalette.activate(theme: accent, scheme: scheme)
    }

    private func nextCoreScript(after script: MarketingScript) -> MarketingScript? {
        let core: [MarketingScript] = [.coreSakuraDarkNeon, .coreSakuraDarkOff, .coreAmberDarkNeon, .coreAmberDarkOff]
        guard let idx = core.firstIndex(of: script), idx + 1 < core.count else { return nil }
        return core[idx + 1]
    }

    private func demoVocabFallback() -> [SavedWord] {
        let descriptor = FetchDescriptor<SavedWord>(sortBy: [SortDescriptor(\.addedAt, order: .reverse)])
        return (try? app.context.fetch(descriptor))?.prefix(6).map { $0 } ?? []
    }

    /// Boxes one content word in green so the recording shows a known word on the transcript.
    private func markDemoKnown(on clip: Clip, lineIndex: Int) -> Token? {
        guard let line = clip.lines[safe: lineIndex] else { return nil }
        guard let token = line.tokens.first(where: { $0.tappable && !$0.definitions.isEmpty && $0.containsKanji })
            ?? line.tokens.first(where: { $0.tappable && !$0.definitions.isEmpty })
            ?? line.tokens.first(where: \.tappable) else { return nil }
        app.paint(token: token, explanation: nil, clip: clip, lineIndex: lineIndex, mark: .known)
        return token
    }

    /// The spoken line with a translation and defined words, so the card explains what was said.
    private func richestLine(on clip: Clip) -> (index: Int, line: Line) {
        guard !clip.lines.isEmpty else {
            return (0, Line(tokens: [], translation: "", start: 0, end: 0))
        }
        let best = clip.lines.enumerated().max { lhs, rhs in
            lineScore(lhs.element) < lineScore(rhs.element)
        }
        if let best { return (best.offset, best.element) }
        return (0, clip.lines[0])
    }

    private func lineScore(_ line: Line) -> Int {
        let words = line.tokens.filter(\.tappable)
        let defined = words.filter { !$0.definitions.isEmpty }.count
        return defined * 3 + min(words.count, 8) + (line.translation.isEmpty ? 0 : 5)
    }

    private func beginShowcase(_ script: MarketingScript) {
        lookup.offlineOnly = true
        lookup.previewOnly = true
        let clips = demoFeedClips()
        feedClips = clips
        guard let first = clips.first else {
            phase = .done
            return
        }
        currentId = first.id
        flashWords = demoVocabFallback()
        app.markVocabSaveCoachSeen()
        onboardingBeat = 0
        demoAccent = script.accent
        applyLook(accent: script.accent, scheme: script.scheme, glow: script.glow)
        stage = script.kind == .fullTour ? .onboarding : .feed
        tabHighlight = .feed
        watchChromeVisible = true
        demoVideoExpanded = false
        phase = .running
        track("marketing_showcase_started", props: [
            "script": script.rawValue,
            "accent": script.accent.rawValue,
            "glow": script.glow.rawValue,
            "clips": clips.map(\.id).joined(separator: ","),
        ])
        scriptTask?.cancel()
        scriptTask = Task { @MainActor in
            applyLook(accent: script.accent, scheme: script.scheme, glow: script.glow)
            switch script.kind {
            case .core:
                await runCoreForYouScript(clips: clips, first: first, glow: script.glow, restoreGlow: true)
            case .fullTour:
                await runFullTour(clips: clips, first: first)
            }
            guard !Task.isCancelled else { return }
            coordinator.stop()
            withAnimation(.easeInOut(duration: 0.35)) { phase = .done }
            track("marketing_showcase_finished", props: ["script": script.rawValue])
        }
    }

    /// Core marketing cut: For You scroll (3) → tap/dictionary/save → flashcards.
    private func runCoreForYouScript(clips: [Clip], first: Clip, glow: GlowLevel, restoreGlow: Bool) async {
        tabHighlight = .feed
        stage = .feed
        app.setGlowLevel(glow)
        let focus = richestLine(on: first)
        let known = markDemoKnown(on: first, lineIndex: focus.index)
        coordinator.activate(first, startLine: focus.index, loopLine: true)
        try? await Task.sleep(for: .milliseconds(1500))
        guard !Task.isCancelled else { return }

        // Normal → maximum while karaoke stays in its own section below the video.
        withAnimation(.snappy) { demoVideoExpanded = true }
        try? await Task.sleep(for: .milliseconds(1700))
        guard !Task.isCancelled else { return }
        await fadeDemoChrome()
        try? await Task.sleep(for: .milliseconds(1200))
        guard !Task.isCancelled else { return }
        await revealDemoChrome()

        var savedFromTap: SavedWord?
        let line = focus.line
        let candidates = line.tokens.enumerated().filter { $0.element.tappable && !$0.element.definitions.isEmpty }
        let rich = candidates.filter { $0.element.surface != known?.surface }
        let pick = rich.first ?? candidates.first
        if let pick {
            let token = pick.element
            lookup.previewOnly = false
            withAnimation(Motion.popupSpring) {
                lookup.select(token: token, tokenIndex: pick.offset, lineIndex: focus.index, clip: first, app: app)
            }
            bornCard = BornCardPayload(
                surface: token.surface,
                romaji: token.romaji,
                gloss: token.definitions.first ?? ""
            )
            try? await Task.sleep(for: .milliseconds(2800))
            guard !Task.isCancelled else { return }
            // Paint ladder beat on the open card.
            app.paint(token: token, explanation: lookup.explanation, clip: first, lineIndex: focus.index, mark: .learning)
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            app.paint(token: token, explanation: lookup.explanation, clip: first, lineIndex: focus.index, mark: .familiar)
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            let key = AppModel.wordKey(for: token)
            savedFromTap = (try? app.context.fetch(
                FetchDescriptor<SavedWord>(predicate: #Predicate { $0.key == key })
            ))?.first
            withAnimation(Motion.popupSpring) { lookup.dismiss() }
            lookup.previewOnly = true
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            bornCard = nil
        }

        // Scroll through remaining clips (2nd and 3rd).
        for clip in clips.dropFirst().prefix(2) {
            guard !Task.isCancelled else { return }
            let nextFocus = richestLine(on: clip)
            withAnimation(.easeInOut(duration: 0.55)) { currentId = clip.id }
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled else { return }
            coordinator.activate(clip, startLine: nextFocus.index, loopLine: true)
            try? await Task.sleep(for: .milliseconds(1100))
            guard !Task.isCancelled else { return }
            await fadeDemoChrome()
            try? await Task.sleep(for: .milliseconds(1400))
            guard !Task.isCancelled else { return }
            await revealDemoChrome()
        }

        flashWords = demoVocabFallback()
        await playFlashcardSequence(startingWith: savedFromTap ?? flashWords.first, count: 2)
        if restoreGlow { restoreParkedGlow() }
    }

    /// Full product tour: onboarding → core → Vocab/Explore/Profile → every theme look.
    private func runFullTour(clips: [Clip], first: Clip) async {
        // Onboarding panels
        withAnimation(.easeInOut(duration: 0.35)) { stage = .onboarding }
        for beat in 0..<4 {
            guard !Task.isCancelled else { return }
            withAnimation(.snappy) { onboardingBeat = beat }
            try? await Task.sleep(for: .milliseconds(beat == 0 ? 1800 : 1600))
        }

        // Core For You story on Sakura dark neon
        applyLook(accent: .sakura, scheme: .dark, glow: .glow)
        withAnimation(.easeInOut(duration: 0.4)) {
            themeCaption = "Sakura · Dark neon"
            stage = .feed
            tabHighlight = .feed
            demoVideoExpanded = false
        }
        try? await Task.sleep(for: .milliseconds(700))
        withAnimation(.easeOut(duration: 0.25)) { themeCaption = nil }
        await runCoreForYouScript(clips: clips, first: first, glow: .glow, restoreGlow: false)
        guard !Task.isCancelled else { return }

        // Vocab
        withAnimation(.easeInOut(duration: 0.4)) {
            stage = .vocab
            tabHighlight = .vocab
        }
        try? await Task.sleep(for: .milliseconds(2600))
        guard !Task.isCancelled else { return }

        // Explore from the top switch
        explorePath = nil
        withAnimation(.easeInOut(duration: 0.4)) {
            stage = .explore
            tabHighlight = .feed
        }
        try? await Task.sleep(for: .milliseconds(1800))
        guard !Task.isCancelled else { return }
        withAnimation(.easeInOut(duration: 0.4)) { explorePath = .listening }
        try? await Task.sleep(for: .milliseconds(1800))
        guard !Task.isCancelled else { return }

        // Search a word (feed header magnifying glass)
        demoSearchQuery = demoSearchWord(from: first)
        withAnimation(.easeInOut(duration: 0.4)) {
            stage = .search
            tabHighlight = .feed
        }
        try? await Task.sleep(for: .milliseconds(2200))
        guard !Task.isCancelled else { return }

        // Library (opened from the feed header, not a dock tab)
        withAnimation(.easeInOut(duration: 0.4)) {
            stage = .library
            tabHighlight = .feed
        }
        try? await Task.sleep(for: .milliseconds(2000))
        guard !Task.isCancelled else { return }

        // Profile / settings
        withAnimation(.easeInOut(duration: 0.4)) {
            stage = .analytics
            tabHighlight = .profile
            profileAnchor = "text-glow"
        }
        try? await Task.sleep(for: .milliseconds(2000))
        guard !Task.isCancelled else { return }

        // Appearance matrix: each accent × dark neon / dark off / light
        let looks: [(AccentTheme, JojoScheme, GlowLevel, String)] = [
            (.sakura, .dark, .glow, "Sakura · Dark neon"),
            (.sakura, .dark, .off, "Sakura · Dark"),
            (.sakura, .light, .soft, "Sakura · Light"),
            (.amber, .dark, .glow, "Amber · Dark neon"),
            (.amber, .dark, .off, "Amber · Dark"),
            (.amber, .light, .soft, "Amber · Light"),
        ]
        let tourLine = richestLine(on: first)
        for look in looks {
            guard !Task.isCancelled else { return }
            coordinator.stop()
            applyLook(accent: look.0, scheme: look.1, glow: look.2)
            withAnimation(.easeInOut(duration: 0.3)) {
                themeMenu = look.0
                themeCaption = look.3
                profileAnchor = nil
                stage = .analytics
                tabHighlight = .profile
            }
            try? await Task.sleep(for: .milliseconds(1100))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.25)) { themeMenu = nil }
            withAnimation(.easeInOut(duration: 0.4)) {
                stage = .feed
                tabHighlight = .feed
                demoVideoExpanded = true
                currentId = first.id
            }
            coordinator.activate(first, startLine: tourLine.index, loopLine: true)
            try? await Task.sleep(for: .milliseconds(2000))
            guard !Task.isCancelled else { return }
            coordinator.stop()
            withAnimation(.easeInOut(duration: 0.35)) {
                stage = .vocab
                tabHighlight = .vocab
            }
            try? await Task.sleep(for: .milliseconds(1600))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) { themeCaption = nil }
        }

        if let parkedAccent, let parkedScheme {
            applyLook(accent: parkedAccent, scheme: parkedScheme, glow: parkedGlow ?? .glow)
        } else {
            restoreParkedGlow()
        }
    }

    private func restoreParkedGlow() {
        if let parkedGlow {
            app.setGlowLevel(parkedGlow)
        }
    }

    /// A real word from the clip so Search shows hits instead of an empty query.
    private func demoSearchWord(from clip: Clip) -> String {
        let tokens = clip.lines.flatMap(\.tokens).filter { $0.tappable && !$0.definitions.isEmpty }
        if let known = tokens.first(where: { $0.containsKanji }) {
            return known.dictionaryForm.isEmpty ? known.surface : known.dictionaryForm
        }
        if let any = tokens.first {
            return any.dictionaryForm.isEmpty ? any.surface : any.dictionaryForm
        }
        return "好き"
    }

    /// Same fade the live feed uses once a clip has the learner's attention.
    private func fadeDemoChrome() async {
        withAnimation(.easeInOut(duration: 0.45)) { watchChromeVisible = false }
        try? await Task.sleep(for: .milliseconds(480))
    }

    /// A touch brings the capsule and the For You / Explore switch back.
    private func revealDemoChrome() async {
        withAnimation(.easeOut(duration: 0.28)) { watchChromeVisible = true }
        try? await Task.sleep(for: .milliseconds(320))
    }

    private func playFlashcardSequence(startingWith first: SavedWord?, count: Int) async {
        var queue = flashWords
        if let first, !queue.contains(where: { $0.key == first.key }) {
            queue.insert(first, at: 0)
        }
        if queue.isEmpty, let first { queue = [first] }
        guard !queue.isEmpty else { return }

        flashWords = queue
        for (i, word) in queue.prefix(count).enumerated() {
            flashIndex = i
            flashWord = word
            flashRevealed = false
            withAnimation(Motion.cardFlip) {
                stage = .flashcard
                showFlashcard = true
                tabHighlight = .vocab
            }
            try? await Task.sleep(for: .milliseconds(1100))
            guard !Task.isCancelled else { return }

            withAnimation(Motion.cardFlip) { flashRevealed = true }
            try? await Task.sleep(for: .milliseconds(4800))
            guard !Task.isCancelled else { return }

            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
        }
    }

    private func resetShowcaseState() {
        scriptTask?.cancel()
        coordinator.stop()
        lookup.dismiss()
        showFlashcard = false
        flashRevealed = false
        flashWord = nil
        flashIndex = 0
        flashWords = []
        bornCard = nil
        feedClips = []
        currentId = nil
        watchId = nil
        explorePath = nil
        stage = .feed
        exploreHighlight = nil
        vocabHighlight = nil
        demoSearchQuery = ""
        tabHighlight = .feed
        watchChromeVisible = true
        demoVideoExpanded = false
        themeCaption = nil
        themeMenu = nil
        profileAnchor = nil
        onboardingBeat = 0
    }
}

/// Kiku-style revolving card entrance for the marketing flashcard beat.
private struct CardFlip: ViewModifier {
    var angle: Double

    func body(content: Content) -> some View {
        content
            .rotation3DEffect(
                .degrees(angle),
                axis: (x: 0, y: 1, z: 0),
                perspective: 0.65
            )
    }
}
#endif

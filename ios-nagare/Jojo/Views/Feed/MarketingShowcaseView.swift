#if DEBUG
import SwiftUI
import SwiftData

/// Which silent marketing walkthrough to screen-record.
nonisolated enum MarketingScript: String, CaseIterable, Identifiable, Sendable {
    case forYou
    case exploreVocab

    var id: String { rawValue }

    var title: String {
        switch self {
        case .forYou: "Video 1 · For You"
        case .exploreVocab: "Video 2 · Explore & Vocab"
        }
    }

    var subtitle: String {
        switch self {
        case .forYou:
            "Two clips play on the black For You page. Plum underlines stay bright, a known word is boxed in green, and the English line is white."
        case .exploreVocab:
            "Explore opens Listening, two clips play on black with the same plum transcript, then Vocab and the flashcards."
        }
    }

    var beats: [String] {
        switch self {
        case .forYou:
            [
                "Channel name above the clip, plum underlines, white English",
                "A word you know is boxed in green",
                "Controls fade, then a touch brings them back",
                "Tap a new word — the dictionary card opens",
                "Swipe to the second clip",
                "The review card shows the definition in full"
            ]
        case .exploreVocab:
            [
                "Explore’s learning paths",
                "Open Listening",
                "Two clips play on black — plum transcript, swipe to the next",
                "Vocab opens with how many words you know",
                "Flashcards show the definition, the sentence, and the clip"
            ]
        }
    }
}

/// Full-screen scripted product showcase for screen-recording Jojo marketing clips.
/// DEBUG builds only — never shown in App Store / production UI.
/// Two clean arcs matching Kiku-style ads: For You immersion, and Explore → Vocab → cards.
struct MarketingShowcaseView: View {
    var initialScript: MarketingScript = .forYou
    /// When true, skips the picker and starts the walkthrough immediately (launch play buttons).
    var autoBegin: Bool = false

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var phase: Phase = .prep
    @State private var selectedScript: MarketingScript = .forYou
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

    private enum Phase { case prep, running, done }
    private enum Stage { case feed, explore, watching, vocab, analytics, flashcard }

    var body: some View {
        ZStack {
            Color.bgPlayer.ignoresSafeArea()
            switch phase {
            case .prep:
                prepScreen
            case .running:
                showcaseStage
            case .done:
                doneScreen
            }
        }
        .environment(coordinator)
        .environment(lookup)
        .preferredColorScheme(.dark)
        .onAppear {
            selectedScript = initialScript
            if autoBegin, !didAutoBegin {
                didAutoBegin = true
                // Let the cover present, then start.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(350))
                    beginShowcase(initialScript)
                }
            }
        }
        .onDisappear {
            scriptTask?.cancel()
            coordinator.stop()
            lookup.dismiss()
        }
        .onChange(of: currentId) { _, newId in
            guard phase == .running, stage == .feed,
                  !showFlashcard,
                  let newId, let clip = feedClips.first(where: { $0.id == newId }) else { return }
            coordinator.activate(clip, startLine: 0, loopLine: true)
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
                .font(.system(size: 48))
                .foregroundStyle(Color.jojoOrange)
            Text("Marketing demos")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
            Text("DEBUG only. Two walkthroughs of the current app. Start a screen recording, then tap Begin.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.s)

            VStack(spacing: Spacing.m) {
                ForEach(MarketingScript.allCases) { script in
                    Button {
                        Haptics.selection()
                        selectedScript = script
                    } label: {
                        VStack(alignment: .leading, spacing: Spacing.s) {
                            HStack {
                                Text(script.title)
                                    .font(.headline.weight(.bold))
                                    .foregroundStyle(.white)
                                Spacer()
                                Image(systemName: selectedScript == script ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedScript == script ? Color.jojoOrange : .white.opacity(0.35))
                            }
                            Text(script.subtitle)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.6))
                                .multilineTextAlignment(.leading)
                        }
                        .padding(Spacing.l)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            selectedScript == script ? Color.sakuraPinkSoft : Color.white.opacity(0.06),
                            in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                                .strokeBorder(selectedScript == script ? Color.sakuraPink : Color.white.opacity(0.08), lineWidth: 1.5)
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

            Spacer(minLength: 0)
            Button {
                Haptics.medium()
                beginShowcase(selectedScript)
            } label: {
                Label("Begin \(selectedScript == .forYou ? "Video 1" : "Video 2")", systemImage: "play.fill")
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
                case .feed:
                    feedChrome
                case .explore:
                    ExploreHomeView(onOpenFeed: {}, scriptedPath: explorePath, featuredClips: feedPair)
                case .watching:
                    if let first = feedPair.first {
                        ClipQueueScreen(
                            clips: feedPair,
                            startId: first.id,
                            startLine: 0,
                            loopLine: true,
                            forcedId: watchId,
                            loopPlayback: true
                        )
                    } else {
                        Color.watchBackground
                    }
                case .vocab:
                    VocabView()
                case .analytics:
                    ProfileView()
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

            if stage != .flashcard && stage != .watching {
                showcaseTabBar
                    .opacity(stage == .feed && !watchChromeVisible ? 0 : 1)
                    .offset(y: stage == .feed && !watchChromeVisible ? 14 : 0)
                    .animation(.easeInOut(duration: 0.45), value: watchChromeVisible)
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
        KikuTabBar(selection: $tabHighlight, vocabBadge: flashWords.count)
            .padding(.bottom, 6)
    }

    // MARK: For You chrome

    private var feedChrome: some View {
        VStack(spacing: 0) {
            if !app.profile.hideDailyGoalBar {
                DailyGoalBar()
                    .padding(.top, 4)
            }
            ZStack {
                CenteredModeSwitch(forYouSelected: true, onForYou: {}, onExplore: {})
                    .opacity(watchChromeVisible ? 1 : 0)
                    .animation(.easeInOut(duration: 0.45), value: watchChromeVisible)
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Image(systemName: "flag")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 40, height: 40)
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 40, height: 40)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 2)

            GeometryReader { geo in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(feedPair) { clip in
                            ClipStageView(
                                clip: clip,
                                showsChannelRow: true,
                                immersiveFeed: true,
                                videoExpanded: true,
                                onToggleVideoSize: {},
                                onActivate: { coordinator.activate(clip, startLine: 0, loopLine: true) }
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
        .background(Color.watchBackground.ignoresSafeArea())
    }

    /// The two bundled clips that actually play. Posters never lead the demo.
    private var feedPair: [Clip] {
        let local = feedClips.filter(\.hasLocalVideo)
        return Array((local.count >= 2 ? local : feedClips).prefix(2))
    }

    // MARK: Flashcard

    private func flashcardBeat(_ word: SavedWord) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: Spacing.m) {
                Image(systemName: "xmark")
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 44, height: 44)
                GeometryReader { proxy in
                    let progress = flashWords.isEmpty ? 0.2 : Double(flashIndex + 1) / Double(max(flashWords.count, 1))
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.12))
                        Capsule().fill(Color.jojoOrange)
                            .frame(width: proxy.size.width * progress)
                    }
                }
                .frame(height: 6)
                Text("\(flashIndex + 1)/\(max(flashWords.count, 1))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(.horizontal, Spacing.l)
            .padding(.top, Spacing.s)

            if !flashRevealed {
                Spacer(minLength: Spacing.s)
                VStack(spacing: Spacing.l) {
                    Text(word.surface)
                        .font(JojoFont.jp(44, bold: true, relativeTo: .largeTitle))
                        .foregroundStyle(.white)
                    Text("Tap to reveal")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.8))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(Spacing.l)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 1.5)
                )
                .padding(.horizontal, Spacing.l)
                Spacer(minLength: Spacing.s)
                Color.clear.frame(height: 8)
            } else {
                FittedFlashcard {
                    KikuFlashcardBack(word: word, dark: true) { _ in }
                        .environment(\.colorScheme, .dark)
                        .padding(.horizontal, Spacing.l)
                        .padding(.top, Spacing.s)
                        .padding(.bottom, Spacing.s)
                        .allowsHitTesting(false)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                HStack(spacing: Spacing.m) {
                    answerChip(title: "Again", subtitle: "<1m", color: .againBackground, fg: .againText)
                    answerChip(title: "Good", subtitle: "<10m", color: .goodBackground, fg: .goodText)
                }
                .padding(.horizontal, Spacing.l)
                .padding(.bottom, Spacing.l)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(Color.bgPlayer.ignoresSafeArea())
    }

    private func answerChip(title: String, subtitle: String, color: Color, fg: Color) -> some View {
        VStack(spacing: 2) {
            Text(title).font(.headline.weight(.bold))
            Text(subtitle).font(.caption.weight(.semibold))
        }
        .foregroundStyle(fg)
        .frame(maxWidth: .infinity, minHeight: 64)
        .background(color, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
            Button("Record the other video") {
                selectedScript = selectedScript == .forYou ? .exploreVocab : .forYou
                phase = .prep
                resetShowcaseState()
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, Spacing.l)
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
        let preferredIds = ["hoshizora-academy-07", "boss-rush-live-09"]
        var ordered: [Clip] = preferredIds.compactMap { app.clip(id: $0) }.filter(\.hasLocalVideo)
        if ordered.count < 2 {
            for clip in app.clips where clip.hasLocalVideo && !ordered.contains(where: { $0.id == clip.id }) {
                ordered.append(clip)
                if ordered.count >= 2 { break }
            }
        }
        return ordered
    }

    private func demoVocabFallback() -> [SavedWord] {
        let descriptor = FetchDescriptor<SavedWord>(sortBy: [SortDescriptor(\.addedAt, order: .reverse)])
        return (try? app.context.fetch(descriptor))?.prefix(6).map { $0 } ?? []
    }

    /// Boxes one content word in green so the recording shows a known word on the transcript.
    private func markDemoKnown(on clip: Clip) -> Token? {
        guard let line = clip.lines.first else { return nil }
        guard let token = line.tokens.first(where: { $0.tappable && $0.containsKanji })
            ?? line.tokens.first(where: \.tappable) else { return nil }
        app.paint(token: token, explanation: nil, clip: clip, lineIndex: 0, mark: .known)
        return token
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
        stage = script == .forYou ? .feed : .explore
        tabHighlight = .feed
        watchChromeVisible = true
        phase = .running
        track("marketing_showcase_started", props: [
            "script": script.rawValue,
            "clips": clips.map(\.id).joined(separator: ","),
        ])
        scriptTask?.cancel()
        scriptTask = Task { @MainActor in
            switch script {
            case .forYou:
                await runForYouScript(clips: clips, first: first)
            case .exploreVocab:
                await runExploreVocabScript(clips: clips, first: first)
            }
            guard !Task.isCancelled else { return }
            coordinator.stop()
            withAnimation(.easeInOut(duration: 0.35)) { phase = .done }
            track("marketing_showcase_finished", props: ["script": script.rawValue])
        }
    }

    /// Video 1: For You immersion → tap → swipe → flashcard reveal.
    private func runForYouScript(clips: [Clip], first: Clip) async {
        tabHighlight = .feed
        stage = .feed
        let known = markDemoKnown(on: first)
        coordinator.activate(first, startLine: 0, loopLine: true)
        try? await Task.sleep(for: .milliseconds(2400))
        guard !Task.isCancelled else { return }
        await fadeDemoChrome()
        try? await Task.sleep(for: .milliseconds(1400))
        guard !Task.isCancelled else { return }
        await revealDemoChrome()

        // Tap a different word so the green box and the new card are both on screen.
        var savedFromTap: SavedWord?
        if let line = first.lines.first {
            let candidates = line.tokens.enumerated().filter { $0.element.tappable && $0.element.containsKanji }
            let pick = candidates.first { $0.element.surface != known?.surface } ?? candidates.first
            if let pick {
                let token = pick.element
                lookup.previewOnly = false
                withAnimation(Motion.popupSpring) {
                    lookup.select(token: token, tokenIndex: pick.offset, lineIndex: 0, clip: first, app: app)
                }
                bornCard = BornCardPayload(
                    surface: token.surface,
                    romaji: token.romaji,
                    gloss: token.definitions.first ?? ""
                )
                try? await Task.sleep(for: .milliseconds(3000))
                guard !Task.isCancelled else { return }
                let key = AppModel.wordKey(for: token)
                savedFromTap = (try? app.context.fetch(
                    FetchDescriptor<SavedWord>(predicate: #Predicate { $0.key == key })
                ))?.first
                withAnimation(Motion.popupSpring) { lookup.dismiss() }
                lookup.previewOnly = true
                try? await Task.sleep(for: .milliseconds(450))
                guard !Task.isCancelled else { return }
            }
        }

        // Swipe to next clip
        if let second = clips.dropFirst().first {
            withAnimation(.easeInOut(duration: 0.55)) { currentId = second.id }
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            coordinator.activate(second, startLine: 0, loopLine: true)
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            await fadeDemoChrome()
            try? await Task.sleep(for: .milliseconds(1600))
            guard !Task.isCancelled else { return }
            await revealDemoChrome()
        }

        // Flashcard ending
        let word = savedFromTap ?? flashWords.first
        await playFlashcardSequence(startingWith: word, count: 2)
    }

    /// Video 2: Explore home → Listening → two clips → Vocab → flashcards.
    private func runExploreVocabScript(clips: [Clip], first: Clip) async {
        tabHighlight = .feed
        explorePath = nil
        _ = markDemoKnown(on: feedPair.first ?? first)
        withAnimation(.easeInOut(duration: 0.35)) { stage = .explore }
        try? await Task.sleep(for: .milliseconds(2200))
        guard !Task.isCancelled else { return }

        withAnimation(.easeInOut(duration: 0.45)) { explorePath = .listening }
        try? await Task.sleep(for: .milliseconds(2200))
        guard !Task.isCancelled else { return }

        let source = feedPair.isEmpty ? clips : feedPair
        let pair = source.isEmpty ? [first] : Array(source.prefix(2))
        let pick = pair[0]
        watchId = pick.id
        withAnimation(.easeInOut(duration: 0.4)) { stage = .watching }
        try? await Task.sleep(for: .milliseconds(2400))
        guard !Task.isCancelled else { return }

        if pair.count > 1 {
            withAnimation(.easeInOut(duration: 0.55)) { watchId = pair[1].id }
            try? await Task.sleep(for: .milliseconds(2600))
            guard !Task.isCancelled else { return }
        }

        if let line = pick.lines.first,
           let idx = line.tokens.firstIndex(where: { $0.containsKanji && $0.tappable })
            ?? line.tokens.firstIndex(where: \.tappable) {
            let token = line.tokens[idx]
            lookup.previewOnly = false
            lookup.select(token: token, tokenIndex: idx, lineIndex: 0, clip: pick, app: app)
            bornCard = BornCardPayload(
                surface: token.surface,
                romaji: token.romaji,
                gloss: token.definitions.first ?? ""
            )
            try? await Task.sleep(for: .milliseconds(3000))
            guard !Task.isCancelled else { return }
            withAnimation(Motion.popupSpring) { lookup.dismiss() }
            bornCard = nil
            lookup.previewOnly = true
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
        }

        flashWords = demoVocabFallback()

        withAnimation(.easeInOut(duration: 0.4)) {
            stage = .vocab
            tabHighlight = .vocab
        }
        try? await Task.sleep(for: .milliseconds(3200))
        guard !Task.isCancelled else { return }

        if let highlight = flashWords.first?.key {
            withAnimation(.snappy) { vocabHighlight = highlight }
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
        }

        withAnimation(.easeInOut(duration: 0.4)) {
            stage = .analytics
            tabHighlight = .profile
        }
        try? await Task.sleep(for: .milliseconds(2600))
        guard !Task.isCancelled else { return }

        await playFlashcardSequence(startingWith: flashWords.first, count: 3)
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
            try? await Task.sleep(for: .milliseconds(1400))
            guard !Task.isCancelled else { return }

            withAnimation(Motion.cardFlip) { flashRevealed = true }
            try? await Task.sleep(for: .milliseconds(3200))
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
        tabHighlight = .feed
        watchChromeVisible = true
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

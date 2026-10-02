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
            "Immersion feed → tap a word → swipe to the next clip → flashcard"
        case .exploreVocab:
            "Explore library → Vocab deck → tap-to-reveal flashcards"
        }
    }

    var beats: [String] {
        switch self {
        case .forYou:
            [
                "For You opens on an anime clip",
                "Tap a word — dictionary popup springs in",
                "Swipe up to the next clip",
                "Flashcard: tap to reveal → Good"
            ]
        case .exploreVocab:
            [
                "Explore grid with filters and posters",
                "Open a clip in the immersive player",
                "Jump to Vocab — saved words from immersion",
                "Review: tap-to-reveal flashcards"
            ]
        }
    }
}

/// Full-screen scripted product showcase for screen-recording Jojo marketing clips.
/// DEBUG builds only — never shown in App Store / production UI.
/// Two clean arcs matching Kiku-style ads: For You immersion, and Explore → Vocab → cards.
struct MarketingShowcaseView: View {
    var initialScript: MarketingScript = .forYou
    /// When true, skips the picker and starts the countdown immediately (launch play buttons).
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
    @State private var countdown: Int?
    @State private var exploreHighlight: String?
    @State private var vocabHighlight: String?
    @State private var tabHighlight: AppTab = .feed
    @State private var didAutoBegin: Bool = false

    private enum Phase { case prep, running, done }
    private enum Stage { case feed, explore, immersive, vocab, analytics, flashcard }

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
        .environment(\.colorScheme, .dark)
        .statusBarHidden(phase == .running)
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
            guard phase == .running, stage == .feed || stage == .immersive,
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
            Text("DEBUG only · never ships to App Store. Two clean Kiku-style walkthroughs. Start a screen recording, pick a video, then tap Begin.")
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
                            selectedScript == script ? Color.jojoOrange.opacity(0.16) : Color.white.opacity(0.06),
                            in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                                .strokeBorder(selectedScript == script ? Color.jojoOrange.opacity(0.7) : Color.white.opacity(0.08), lineWidth: 1.5)
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
        ZStack(alignment: .bottom) {
            Group {
                switch stage {
                case .feed:
                    feedChrome
                case .explore:
                    exploreChrome
                case .immersive:
                    immersiveChrome
                case .vocab:
                    vocabChrome
                case .analytics:
                    analyticsChrome
                case .flashcard:
                    if let flashWord {
                        flashcardBeat(flashWord)
                            .transition(.asymmetric(
                                insertion: .modifier(active: CardFlip(angle: -92), identity: CardFlip(angle: 0)).combined(with: .opacity),
                                removal: .opacity
                            ))
                    } else {
                        Color.bgPlayer
                    }
                }
            }
            .animation(.easeInOut(duration: 0.4), value: stage)

            if stage != .flashcard && stage != .immersive {
                showcaseTabBar
                    .padding(.horizontal, Spacing.l)
                    .padding(.bottom, 10)
            }

            if let countdown {
                Text("\(countdown)")
                    .font(.system(size: 72, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(radius: 12)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .allowsHitTesting(false)
    }

    private var showcaseTabBar: some View {
        HStack(spacing: 0) {
            showcaseTab(.feed, title: "Feed", systemImage: "play.circle.fill")
            showcaseTab(.vocab, title: "Vocab", systemImage: "book.fill", badge: max(flashWords.count, 3))
            showcaseTab(.profile, title: "Profile", systemImage: "person.fill")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.25), radius: 16, y: 6)
    }

    private func showcaseTab(_ tab: AppTab, title: String, systemImage: String, badge: Int = 0) -> some View {
        VStack(spacing: 2) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 44, height: 28)
                if badge > 0, tab == .vocab {
                    Text("\(badge)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .frame(minWidth: 16, minHeight: 16)
                        .background(Color.jojoOrange, in: Capsule())
                        .offset(x: 10, y: -6)
                }
            }
            Text(title).font(.caption2.weight(.semibold))
        }
        .foregroundStyle(tabHighlight == tab ? Color.jojoOrange : Color.white.opacity(0.45))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    // MARK: For You chrome

    private var feedChrome: some View {
        VStack(spacing: 0) {
            DailyGoalBar()
                .padding(.top, 4)
                .environment(\.colorScheme, .dark)
            HStack(spacing: Spacing.m) {
                VStack(spacing: 4) {
                    Text("For You")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Capsule().fill(Color.jojoOrange).frame(width: 28, height: 2)
                }
                Text("Explore")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.35))
                Spacer()
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(width: 40, height: 40)
            }
            .padding(.horizontal, Spacing.l)
            .padding(.bottom, 2)

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(feedClips) { clip in
                        ClipStageView(
                            clip: clip,
                            immersiveFeed: true,
                            onActivate: { coordinator.activate(clip, startLine: 0, loopLine: true) }
                        )
                        .containerRelativeFrame(.vertical)
                        .id(clip.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $currentId)
            .scrollDisabled(true)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: 72)
            }
        }
        .background(Color.canvas.ignoresSafeArea())
    }

    // MARK: Explore chrome

    private var exploreChrome: some View {
        VStack(spacing: 0) {
            DailyGoalBar()
                .padding(.top, 4)
                .environment(\.colorScheme, .dark)
            HStack(spacing: Spacing.m) {
                Text("For You")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.35))
                VStack(spacing: 4) {
                    Text("Explore")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Capsule().fill(Color.jojoOrange).frame(width: 28, height: 2)
                }
                Spacer()
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(width: 40, height: 40)
            }
            .padding(.horizontal, Spacing.l)
            .padding(.bottom, 2)

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Spacing.s) {
                            FilterChip(title: "Saved", systemImage: "bookmark", isSelected: false, dark: true)
                            FilterChip(title: "Difficulty", systemImage: "chart.bar.fill", isSelected: false, dark: true)
                            FilterChip(title: "Anime", systemImage: "sparkles", isSelected: true, dark: true)
                            FilterChip(title: "Source type", systemImage: "play.tv.fill", isSelected: false, dark: true)
                        }
                    }
                    .contentMargins(.horizontal, Spacing.l, for: .scrollContent)

                    LazyVStack(spacing: Spacing.l) {
                        ForEach(feedClips) { clip in
                            showcaseExploreCard(clip)
                                .scaleEffect(exploreHighlight == clip.id ? 1.02 : 1)
                                .overlay(
                                    RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                                        .strokeBorder(exploreHighlight == clip.id ? Color.jojoOrange : .clear, lineWidth: 2.5)
                                )
                                .animation(.snappy, value: exploreHighlight)
                        }
                    }
                    .padding(.horizontal, Spacing.l)
                }
                .padding(.vertical, Spacing.m)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: 72)
            }
        }
        .background(Color.canvas.ignoresSafeArea())
    }

    private func showcaseExploreCard(_ clip: Clip) -> some View {
        Color.bgElevatedDark
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay { GradientPoster(clip: clip).allowsHitTesting(false) }
            .overlay(alignment: .topLeading) {
                Text(clip.difficulty)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.jojoOrange.opacity(0.9), in: Capsule())
                    .padding(Spacing.s)
            }
            .overlay(alignment: .topTrailing) {
                Text(formatClock(clip.durationSec))
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.5), in: Capsule())
                    .padding(Spacing.s)
            }
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 88)
                    .overlay(alignment: .bottomLeading) {
                        VStack(alignment: .leading, spacing: 4) {
                            if let line = clip.lines.first {
                                Text(line.text)
                                    .font(JojoFont.jp(17, bold: true, relativeTo: .headline))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                            }
                            Text(clip.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.8))
                                .lineLimit(1)
                        }
                        .padding(Spacing.m)
                    }
            }
            .clipShape(.rect(cornerRadius: Radius.card, style: .continuous))
    }

    // MARK: Immersive chrome

    private var immersiveChrome: some View {
        Group {
            if let clip = feedClips.first(where: { $0.id == currentId }) ?? feedClips.first {
                VStack(spacing: 0) {
                    HStack(spacing: Spacing.m) {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(Color.white.opacity(0.12), in: Circle())
                        ChannelAvatar(clip: clip, size: 36)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(clip.title).font(.subheadline.weight(.semibold)).foregroundStyle(.white).lineLimit(1)
                            Text(clip.channelName).font(.caption).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "flag").foregroundStyle(.white.opacity(0.7)).frame(width: 40, height: 40)
                    }
                    .padding(.horizontal, Spacing.l)
                    .padding(.vertical, Spacing.s)

                    ClipStageView(
                        clip: clip,
                        immersiveFeed: true,
                        showsChannelRow: false,
                        onActivate: { coordinator.activate(clip, startLine: 0, loopLine: true) }
                    )
                }
                .background(Color.bgPlayer.ignoresSafeArea())
            }
        }
    }

    // MARK: Vocab chrome

    private var vocabChrome: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Vocab")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(.white)
                Spacer()
                Image(systemName: "text.magnifyingglass")
                    .foregroundStyle(Color.jojoOrange)
                    .frame(width: 44, height: 44)
            }
            .padding(.horizontal, Spacing.l)
            .padding(.top, Spacing.s)

            Picker("", selection: .constant(VocabSection.all)) {
                Text("Review").tag(VocabSection.review)
                Text("All Words").tag(VocabSection.all)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Spacing.l)
            .padding(.vertical, Spacing.s)

            ScrollView {
                VStack(spacing: Spacing.s) {
                    let words = flashWords.isEmpty ? demoVocabFallback() : flashWords
                    ForEach(words.prefix(6), id: \.key) { word in
                        HStack(spacing: Spacing.m) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(word.surface)
                                    .font(JojoFont.jp(22, bold: true, relativeTo: .title3))
                                    .foregroundStyle(.white)
                                Text(word.readings.joined(separator: " · "))
                                    .font(JojoFont.jp(13, relativeTo: .caption))
                                    .foregroundStyle(.white.opacity(0.55))
                                if let def = word.definitions.first {
                                    Text(def)
                                        .font(.caption)
                                        .foregroundStyle(.white.opacity(0.7))
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                            if let jlpt = word.jlpt {
                                PillView(text: jlpt, style: .jlpt)
                            }
                        }
                        .padding(Spacing.m)
                        .background(
                            Color.bgElevatedDark,
                            in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                                .strokeBorder(vocabHighlight == word.key ? Color.jojoOrange : Color.white.opacity(0.06), lineWidth: vocabHighlight == word.key ? 2 : 1)
                        )
                        .scaleEffect(vocabHighlight == word.key ? 1.02 : 1)
                        .animation(.snappy, value: vocabHighlight)
                        .padding(.horizontal, Spacing.l)
                    }
                }
                .padding(.vertical, Spacing.s)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: 72)
            }
        }
        .background(Color.canvas.ignoresSafeArea())
    }

    // MARK: Analytics chrome (Profile study stats)

    private var analyticsChrome: some View {
        VStack(spacing: Spacing.l) {
            HStack {
                Text("Profile")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(.white)
                Spacer()
            }
            .padding(.horizontal, Spacing.l)
            .padding(.top, Spacing.s)

            HStack(spacing: Spacing.m) {
                showcaseStat(symbol: "flame.fill", tint: .jojoOrange, value: "\(max(app.currentStreak, 3))-day", caption: "streak")
                showcaseStat(symbol: "clock", tint: .secondary, value: "12m", caption: "watched")
            }
            .padding(.horizontal, Spacing.l)

            VStack(alignment: .leading, spacing: Spacing.m) {
                Text("This week")
                    .font(.headline)
                    .foregroundStyle(.white)
                HStack(alignment: .bottom, spacing: 10) {
                    ForEach(0..<7, id: \.self) { day in
                        let height: CGFloat = [28, 44, 36, 58, 48, 62, 40][day]
                        VStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.jojoOrangeLight, Color.jojoOrange],
                                        startPoint: .bottom,
                                        endPoint: .top
                                    )
                                )
                                .frame(height: height)
                            Text(["M", "T", "W", "T", "F", "S", "S"][day])
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.45))
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 90, alignment: .bottom)
                .padding(Spacing.l)
                .background(Color.bgElevatedDark, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            }
            .padding(.horizontal, Spacing.l)

            VStack(alignment: .leading, spacing: Spacing.s) {
                Text("Mastery")
                    .font(.headline)
                    .foregroundStyle(.white)
                HStack(spacing: Spacing.m) {
                    masteryChip("New", "\(max(flashWords.count, 8))", .jojoOrange)
                    masteryChip("Learning", "12", .sakuraPink)
                    masteryChip("Known", "34", .spokenGreen)
                }
            }
            .padding(.horizontal, Spacing.l)

            Spacer(minLength: 0)
        }
        .background(Color.canvas.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: 72)
        }
    }

    private func showcaseStat(symbol: String, tint: Color, value: String, caption: String) -> some View {
        HStack(spacing: Spacing.m) {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(value).font(.headline.weight(.bold)).foregroundStyle(.white)
                Text(caption).font(.caption).foregroundStyle(.white.opacity(0.5))
            }
            Spacer(minLength: 0)
        }
        .padding(Spacing.m)
        .background(Color.bgElevatedDark, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    private func masteryChip(_ title: String, _ value: String, _ tint: Color) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.title3.weight(.bold)).foregroundStyle(.white)
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, minHeight: 64)
        .background(Color.bgElevatedDark, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    // MARK: Flashcard

    private func flashcardBeat(_ word: SavedWord) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: Spacing.m) {
                Image(systemName: "xmark")
                    .foregroundStyle(.white.opacity(0.5))
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

            Spacer(minLength: Spacing.l)

            ZStack {
                if !flashRevealed {
                    VStack(spacing: Spacing.l) {
                        Text(word.surface)
                            .font(JojoFont.jp(44, bold: true, relativeTo: .largeTitle))
                            .foregroundStyle(.white)
                        Text("Tap to reveal")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                    .frame(maxWidth: .infinity, minHeight: 300)
                    .padding(Spacing.l)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.sheet, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.2), lineWidth: 1.5)
                    )
                    .padding(.horizontal, Spacing.l)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: Spacing.l) {
                            WordHeaderCard(
                                surface: word.surface,
                                readings: word.readings,
                                romaji: word.romaji,
                                pos: word.pos,
                                conjugationClass: word.conjugationClass,
                                jlpt: word.jlpt,
                                showFurigana: true,
                                showRomaji: true
                            )
                            .environment(\.colorScheme, .dark)

                            Text("Definitions")
                                .font(.headline)
                                .foregroundStyle(.white.opacity(0.55))
                            ForEach(Array(word.definitions.prefix(2).enumerated()), id: \.offset) { i, def in
                                DefinitionRow(number: i + 1, tag: word.pos, text: def, dark: true)
                            }
                            if !word.contextSentence.isEmpty {
                                Text("Context")
                                    .font(.headline)
                                    .foregroundStyle(.white.opacity(0.55))
                                HighlightedSentence(
                                    sentence: word.contextSentence,
                                    target: word.contextSurface.isEmpty ? word.surface : word.contextSurface,
                                    size: 19,
                                    baseColor: .white
                                )
                                .padding(Spacing.l)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.bgElevatedDark, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                                if let clip = app.clip(id: word.contextClipId) {
                                    ClipThumbnailButton(clip: clip, emphasizesPlay: true) {}
                                        .disabled(true)
                                }
                            }
                        }
                        .padding(Spacing.l)
                    }
                }
            }
            .animation(Motion.cardFlip, value: flashRevealed)

            if flashRevealed {
                HStack(spacing: Spacing.m) {
                    answerChip(title: "Again", subtitle: "<1m", color: .againBackground, fg: .againText)
                    answerChip(title: "Good", subtitle: "<10m", color: .goodBackground, fg: .goodText)
                }
                .padding(Spacing.l)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                Color.clear.frame(height: 88)
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
            Text("Stop your screen recording, then trim the countdown if you want.")
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
        var ordered: [Clip] = []
        for id in preferredIds {
            if let clip = app.clip(id: id), clip.hasLocalVideo || clip.hasPlayableVideo {
                ordered.append(clip)
            }
        }
        if ordered.count < 2 {
            for clip in app.clips where clip.hasLocalVideo && !ordered.contains(where: { $0.id == clip.id }) {
                ordered.append(clip)
                if ordered.count >= 2 { break }
            }
        }
        if ordered.isEmpty, let fallback = app.recommendedClip(preferShort: true) ?? app.clips.first {
            ordered = [fallback]
        }
        // Pad explore grid with a couple more for Video 2.
        if ordered.count < 4 {
            for clip in app.clips where !ordered.contains(where: { $0.id == clip.id }) {
                ordered.append(clip)
                if ordered.count >= 4 { break }
            }
        }
        return ordered
    }

    private func demoVocabFallback() -> [SavedWord] {
        let descriptor = FetchDescriptor<SavedWord>(sortBy: [SortDescriptor(\.addedAt, order: .reverse)])
        return (try? app.context.fetch(descriptor))?.prefix(6).map { $0 } ?? []
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
        phase = .running
        track("marketing_showcase_started", props: [
            "script": script.rawValue,
            "clips": clips.map(\.id).joined(separator: ","),
        ])
        scriptTask?.cancel()
        scriptTask = Task { @MainActor in
            await runCountdown()
            guard !Task.isCancelled else { return }
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

    private func runCountdown() async {
        for n in [3, 2, 1] {
            withAnimation(.snappy) { countdown = n }
            Haptics.selection()
            try? await Task.sleep(for: .milliseconds(700))
            if Task.isCancelled { return }
        }
        withAnimation { countdown = nil }
    }

    /// Video 1: For You immersion → tap → swipe → flashcard reveal.
    private func runForYouScript(clips: [Clip], first: Clip) async {
        tabHighlight = .feed
        stage = .feed
        coordinator.activate(first, startLine: 0, loopLine: true)
        try? await Task.sleep(for: .milliseconds(1800))
        guard !Task.isCancelled else { return }

        // Tap a word — highlight new vocabulary
        var savedFromTap: SavedWord?
        if let line = first.lines.first,
           let idx = line.tokens.firstIndex(where: { $0.containsKanji && $0.tappable })
            ?? line.tokens.firstIndex(where: \.tappable) {
            let token = line.tokens[idx]
            lookup.previewOnly = false
            withAnimation(Motion.popupSpring) {
                lookup.select(token: token, tokenIndex: idx, lineIndex: 0, clip: first, app: app)
            }
            try? await Task.sleep(for: .milliseconds(2800))
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

        // Swipe to next clip
        if let second = clips.dropFirst().first {
            withAnimation(.easeInOut(duration: 0.55)) { currentId = second.id }
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            coordinator.activate(second, startLine: 0, loopLine: true)
            try? await Task.sleep(for: .milliseconds(2400))
            guard !Task.isCancelled else { return }
        }

        // Flashcard ending
        let word = savedFromTap ?? flashWords.first
        await playFlashcardSequence(startingWith: word, count: 2)
    }

    /// Video 2: Explore → immersive → Vocab → analytics → flashcards.
    private func runExploreVocabScript(clips: [Clip], first: Clip) async {
        tabHighlight = .feed
        withAnimation(.easeInOut(duration: 0.35)) { stage = .explore }
        try? await Task.sleep(for: .milliseconds(2200))
        guard !Task.isCancelled else { return }

        let pick = clips.first ?? first
        withAnimation(.snappy) { exploreHighlight = pick.id }
        try? await Task.sleep(for: .milliseconds(900))
        guard !Task.isCancelled else { return }

        currentId = pick.id
        withAnimation(.easeInOut(duration: 0.4)) {
            stage = .immersive
            exploreHighlight = nil
        }
        coordinator.activate(pick, startLine: 0, loopLine: true)
        try? await Task.sleep(for: .milliseconds(1600))
        guard !Task.isCancelled else { return }

        if let line = pick.lines.first,
           let idx = line.tokens.firstIndex(where: { $0.containsKanji && $0.tappable })
            ?? line.tokens.firstIndex(where: \.tappable) {
            let token = line.tokens[idx]
            lookup.previewOnly = false
            withAnimation(Motion.popupSpring) {
                lookup.select(token: token, tokenIndex: idx, lineIndex: 0, clip: pick, app: app)
            }
            try? await Task.sleep(for: .milliseconds(2000))
            guard !Task.isCancelled else { return }
            withAnimation(Motion.popupSpring) { lookup.dismiss() }
            lookup.previewOnly = true
            try? await Task.sleep(for: .milliseconds(400))
        }

        coordinator.pause()
        flashWords = demoVocabFallback()

        withAnimation(.easeInOut(duration: 0.4)) {
            stage = .vocab
            tabHighlight = .vocab
        }
        try? await Task.sleep(for: .milliseconds(1400))
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
            try? await Task.sleep(for: .milliseconds(2200))
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
        countdown = nil
        feedClips = []
        currentId = nil
        stage = .feed
        exploreHighlight = nil
        vocabHighlight = nil
        tabHighlight = .feed
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

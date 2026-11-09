import SwiftUI

/// Explore tab: six learning lanes, matching the product design.
struct ExploreHomeView: View {
    var onOpenFeed: () -> Void = {}
    var tabBarHidden: Binding<Bool> = .constant(false)
    /// Debug walkthrough pushes this path after the home screen is on screen.
    var scriptedPath: LearningPath? = nil
    /// Clips pinned to the top of a path list during the marketing walkthrough.
    var featuredClips: [Clip] = []

    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @State private var showGoal: Bool = false
    @State private var showCapture: Bool = false
    @State private var showImport: Bool = false
    @State private var showExploreFilters = false
    @State private var exploreFilters = ExploreFilters()
    @State private var path = NavigationPath()
    @State private var dueKeys: [String] = []
    @State private var reviewSession: ReviewSessionConfig?
    @State private var playing: Clip?
    @State private var playQueue: [Clip] = []
    @State private var playLine: Int?
    @State private var practiceClip: Clip?
    @State private var reviewDone = false
    @State private var watchDone = false
    @State private var speakDone = false
    @State private var speakCoordinator = PlaybackCoordinator()
    @State private var showSpeakingScenes = false

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 0) {
                        Color.clear.frame(width: 44, height: 44)
                        Spacer(minLength: 0)
                        CenteredModeSwitch(
                            forYouSelected: false,
                            onForYou: onOpenFeed,
                            onExplore: {}
                        )
                        Spacer(minLength: 0)
                        Button {
                            path.append(LearningPath.jlpt)
                        } label: {
                            Image(systemName: "map")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("My Path")
                    }
                    StudySessionClock(running: scenePhase == .active)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if !app.profile.hideDailyGoalBar {
                        DailyGoalBar()
                    }
                    exploreFinder
                    Text("More ways to learn")
                        .font(.headline)
                    Button {
                        Haptics.selection()
                        showSpeakingScenes = true
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "mic.fill")
                                .font(.title3.weight(.bold))
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .background(Color.sakuraButton, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Speaking scenes")
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text("Konbini, station, restaurant — say it out loud.")
                                    .font(.caption)
                                    .foregroundStyle(Color.studyMuted)
                                    .lineLimit(2)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(14)
                        .background(Color.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.cardStroke))
                    }
                    .buttonStyle(.plain)
                    todayPlan
                    if app.immersion.isAvailable {
                        importRow
                    }
                    captureRow
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .background(Color.studyPage.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: LearningPath.self) { path in
                LearningPathScreen(path: path, featuredClips: featuredClips)
            }
            .navigationDestination(for: SearchRoute.self) { route in
                SearchView(initialQuery: route.initialQuery,
                           initialScope: route.initialQuery.isEmpty ? .all : .sentences,
                           embedded: true)
            }
            .navigationDestination(for: TopicHub.self) { _ in
                TopicStylesView()
            }
            .navigationDestination(for: ExploreBrowseRoute.self) { _ in
                ExploreView(initialFilters: exploreFilters) { clip, line, list in
                    playQueue = list
                    playLine = line
                    playing = clip
                }
                .navigationTitle("Explore Clips")
                .navigationBarTitleDisplayMode(.inline)
            }
            .sheet(isPresented: $showExploreFilters) {
                ExploreFiltersSheet(
                    filters: $exploreFilters,
                    lockedDifficulty: nil,
                    lockTopic: false,
                    count: { filters in
                        app.studyLibrary.filter {
                            filters.matches($0, finishedClipIds: app.profile.finishedClipIds)
                        }.count
                    },
                    onApply: { path.append(ExploreBrowseRoute.results) }
                )
            }
            .sheet(isPresented: $showGoal) {
                DailyGoalSheet()
            }
            .sheet(isPresented: $showSpeakingScenes, onDismiss: reloadPlan) {
                SpeakingScenesView()
            }
            .sheet(isPresented: $showCapture) {
                CaptureJapaneseView()
            }
            .sheet(isPresented: $showImport) {
                ImmersionImportView()
                    .environment(app)
            }
            .fullScreenCover(item: $reviewSession, onDismiss: reloadPlan) { config in
                ReviewSessionView(config: config)
            }
            .fullScreenCover(item: $playing, onDismiss: {
                playQueue = []
                playLine = nil
                reloadPlan()
            }) { clip in
                ClipPlayerScreen(clip: clip,
                                 queue: playQueue.isEmpty ? app.personalized(app.studyLibrary) : playQueue,
                                 startLine: playLine,
                                 loopLine: playLine != nil)
                    .environment(app)
            }
            .sheet(item: $practiceClip, onDismiss: reloadPlan) { clip in
                ShadowingOverlay(clip: clip)
                    .environment(speakCoordinator)
                    .environment(app)
            }
        }
        .onAppear { reloadPlan() }
        .onChange(of: app.reviewAvailabilityRevision) { _, _ in reloadPlan() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { reloadPlan() }
        }
        .onChange(of: scriptedPath) { _, newPath in
            guard let newPath else { return }
            path.append(newPath)
        }
    }

    private var exploreFinder: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                NavigationLink(value: SearchRoute.search) {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        Text("English, Japanese, or romaji")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 48)
                    .background(Color.fieldFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Search clips")

                Button {
                    Haptics.selection()
                    showExploreFilters = true
                } label: {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(exploreFilters.activeCount == 0 ? Color.primary : Color.white)
                        .frame(width: 48, height: 48)
                        .background(
                            exploreFilters.activeCount == 0 ? Color.fieldFill : Color.designOrange,
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                        .overlay(alignment: .topTrailing) {
                            if exploreFilters.activeCount > 0 {
                                Text("\(exploreFilters.activeCount)")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 20, height: 20)
                                    .background(Color.sakuraButton, in: Circle())
                                    .offset(x: 5, y: -5)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Filter clips")
                .accessibilityValue(exploreFilters.activeCount == 0 ? "No filters" : "\(exploreFilters.activeCount) active")
            }

            VStack(spacing: 4) {
                Text("Explore Clips")
                    .font(.title3.weight(.bold))
                Text("Search and filter to find exactly what you want to study.")
                    .font(.caption)
                    .foregroundStyle(Color.studyMuted)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10)
            ], spacing: 10) {
                finderCard("🔍", title: "Search a word", subtitle: "Find clips containing any word") {
                    path.append(SearchRoute.search)
                }
                finderCard("🎯", title: "Difficulty levels", subtitle: "Filter by your current level") {
                    showExploreFilters = true
                }
                finderCard("📖", title: "Grammar patterns", subtitle: "Find grammar in real speech") {
                    path.append(LearningPath.grammar)
                }
                finderCard("🎬", title: "Topic & source", subtitle: "Browse anime, interviews, and more") {
                    showExploreFilters = true
                }
            }

            if exploreFilters.activeCount > 0 {
                Button {
                    path.append(ExploreBrowseRoute.results)
                } label: {
                    Label("Show \(matchingExploreClipCount) matching clips", systemImage: "play.rectangle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.designOrangeDeep)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(Color.designOrange.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func finderCard(_ emoji: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Text(emoji).font(.title2)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(Color.studyMuted)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 126, alignment: .topLeading)
            .background(Color.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.cardStroke))
        }
        .buttonStyle(PressableStyle())
    }

    private var matchingExploreClipCount: Int {
        app.studyLibrary.filter {
            exploreFilters.matches($0, finishedClipIds: app.profile.finishedClipIds)
        }.count
    }

    private var searchEntry: some View {
        VStack(alignment: .leading, spacing: 10) {
            NavigationLink(value: SearchRoute.search) {
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.studyAccent)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Search a word or phrase")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text("Hear it used in real clips")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold)).foregroundStyle(.secondary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.card, in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.cardStroke))
            }
            .buttonStyle(.plain)
            HStack(spacing: 8) {
                Text("Try").font(.caption).foregroundStyle(.secondary)
                ForEach(["好き", "大丈夫", "ありがとう"], id: \.self) { word in
                    NavigationLink(value: SearchRoute.query(word)) {
                        Text(word).font(JojoFont.jp(14, relativeTo: .subheadline))
                            .foregroundStyle(Color.studyAccent)
                            .padding(.horizontal, 12).frame(minHeight: 44)
                            .background(Color.studyAccent.opacity(0.08), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            Button(action: onOpenFeed) {
                JojoBrandIcon(size: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Go to For You")
            Spacer(minLength: 0)
            NavigationLink(value: SearchRoute.search) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 40, height: 40)
            }
            .accessibilityLabel("Search")
            Button {
                showGoal = true
            } label: {
                Image(systemName: app.isGoalReached ? "trophy.fill" : "trophy")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(app.isGoalReached ? Color.designOrange : .primary)
                    .frame(width: 40, height: 40)
            }
            .accessibilityLabel("Daily goal")
        }
    }

    /// Prefers the best-fit clip where today's review words come back, so watching doubles as review.
    private var suggestion: (clip: Clip, matches: Int)? {
        if let pick = app.reviewReinforcingClip(dueKeys: dueKeys), pick.matches > 0 { return pick }
        return app.recommendedClip(preferShort: true).map { (clip: $0, matches: 0) }
    }

    private var todayPlan: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Today")
                .font(.headline)
            if dueKeys.isEmpty {
                planRow(symbol: "checkmark.circle.fill", title: "Review", subtitle: "You're caught up", done: true) {}
                    .disabled(true)
            } else {
                planRow(
                    symbol: "rectangle.stack",
                    title: "Review \(dueKeys.count)",
                    subtitle: "Words you keep meeting",
                    done: reviewDone
                ) {
                    reviewSession = ReviewSessionConfig(title: "Today", keys: dueKeys)
                }
            }
            if let suggestion {
                let clip = suggestion.clip
                planRow(
                    symbol: "play.fill",
                    title: "Watch a clip",
                    subtitle: suggestion.matches > 0
                        ? "\(suggestion.matches) of your review word\(suggestion.matches == 1 ? "" : "s") · \(clip.title)"
                        : clip.title,
                    done: watchDone
                ) {
                    playing = clip
                }
                planRow(symbol: "mic.fill", title: "Say a line", subtitle: "Listen, then speak it back", done: speakDone) {
                    practiceClip = clip
                }
            }
        }
    }

    /// Paste a YouTube link and get a captioned, tappable lesson.
    private var importRow: some View {
        Button {
            Haptics.selection()
            showImport = true
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.card)
                    Image(systemName: "play.rectangle.on.rectangle.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Color.designOrangeDeep)
                }
                .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 3) {
                    Text("From your own video")
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(importSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .contentTransition(.opacity)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(Color.sakuraPinkLight, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Make a lesson from a YouTube video")
        .coachTarget(.exploreImport)
        .task {
            try? await Task.sleep(for: .seconds(1.5))
            GuidanceCenter.shared.requestTip(.exploreImport)
        }
        .onDisappear { GuidanceCenter.shared.withdrawTip(.exploreImport) }
    }

    private var importSubtitle: String {
        let active = app.immersion.activeCount
        if active > 0 { return active == 1 ? "1 video in progress" : "\(active) videos in progress" }
        let ready = app.immersion.readyClips.count
        if ready > 0 { return ready == 1 ? "1 lesson ready — paste another link" : "\(ready) lessons ready — paste another link" }
        return "Paste a YouTube link, get tappable captions"
    }

    private var captureRow: some View {
        Button {
            Haptics.selection()
            showCapture = true
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.card)
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Color.designOrangeDeep)
                }
                .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 3) {
                    Text("From a photo")
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text("Signs, menus, manga, and screenshots")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(Color.sakuraPinkLight, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Read Japanese from a photo")
    }

    private func planRow(symbol: String, title: String, subtitle: String, done: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: done ? "checkmark.circle.fill" : symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(done ? Color.spokenGreen : Color.designOrange)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
            }
            .padding(12)
            .background(Color.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.cardStroke))
        }
        .buttonStyle(.plain)
    }

    private func reloadPlan() {
        dueKeys = app.relevantDueKeys()
        reviewDone = DailyPlanProgress.isDone(.review)
        watchDone = DailyPlanProgress.isDone(.watch)
        speakDone = DailyPlanProgress.isDone(.speak)
    }
}

nonisolated enum ExploreBrowseRoute: Hashable, Sendable {
    case results
}

nonisolated enum SearchRoute: Hashable, Sendable {
    case search
    case query(String)

    var initialQuery: String {
        switch self {
        case .search: ""
        case .query(let text): text
        }
    }
}

nonisolated enum TopicHub: Hashable, Sendable {
    case topics
}

private struct TopicStylesView: View {
    private let paths: [LearningPath] = [.conversation, .listening, .culture, .practice]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Pick a style and watch it in real clips.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(paths) { path in
                    NavigationLink(value: path) {
                        LearningPathCard(path: path)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
        }
        .background(Color.studyPage.ignoresSafeArea())
        .navigationTitle("Topics & styles")
        .navigationBarTitleDisplayMode(.inline)
    }
}

nonisolated enum LearningPath: String, CaseIterable, Identifiable, Hashable, Sendable {
    case conversation, grammar, listening, culture, jlpt, practice

    var id: String { rawValue }

    var title: String {
        switch self {
        case .conversation: "Conversation"
        case .grammar: "Grammar"
        case .listening: "Listening"
        case .culture: "Culture"
        case .jlpt: "JLPT Prep"
        case .practice: "Speaking Practice"
        }
    }

    var subtitle: String {
        switch self {
        case .conversation: "Real-life dialogues & practical phrases"
        case .grammar: "Build your foundation"
        case .listening: "Hear native Japanese in context"
        case .culture: "Discover Japan’s traditions, life, and people"
        case .jlpt: "Find real clips by vocabulary level"
        case .practice: "Repeat clip dialogue and compare what was heard"
        }
    }

    /// Pastel lane from the study-screen design. Dark values stay readable at night.
    var tint: Color {
        switch self {
        case .conversation: Color.adaptive(light: "#FFF1D6", dark: "#3A2A16")
        case .grammar: Color.adaptive(light: "#FDE7EF", dark: "#3A2230")
        case .listening: Color.adaptive(light: "#E5F1FF", dark: "#1A2C3E")
        case .culture: Color.adaptive(light: "#F3E8FF", dark: "#2C243C")
        case .jlpt: Color.adaptive(light: "#E5F6EA", dark: "#1A3326")
        case .practice: Color.adaptive(light: "#FFF6E4", dark: "#332816")
        }
    }

    var symbol: String {
        switch self {
        case .conversation: "building.columns.fill"
        case .grammar: "character.book.closed.fill"
        case .listening: "headphones"
        case .culture: "mountain.2.fill"
        case .jlpt: "graduationcap.fill"
        case .practice: "bubble.left.and.bubble.right.fill"
        }
    }

    var glyph: String? {
        switch self {
        case .grammar: "文法"
        case .jlpt: "N5"
        default: nil
        }
    }
}

private struct LearningPathCard: View {
    let path: LearningPath
    @Environment(AppModel.self) private var app

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.card)
                if let glyph = path.glyph {
                    Text(glyph)
                        .font(.system(size: path == .jlpt ? 16 : 15, weight: .bold))
                        .foregroundStyle(Color.studyAccent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                } else {
                    Image(systemName: path.symbol)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Color.studyAccent)
                }
            }
            .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(path.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    if path == .practice {
                        Text("New")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.sakuraButton, in: Capsule())
                    }
                }
                Text(path.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(Color.card.opacity(0.92), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.sakuraPink.opacity(app.profile.glow == .off ? 0.22 : 0.55), lineWidth: 1)
        )
        .chromeGlow(Color.sakuraPink, level: app.profile.glow, radius: 10)
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

struct LearningPathScreen: View {
    let path: LearningPath
    var featuredClips: [Clip] = []

    @Environment(AppModel.self) private var app
    @State private var playing: Clip?
    @State private var playQueue: [Clip] = []
    @State private var playLine: Int?
    @State private var practiceClip: Clip?
    @State private var practiceCoordinator = PlaybackCoordinator()

    var body: some View {
        Group {
            switch path {
            case .jlpt:
                JLPTPathView()
            case .grammar:
                GrammarPathView()
            case .practice:
                practiceList
            default:
                ExploreView(
                    lockedCategories: categories,
                    lockedDifficulty: path == .jlpt ? .beginner : nil,
                    leadingClips: featuredClips,
                    onPlay: { clip, line, list in
                        playQueue = list
                        playLine = line
                        playing = clip
                    }
                )
            }
        }
        .background(Color.canvas.ignoresSafeArea())
        .navigationTitle(path.title)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $playing) { clip in
            ClipPlayerScreen(clip: clip, queue: playQueue, startLine: playLine, loopLine: playLine != nil)
                .environment(app)
        }
        .sheet(item: $practiceClip) { clip in
            ShadowingOverlay(clip: clip)
                .environment(practiceCoordinator)
                .environment(app)
        }
    }

    private var categories: Set<ClipCategory> {
        switch path {
        case .conversation: [.drama, .interview]
        case .listening: []
        case .culture: [.variety, .kids]
        case .jlpt: []
        default: []
        }
    }

    private var practiceList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                Text("Listen to a real line, then say it back. Compare the recognized words with the original.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(app.personalized(app.studyLibrary)) { clip in
                    Button {
                        Haptics.light()
                        practiceClip = clip
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(clip.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                Text("\(clip.lines.count) lines · \(clip.difficulty)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "mic.fill")
                                .foregroundStyle(Color.designOrange)
                        }
                        .padding(14)
                        .background(Color.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.cardStroke))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
        }
    }
}

private struct GrammarPathView: View {
    @Environment(AppModel.self) private var app
    @State private var playing: Clip?
    @State private var playLine: Int?

    private var clipQueue: [Clip] {
        var seen: Set<String> = []
        return moments.compactMap { moment in
            guard seen.insert(moment.clip.id).inserted else { return nil }
            return moment.clip
        }
    }

    private var moments: [(clip: Clip, line: Line, surface: String, gloss: String)] {
        let grammar: Set<String> = ["particle", "auxiliary", "copula", "conjunction", "expression", "grammar"]
        var rows: [(Clip, Line, String, String)] = []
        for clip in app.personalized(app.studyLibrary) {
            for line in clip.lines {
                guard let token = line.tokens.first(where: { grammar.contains($0.pos) && $0.tappable }) else { continue }
                let gloss = token.definitions.first ?? ""
                rows.append((clip, line, token.surface, gloss))
                if rows.count == 24 { return rows }
            }
        }
        return rows
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                Text("Grammar the way it shows up in a real line. Open the clip and hear it.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(Array(moments.enumerated()), id: \.offset) { _, moment in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(moment.surface)
                            .font(JojoFont.jp(22, bold: true, relativeTo: .title3))
                            .lineLimit(1)
                        if !moment.gloss.isEmpty {
                            Text(moment.gloss)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Text(moment.line.text)
                            .font(JojoFont.jp(16, relativeTo: .body))
                            .lineLimit(2)
                        Text(moment.line.translation)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.translationText)
                            .lineLimit(2)
                        Button {
                            SpeechService.shared.speak(moment.line.text)
                        } label: {
                            Label("Hear the line", systemImage: "speaker.wave.2")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.designOrange)
                        Button {
                            playLine = moment.clip.lines.firstIndex(where: { $0.start == moment.line.start })
                            playing = moment.clip
                        } label: {
                            Label("Open the clip", systemImage: "play.fill")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.designOrange)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Color.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.cardStroke))
                }
            }
            .padding(20)
        }
        .fullScreenCover(item: $playing) { clip in
            ClipPlayerScreen(clip: clip, queue: clipQueue, startLine: playLine)
                .environment(app)
        }
    }
}

private struct JLPTPathView: View {
    @Environment(AppModel.self) private var app
    @State private var level = "N5"
    @State private var didPickLevel = false
    @State private var playing: Clip?

    private let levels = ["N5", "N4", "N3", "N2", "N1"]

    private var clips: [Clip] {
        app.personalized(app.studyLibrary.filter { clip in
            clip.lines.contains { line in line.tokens.contains { $0.jlpt == level } }
        })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Clips containing vocabulary tagged at this JLPT level. Other words in the clip may be harder.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(levels, id: \.self) { item in
                            Button(item) { level = item }
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(level == item ? .white : .primary)
                                .padding(.horizontal, 14)
                                .frame(minHeight: 36)
                                .background {
                                    if level == item { Capsule().fill(Color.sakuraFill) }
                                    else { Capsule().fill(Color.card) }
                                }
                        }
                    }
                }
                ForEach(clips) { clip in
                    Button {
                        playing = clip
                    } label: {
                        HStack {
                            Text(clip.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 8)
                            Image(systemName: "play.fill")
                                .foregroundStyle(Color.designOrange)
                        }
                        .padding(14)
                        .background(Color.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                if clips.isEmpty {
                    Text("No \(level) lines in the library yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
        }
        .fullScreenCover(item: $playing) { clip in
            ClipPlayerScreen(clip: clip, queue: clips)
                .environment(app)
        }
        .onAppear {
            guard !didPickLevel else { return }
            didPickLevel = true
            level = app.suggestedJLPTLevel
        }
    }
}


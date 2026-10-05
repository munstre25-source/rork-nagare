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
    @State private var path = NavigationPath()
    @State private var dueKeys: [String] = []
    @State private var reviewSession: ReviewSessionConfig?
    @State private var playing: Clip?
    @State private var practiceClip: Clip?
    @State private var reviewDone = false
    @State private var watchDone = false
    @State private var speakDone = false
    @State private var speakCoordinator = PlaybackCoordinator()

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    StudySessionClock(running: scenePhase == .active)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if !app.profile.hideDailyGoalBar {
                        DailyGoalBar()
                    }
                    topBar
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Explore")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text("Dive into different ways to learn.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    exploreDoors
                    Text("Ways to study")
                        .font(.headline)
                    VStack(spacing: 12) {
                        ForEach(LearningPath.allCases) { path in
                            NavigationLink(value: path) {
                                LearningPathCard(path: path)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    todayPlan
                    captureRow
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .background(Color.studyPage.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: LearningPath.self) { path in
                LearningPathScreen(path: path, featuredClips: featuredClips)
            }
            .navigationDestination(for: SearchRoute.self) { _ in
                SearchView(embedded: true)
            }
            .navigationDestination(for: TopicHub.self) { _ in
                TopicStylesView()
            }
            .sheet(isPresented: $showGoal) {
                DailyGoalSheet()
            }
            .sheet(isPresented: $showCapture) {
                CaptureJapaneseView()
            }
            .fullScreenCover(item: $reviewSession, onDismiss: reloadPlan) { config in
                ReviewSessionView(config: config)
            }
            .fullScreenCover(item: $playing, onDismiss: reloadPlan) { clip in
                ClipPlayerScreen(clip: clip, queue: app.studyLibrary)
                    .environment(app)
            }
            .sheet(item: $practiceClip, onDismiss: reloadPlan) { clip in
                ShadowingOverlay(clip: clip)
                    .environment(speakCoordinator)
                    .environment(app)
            }
        }
        .onAppear { reloadPlan() }
        .onChange(of: scriptedPath) { _, newPath in
            guard let newPath else { return }
            path.append(newPath)
        }
        .environment(\.colorScheme, .light)
    }

    private var topBar: some View {
        ZStack {
            CenteredModeSwitch(forYouSelected: false, onForYou: onOpenFeed, onExplore: {})
            HStack(spacing: 0) {
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
    }

    private var exploreDoors: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            NavigationLink(value: SearchRoute.search) {
                ExploreDoorCard(title: "Search a word", subtitle: "Hear it in real clips", symbol: "magnifyingglass")
            }
            .buttonStyle(.plain)
            NavigationLink(value: LearningPath.jlpt) {
                ExploreDoorCard(title: "Difficulty levels", subtitle: "N5 through N1", symbol: "chart.bar.fill")
            }
            .buttonStyle(.plain)
            NavigationLink(value: LearningPath.grammar) {
                ExploreDoorCard(title: "Grammar patterns", subtitle: "Particles and forms in real lines", symbol: "text.book.closed")
            }
            .buttonStyle(.plain)
            NavigationLink(value: TopicHub.topics) {
                ExploreDoorCard(title: "Topics & styles", subtitle: "Conversation, culture, more", symbol: "square.grid.2x2")
            }
            .buttonStyle(.plain)
        }
    }

    private var suggestedClip: Clip? { app.recommendedClip(preferShort: true) }

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
                    DailyPlanProgress.mark(.review)
                    reviewDone = true
                    reviewSession = ReviewSessionConfig(title: "Today", keys: dueKeys)
                }
            }
            if let clip = suggestedClip {
                planRow(symbol: "play.fill", title: "Watch a clip", subtitle: clip.title, done: watchDone) {
                    DailyPlanProgress.mark(.watch)
                    watchDone = true
                    playing = clip
                }
                planRow(symbol: "mic.fill", title: "Say a line", subtitle: "Listen, then speak it back", done: speakDone) {
                    DailyPlanProgress.mark(.speak)
                    speakDone = true
                    practiceClip = clip
                }
            }
        }
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

nonisolated enum SearchRoute: Hashable, Sendable {
    case search
}

nonisolated enum TopicHub: Hashable, Sendable {
    case topics
}

private struct ExploreDoorCard: View {
    let title: String
    let subtitle: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.studyAccent)
                .frame(width: 36, height: 36)
                .background(Color.studyFocus, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.cardStroke))
    }
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
        .environment(\.colorScheme, .light)
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
        case .practice: "AI Practice"
        }
    }

    var subtitle: String {
        switch self {
        case .conversation: "Real-life dialogues & practical phrases"
        case .grammar: "Build your foundation"
        case .listening: "Hear native Japanese in context"
        case .culture: "Discover Japan’s traditions, life, and people"
        case .jlpt: "Get exam ready"
        case .practice: "Chat, speak and get personalized feedback"
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
                Text(path.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
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
        .background(path.tint, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
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
                Text("Listen to a line, say it back, and Jojo scores how close you were.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(app.studyLibrary) { clip in
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
        for clip in app.studyLibrary {
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
    @State private var playing: Clip?

    private let levels = ["N5", "N4", "N3", "N2", "N1"]

    private var clips: [Clip] {
        app.studyLibrary.filter { clip in
            clip.lines.contains { line in line.tokens.contains { $0.jlpt == level } }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Clips whose words sit at this level.")
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
    }
}


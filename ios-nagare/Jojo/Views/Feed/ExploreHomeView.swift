import SwiftUI

/// Explore tab: six learning lanes, matching the product design.
struct ExploreHomeView: View {
    var onOpenFeed: () -> Void = {}
    var tabBarHidden: Binding<Bool> = .constant(false)

    @Environment(AppModel.self) private var app
    @State private var showGoal: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
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
                    VStack(spacing: 12) {
                        ForEach(LearningPath.allCases) { path in
                            NavigationLink(value: path) {
                                LearningPathCard(path: path)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 96)
            }
            .scrollIndicators(.hidden)
            .tabBarAutoHide(tabBarHidden)
            .background(Color.canvas.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: LearningPath.self) { path in
                LearningPathScreen(path: path)
            }
            .navigationDestination(for: SearchRoute.self) { _ in
                SearchView(embedded: true)
            }
            .sheet(isPresented: $showGoal) {
                DailyGoalSheet()
                    .presentationDetents([.medium])
            }
        }
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
}

nonisolated enum SearchRoute: Hashable, Sendable {
    case search
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

    var tint: Color {
        switch self {
        case .conversation: Color.adaptive(light: "#E7F4FF", dark: "#1A2C40")
        case .grammar: Color.adaptive(light: "#FDE8EF", dark: "#3A2430")
        case .listening: Color.adaptive(light: "#E5F1FF", dark: "#1A2744")
        case .culture: Color.adaptive(light: "#F3E8FF", dark: "#2C2440")
        case .jlpt: Color.adaptive(light: "#E5F8EE", dark: "#1A3328")
        case .practice: Color.adaptive(light: "#FFF6E8", dark: "#3A3020")
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
                    .fill(Color.white.opacity(0.72))
                if let glyph = path.glyph {
                    Text(glyph)
                        .font(.system(size: path == .jlpt ? 16 : 15, weight: .bold))
                        .foregroundStyle(Color.designOrangeDeep)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                } else {
                    Image(systemName: path.symbol)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Color.designOrangeDeep)
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

    @Environment(AppModel.self) private var app
    @State private var playing: Clip?
    @State private var practiceClip: Clip?
    @State private var practiceCoordinator = PlaybackCoordinator()

    var body: some View {
        Group {
            switch path {
            case .grammar:
                GrammarPathView()
            case .practice:
                practiceList
            default:
                ExploreView(
                    lockedCategories: categories,
                    lockedDifficulty: path == .jlpt ? .beginner : nil,
                    onPlay: { clip, _ in playing = clip }
                )
            }
        }
        .background(Color.canvas.ignoresSafeArea())
        .navigationTitle(path.title)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $playing) { clip in
            ClipPlayerScreen(clip: clip)
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
                Text("Listen, then say the line back. Jojo plays the model so you can compare.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(app.clips) { clip in
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

    private var entries: [DictionaryEntry] {
        let grammar: Set<String> = ["particle", "auxiliary", "copula", "conjunction", "expression", "grammar", "suffix", "prefix"]
        return app.lexicon.entries.values
            .filter { grammar.contains($0.pos) }
            .sorted { $0.surface < $1.surface }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                Text("Particles and patterns from the dictionary. Tap the speaker to hear one.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 12)
                ForEach(Array(entries.enumerated()), id: \.element.surface) { index, entry in
                    GrammarRow(index: index + 1, entry: entry)
                    if index < entries.count - 1 {
                        Divider().padding(.leading, 56)
                    }
                }
            }
            .padding(20)
        }
    }
}

private struct GrammarRow: View {
    let index: Int
    let entry: DictionaryEntry

    var body: some View {
        HStack(spacing: 12) {
            Text("\(index)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Color.designOrange, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.surface)
                    .font(JojoFont.jp(20, bold: true, relativeTo: .title3))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(entry.romaji)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(entry.definitions.prefix(2).joined(separator: "; "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            if let jlpt = entry.jlpt {
                JLPTBadge(level: jlpt)
            }
            Button {
                SpeechService.shared.speak(entry.surface)
            } label: {
                Image(systemName: "speaker.wave.2")
                    .foregroundStyle(.primary)
                    .frame(width: 40, height: 40)
            }
            .accessibilityLabel("Play \(entry.surface)")
        }
        .padding(.vertical, 8)
    }
}

private struct DailyGoalSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Daily goal")
                    .font(.title2.weight(.bold))
                Spacer()
                Button("Done") { dismiss() }
                    .font(.body.weight(.semibold))
            }
            Text(app.isGoalReached ? "You hit today’s goal." : "\(app.minutesLeft) min left today")
                .font(.title3.weight(.semibold))
                .lineLimit(2)
            ProgressView(value: app.goalProgress)
                .tint(Color.designOrange)
            Text("\(app.profile.dailyGoalMinutes) minutes keeps the streak alive.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(24)
        .background(Color.canvas.ignoresSafeArea())
    }
}

import SwiftUI
import SwiftData

struct ReviewSessionConfig: Identifiable {
    let id = UUID()
    let title: String
    let keys: [String]
}

/// Flashcard session: tap-to-reveal front → definitions/context → Again / Good.
struct ReviewSessionView: View {
    let config: ReviewSessionConfig

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Query private var allWords: [SavedWord]
    @State private var queue: [String] = []
    @State private var total: Int = 0
    @State private var completed: Int = 0
    @State private var goodCount: Int = 0
    @State private var showAllDefs: Bool = false
    @State private var isFinished: Bool = false
    @State private var playing: Clip?
    @State private var revealed: Bool = false
    @State private var flipAngle: Double = 0
    @State private var showGoodPulse: Bool = false

    private var current: SavedWord? {
        guard let key = queue.first else { return nil }
        return allWords.first { $0.key == key }
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                topBar
                if isFinished {
                    ReviewCompleteView(reviewed: total, good: goodCount) { dismiss() }
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                } else if let word = current {
                    Group {
                        if revealed {
                            FittedFlashcard {
                                flipCard(for: word)
                                    .padding(.horizontal, Spacing.l)
                                    .padding(.vertical, Spacing.s)
                            }
                        } else {
                            flipCard(for: word)
                                .padding(.horizontal, Spacing.l)
                                .padding(.vertical, Spacing.s)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .id(word.key)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .animation(Motion.cardFlip, value: word.key)
                    if revealed {
                        answerButtons(for: word)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                } else {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            }

            if showGoodPulse {
                GoodCheckPulse()
                    .transition(.scale.combined(with: .opacity))
                    .zIndex(2)
                    .allowsHitTesting(false)
            }
        }
        .background(Color.canvas.ignoresSafeArea())
        .animation(Motion.cardFlip, value: revealed)
        .onAppear {
            guard queue.isEmpty, !isFinished else { return }
            queue = config.keys
            total = config.keys.count
            track("review_started", props: ["count": String(total)])
        }
        .onChange(of: queue.first) { _, _ in
            revealed = false
            flipAngle = 0
            showAllDefs = false
        }
        .fullScreenCover(item: $playing) { clip in
            ClipPlayerScreen(clip: clip, startLine: current?.contextLineIndex, loopLine: true)
        }
    }

    private var topBar: some View {
        HStack(spacing: Spacing.m) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .background(Color.fieldFill, in: Circle())
            }
            .accessibilityLabel("Close review")
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.1))
                    Capsule().fill(Color.jojoOrange)
                        .frame(width: proxy.size.width * (total == 0 ? 0 : Double(completed) / Double(total)))
                        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: completed)
                }
            }
            .frame(height: 6)
            Text("\(min(completed + (isFinished ? 0 : 1), total))/\(total)")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.s)
    }

    private func flipCard(for word: SavedWord) -> some View {
        ZStack {
            if flipAngle < 90 {
                frontFace(word)
                    .opacity(revealed ? 0 : 1)
            }
            if flipAngle > 90 {
                backFace(word)
                    .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
            }
        }
        .rotation3DEffect(.degrees(flipAngle), axis: (x: 0, y: 1, z: 0), perspective: 0.65)
        .onTapGesture {
            guard !revealed else { return }
            Haptics.light()
            withAnimation(Motion.cardFlip) {
                flipAngle = 180
                revealed = true
            }
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(revealed ? "Card revealed" : "Tap to reveal")
    }

    private func frontFace(_ word: SavedWord) -> some View {
        VStack(spacing: Spacing.m) {
            Spacer(minLength: 24)
            Text(word.contextSentence.isEmpty ? word.surface : word.contextSentence)
                .font(JojoFont.jp(word.contextSentence.isEmpty ? 44 : 28, bold: true, relativeTo: .largeTitle))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(4)
                .minimumScaleFactor(0.7)
            Text("Tap to flip")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.55))
            Spacer(minLength: 24)
        }
        .frame(maxWidth: .infinity, minHeight: 360)
        .padding(Spacing.l)
        .background(Color(hex: "#1C1C1E"), in: RoundedRectangle(cornerRadius: Radius.sheet, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sheet, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    private func backFace(_ word: SavedWord) -> some View {
        KikuFlashcardBack(word: word, onPlayClip: { playing = $0 })
    }

    private func answerButtons(for word: SavedWord) -> some View {
        HStack(spacing: Spacing.m) {
            Button {
                answer(word, good: false)
            } label: {
                AnswerLabel(title: "Again", interval: SRS.againLabel, symbol: "arrow.counterclockwise", fg: .againText, bg: .againBackground)
            }
            Button {
                answer(word, good: true)
            } label: {
                AnswerLabel(title: "Good", interval: SRS.label(SRS.goodInterval(fromStep: word.intervalStepIndex)), symbol: "checkmark", fg: .goodText, bg: .goodBackground)
            }
        }
        .buttonStyle(PressableStyle())
        .padding(.horizontal, Spacing.l)
        .padding(.top, Spacing.s)
        .padding(.bottom, Spacing.m)
        .background(Color.canvas)
    }

    private func answer(_ word: SavedWord, good: Bool) {
        good ? Haptics.medium() : Haptics.soft()
        app.answer(word, good: good)

        if good {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) { showGoodPulse = true }
            Task {
                try? await Task.sleep(for: .milliseconds(350))
                withAnimation(.easeOut(duration: 0.2)) { showGoodPulse = false }
                advance(good: true)
            }
        } else {
            advance(good: false)
        }
    }

    private func advance(good: Bool) {
        withAnimation(Motion.cardFlip) {
            showAllDefs = false
            revealed = false
            flipAngle = 0
            completed += 1
            if good { goodCount += 1 }
            queue.removeFirst()
            if queue.isEmpty {
                isFinished = true
                Haptics.success()
                track("review_completed", props: ["count": String(total), "good": String(goodCount)])
            }
        }
    }
}

/// Shrinks a flashcard so the word, context, and clip all stay above the rating buttons.
struct FittedFlashcard<Content: View>: View {
    @ViewBuilder var content: () -> Content
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let scale = contentHeight > 1 ? min(1, geo.size.height / contentHeight) : 1
            content()
                .frame(width: geo.size.width, alignment: .top)
                .fixedSize(horizontal: false, vertical: true)
                .background {
                    GeometryReader { inner in
                        Color.clear
                            .preference(key: FlashcardHeightKey.self, value: inner.size.height)
                    }
                }
                .scaleEffect(scale, anchor: .top)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                .onPreferenceChange(FlashcardHeightKey.self) { height in
                    guard height > 1, abs(height - contentHeight) > 0.5 else { return }
                    contentHeight = height
                }
        }
    }
}

private struct FlashcardHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// One Kiku-style review card: word, definitions, context, and a clip that stays fully on screen.
struct KikuFlashcardBack: View {
    let word: SavedWord
    var dark: Bool = false
    var onPlayClip: (Clip) -> Void

    @Environment(AppModel.self) private var app

    var body: some View {
        let defs = Array(word.displayDefinitions(mode: app.profile.dictionary).prefix(2))
        VStack(alignment: .leading, spacing: 12) {
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
            if !defs.isEmpty {
                Text("Definition")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.translationText)
                ForEach(Array(defs.enumerated()), id: \.offset) { index, def in
                    DefinitionRow(number: index + 1, tag: word.conjugationClass ?? word.pos, text: def, dark: dark)
                }
            }
            if !word.contextSentence.isEmpty {
                Text("Context")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.translationText)
                HighlightedSentence(
                    sentence: word.contextSentence,
                    target: word.contextSurface.isEmpty ? word.surface : word.contextSurface,
                    size: 18,
                    baseColor: dark ? .white : .primary
                )
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                if let clip = app.clip(id: word.contextClipId) {
                    Button {
                        onPlayClip(clip)
                    } label: {
                        ZStack {
                            ClipPosterView(clip: clip, showsSymbol: false)
                            Image(systemName: "play.fill")
                                .font(.title2.weight(.bold))
                                .foregroundStyle(.white)
                                .frame(width: 54, height: 54)
                                .background(.black.opacity(0.45), in: Circle())
                                .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 148)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Play the clip for \(word.surface)")
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.16), lineWidth: 1)
        )
    }
}

/// Revolving card motion between flashcards (Kiku-style).
private struct ReviewCardFlip: ViewModifier {
    var angle: Double

    func body(content: Content) -> some View {
        content
            .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.65)
    }
}

private struct GoodCheckPulse: View {
    @State private var scale: CGFloat = 0.4

    var body: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 72, weight: .bold))
            .foregroundStyle(Color.goodBackground)
            .scaleEffect(scale)
            .shadow(color: Color.goodBackground.opacity(0.45), radius: 24)
            .onAppear {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) { scale = 1.1 }
            }
    }
}

private struct AnswerLabel: View {
    let title: String
    let interval: String
    let symbol: String
    let fg: Color
    let bg: Color

    var body: some View {
        HStack(spacing: Spacing.m) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .bold))
                .frame(width: 32, height: 32)
                .background(fg.opacity(0.18), in: Circle())
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.title3.weight(.bold))
                Text(interval).font(.subheadline.weight(.medium)).opacity(0.85)
            }
        }
        .foregroundStyle(fg)
        .frame(maxWidth: .infinity, minHeight: 72)
        .background(bg, in: RoundedRectangle(cornerRadius: Radius.sheet, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), next review in \(interval)")
    }
}

private struct ReviewCompleteView: View {
    let reviewed: Int
    let good: Int
    let onDone: () -> Void
    @State private var appeared: Bool = false

    var body: some View {
        VStack(spacing: Spacing.l) {
            Spacer()
            ZStack {
                Circle().fill(Color.jojoOrangeSoft).frame(width: 170, height: 170)
                    .scaleEffect(appeared ? 1 : 0.4)
                JojoMascot(height: 180, pose: .cheer)
                    .scaleEffect(appeared ? 1 : 0.2)
                if appeared { ConfettiBurst(count: 22, radius: 110) }
            }
            Text("Session complete")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
            Text("\(reviewed) cards reviewed · \(good) remembered")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("流れに乗ってる! You're in the flow.")
                .font(JojoFont.jp(16, relativeTo: .body))
                .foregroundStyle(.secondary)
            Spacer()
            Button("Back to Vocab", action: onDone)
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, Spacing.l)
                .padding(.bottom, Spacing.l)
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.55)) { appeared = true }
        }
    }
}

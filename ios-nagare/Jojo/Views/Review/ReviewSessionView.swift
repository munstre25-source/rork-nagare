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
                    ScrollView {
                        flipCard(for: word)
                            .padding(Spacing.l)
                            .id(word.key)
                            .transition(.asymmetric(
                                insertion: .modifier(
                                    active: ReviewCardFlip(angle: -88),
                                    identity: ReviewCardFlip(angle: 0)
                                ).combined(with: .opacity),
                                removal: .modifier(
                                    active: ReviewCardFlip(angle: 88),
                                    identity: ReviewCardFlip(angle: 0)
                                ).combined(with: .opacity)
                            ))
                    }
                    .scrollIndicators(.hidden)
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
        let defs = word.displayDefinitions(mode: app.profile.dictionary)
        return VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(alignment: .firstTextBaseline) {
                Text(word.surface)
                    .font(JojoFont.jp(36, bold: true, relativeTo: .largeTitle))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Button {
                    SpeechService.shared.speak(word.contextSentence.isEmpty ? word.surface : word.contextSentence)
                } label: {
                    Image(systemName: "speaker.wave.2")
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 36, height: 36)
                }
                .accessibilityLabel("Play \(word.surface)")
            }
            if !word.romaji.isEmpty {
                Text(word.romaji)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.55))
            }
            if let gloss = defs.first {
                Text(gloss)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            if !word.contextSentence.isEmpty {
                Text("Context")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.45))
                HighlightedSentence(
                    sentence: word.contextSentence,
                    target: word.contextSurface.isEmpty ? word.surface : word.contextSurface,
                    size: 18,
                    baseColor: .white
                )
                if let clip = app.clip(id: word.contextClipId), let line = clip.lines[safe: word.contextLineIndex] {
                    Text(line.translation)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                    ClipThumbnailButton(clip: clip, emphasizesPlay: true) { playing = clip }
                }
            }
        }
        .padding(Spacing.l)
        .frame(maxWidth: .infinity, minHeight: 360, alignment: .topLeading)
        .background(Color(hex: "#1C1C1E"), in: RoundedRectangle(cornerRadius: Radius.sheet, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.sheet, style: .continuous).strokeBorder(Color.white.opacity(0.12)))
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
        .padding(.bottom, Spacing.s)
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

import SwiftUI
import SwiftData

struct ReviewSessionConfig: Identifiable {
    let id = UUID()
    let title: String
    let keys: [String]
}

/// Flashcard session: word card → definitions → context + clip → Again / Good.
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
    @State private var cardOffset: CGFloat = 0

    private var current: SavedWord? {
        guard let key = queue.first else { return nil }
        return allWords.first { $0.key == key }
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            if isFinished {
                ReviewCompleteView(reviewed: total, good: goodCount) { dismiss() }
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            } else if let word = current {
                ScrollView {
                    card(for: word)
                        .padding(Spacing.l)
                        .id(word.key)
                        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
                }
                .scrollIndicators(.hidden)
                answerButtons(for: word)
            } else {
                Spacer()
                ProgressView()
                Spacer()
            }
        }
        .background(Color.canvas.ignoresSafeArea())
        .onAppear {
            guard queue.isEmpty, !isFinished else { return }
            queue = config.keys
            total = config.keys.count
            track("review_started", props: ["count": String(total)])
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

    private func card(for word: SavedWord) -> some View {
        let defs = word.displayDefinitions(mode: app.profile.dictionary)
        return VStack(alignment: .leading, spacing: Spacing.l) {
            WordHeaderCard(
                surface: word.surface,
                readings: word.readings,
                romaji: word.romaji,
                pos: word.pos,
                conjugationClass: word.conjugationClass,
                jlpt: word.jlpt,
                showFurigana: app.profile.showFurigana,
                showRomaji: app.profile.showRomaji
            )
            SectionTitle("Definition")
            VStack(spacing: Spacing.s) {
                let visible = showAllDefs ? defs : Array(defs.prefix(2))
                ForEach(Array(visible.enumerated()), id: \.offset) { index, def in
                    DefinitionRow(number: index + 1, tag: word.conjugationClass ?? word.pos, text: def)
                }
                if defs.count > 2, !showAllDefs {
                    Button {
                        withAnimation(.snappy) { showAllDefs = true }
                    } label: {
                        HStack {
                            Label("\(defs.count - 2) more", systemImage: "plus")
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.tappableBlue)
                        .padding(Spacing.m)
                        .frame(minHeight: 48)
                        .background(Color.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
            }
            if !word.contextSentence.isEmpty {
                SectionTitle("Context")
                HighlightedSentence(sentence: word.contextSentence, target: word.contextSurface.isEmpty ? word.surface : word.contextSurface, size: 19)
                    .padding(Spacing.l)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.card, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Color.cardStroke))
                if let clip = app.clip(id: word.contextClipId) {
                    ClipThumbnailButton(clip: clip) { playing = clip }
                }
            }
        }
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
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            showAllDefs = false
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
                JojoMascot(height: 180)
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

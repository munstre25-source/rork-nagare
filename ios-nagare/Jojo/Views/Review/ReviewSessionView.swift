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
        .background { ReviewStageBackground() }
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
        VStack(spacing: 10) {
            ZStack {
                ReviewWordmark()
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(FlashcardInk.ink)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Close review")
                    Spacer()
                }
            }
            HStack(spacing: 10) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(FlashcardInk.ink.opacity(0.14))
                        Capsule().fill(Color.sakuraButton)
                            .frame(width: proxy.size.width * (total == 0 ? 0 : Double(completed) / Double(total)))
                            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: completed)
                    }
                }
                .frame(height: 8)
                Text("\(min(completed + (isFinished ? 0 : 1), total))/\(total)")
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(FlashcardInk.muted)
                    .contentTransition(.numericText())
            }
        }
        .padding(.horizontal, Spacing.l)
        .padding(.top, Spacing.s)
        .padding(.bottom, 4)
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
        FlashcardHero(
            surface: word.surface,
            reading: app.profile.showFurigana ? word.primaryReading : "",
            romaji: app.profile.showRomaji ? word.romaji : "",
            pos: word.pos,
            jlpt: word.jlpt,
            hint: "Tap to reveal"
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func backFace(_ word: SavedWord) -> some View {
        KikuFlashcardBack(word: word, onPlayClip: { playing = $0 })
    }

    private func answerButtons(for word: SavedWord) -> some View {
        let next = SRS.goodInterval(fromStep: word.intervalStepIndex)
        return VStack(spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    answer(word, good: false)
                } label: {
                    ReviewGradeButton(title: "Again", interval: SRS.againLabel, good: false)
                }
                Button {
                    answer(word, good: true)
                } label: {
                    ReviewGradeButton(title: "Good", interval: SRS.label(next), good: true)
                }
            }
            .buttonStyle(PressableStyle())
            ReviewUntilFooter(text: SRS.untilReview(next))
        }
        .padding(.horizontal, Spacing.l)
        .padding(.top, Spacing.s)
        .padding(.bottom, Spacing.m)
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

/// One review card: the word plate, definitions, and the sentence it came from.
struct KikuFlashcardBack: View {
    let word: SavedWord
    /// Onboarding practice speaks the line. Review opens the clip.
    var playsClip: Bool = true
    var onPlayClip: (Clip) -> Void

    @Environment(AppModel.self) private var app

    var body: some View {
        let defs = Array(word.displayDefinitions(mode: app.profile.dictionary).prefix(2))
        let clip = app.clip(id: word.contextClipId)
        let line = clip?.lines[safe: word.contextLineIndex]
        VStack(alignment: .leading, spacing: 16) {
            FlashcardHero(
                surface: word.surface,
                reading: app.profile.showFurigana ? word.primaryReading : "",
                romaji: app.profile.showRomaji ? word.romaji : "",
                pos: word.pos,
                jlpt: word.jlpt
            )
            if !defs.isEmpty {
                FlashcardSectionTitle(title: "Definition", systemImage: "book.closed.fill")
                ForEach(Array(defs.enumerated()), id: \.offset) { index, def in
                    FlashcardDefinitionRow(number: index + 1, tag: word.pos, text: def)
                }
            }
            if !word.contextSentence.isEmpty {
                FlashcardSectionTitle(title: "Context", systemImage: "text.bubble.fill")
                contextCard(clip: clip, translation: line?.translation)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func contextCard(clip: Clip?, translation: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                HighlightedSentence(
                    sentence: word.contextSentence,
                    target: word.contextSurface.isEmpty ? word.surface : word.contextSurface,
                    size: 22,
                    baseColor: FlashcardInk.ink
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    if playsClip, let clip {
                        onPlayClip(clip)
                    } else {
                        SpeechService.shared.speak(word.contextSentence)
                    }
                } label: {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.sakuraPink)
                        .frame(width: 36, height: 36)
                }
                .accessibilityLabel("Play this line")
            }
            if let translation, !translation.isEmpty {
                Text(translation)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(FlashcardInk.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FlashcardInk.row, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.sakuraPink.opacity(0.45), lineWidth: 1)
        )
        .overlay(alignment: .bottomTrailing) {
            HStack(spacing: -4) {
                Blossom(size: 22, color: Color.sakuraPinkLight)
                Blossom(size: 14, color: Color.sakuraPink)
            }
            .padding(8)
            .allowsHitTesting(false)
        }
    }
}

/// Night or cream stage behind a review session. Sakura uses the temple scene; purple and orange use their own glow.
struct ReviewStageBackground: View {
    var body: some View {
        ZStack {
            FlashcardInk.page
            if JojoPalette.scheme == .dark, JojoPalette.theme == .sakura {
                JojoBrandBackground(scene: .templeDusk, showsHills: false, showsPetals: true)
                    .opacity(0.72)
            } else {
                RadialGradient(
                    colors: [Color.sakuraPink.opacity(JojoPalette.scheme == .dark ? 0.38 : 0.22), .clear],
                    center: .init(x: 0.9, y: 0.08),
                    startRadius: 8,
                    endRadius: 380
                )
                RadialGradient(
                    colors: [Color.sakuraPinkLight.opacity(0.55), .clear],
                    center: .init(x: 0.05, y: 0.85),
                    startRadius: 8,
                    endRadius: 280
                )
                BrandPetalField(
                    tint: Color.sakuraPinkLight,
                    density: JojoPalette.scheme == .dark ? .lush : .sparse
                )
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// JOJO wordmark with the accent blossom. Review sits behind the subscription, so it carries PRO.
struct ReviewWordmark: View {
    var body: some View {
        HStack(spacing: 5) {
            Text("JOJO")
                .font(.system(size: 22, weight: .heavy, design: .rounded))
            Blossom(size: 16, color: Color.sakuraPink)
            Text("PRO")
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .tracking(0.6)
        }
        .foregroundStyle(Color.sakuraPink)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Jojo Pro")
    }
}

/// The glowing word plate: reading, kanji, romaji, part of speech, level, and Jojo.
struct FlashcardHero: View {
    let surface: String
    let reading: String
    let romaji: String
    let pos: String
    let jlpt: String?
    var hint: String? = nil

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 8) {
                HStack {
                    readingPill
                    Spacer(minLength: 0)
                    Blossom(size: 18, color: Color.sakuraPink)
                        .opacity(0.9)
                }
                Text(surface)
                    .font(JojoFont.jp(56, bold: true, relativeTo: .largeTitle))
                    .foregroundStyle(FlashcardInk.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .frame(maxWidth: .infinity)
                if !romaji.isEmpty {
                    Text(romaji.uppercased())
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .tracking(2)
                        .foregroundStyle(FlashcardInk.ink.opacity(0.92))
                }
                if let hint {
                    Text(hint)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(FlashcardInk.muted)
                        .padding(.top, 4)
                } else {
                    HStack(spacing: 8) {
                        if !pos.isEmpty {
                            Text(pos)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(FlashcardInk.posInk)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 5)
                                .background(FlashcardInk.posFill, in: Capsule())
                        }
                        if let jlpt, !jlpt.isEmpty {
                            Text(jlpt)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Color.jlptPillText)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 5)
                                .background(Color.jlptPill, in: Capsule())
                        }
                    }
                    .padding(.top, 2)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .padding(.trailing, 64)

            JojoMascot(height: 112, floats: false, pose: .peek)
                .offset(x: 6, y: 18)
                .allowsHitTesting(false)
        }
        .background(FlashcardInk.plate, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(Color.sakuraPink.opacity(0.9), lineWidth: 1.5)
        )
        .shadow(color: Color.sakuraPink.opacity(0.45), radius: 16, y: 4)
    }

    private var readingPill: some View {
        Button {
            SpeechService.shared.speak(surface)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 13, weight: .bold))
                if !reading.isEmpty {
                    Text(reading)
                        .font(JojoFont.jp(16, relativeTo: .body))
                }
                Image(systemName: "waveform")
                    .font(.system(size: 12, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(minHeight: 34)
            .background(Color.sakuraButton, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Play pronunciation")
    }
}

private struct FlashcardSectionTitle: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.bold))
            Text(title)
                .font(.subheadline.weight(.bold))
            Rectangle()
                .fill(Color.sakuraPink.opacity(0.35))
                .frame(height: 1)
        }
        .foregroundStyle(Color.sakuraPink)
    }
}

private struct FlashcardDefinitionRow: View {
    let number: Int
    let tag: String
    let text: String

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text("\(number)")
                .font(.footnote.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Color.sakuraButton, in: Circle())
            if !tag.isEmpty {
                Text(tag)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(FlashcardInk.posInk)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(FlashcardInk.posFill, in: Capsule())
            }
            Text(text)
                .font(.body.weight(.semibold))
                .foregroundStyle(FlashcardInk.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(FlashcardInk.row, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.sakuraPink.opacity(0.28), lineWidth: 1)
        )
    }
}

/// Again is the pale accent. Good is the solid accent ramp. Both follow sakura, purple, or orange.
struct ReviewGradeButton: View {
    let title: String
    let interval: String
    var good: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: good ? "face.smiling" : "face.frowning")
                .font(.system(size: 26, weight: .medium))
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.title3.weight(.bold))
                Text(interval)
                    .font(.subheadline.weight(.semibold))
                    .opacity(0.85)
            }
        }
        .foregroundStyle(good ? Color.white : FlashcardInk.againInk)
        .frame(maxWidth: .infinity, minHeight: 72)
        .background {
            if good {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(LinearGradient(colors: [FlashcardInk.goodA, FlashcardInk.goodB], startPoint: .leading, endPoint: .trailing))
            } else {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(FlashcardInk.againFill)
            }
        }
        .shadow(color: good ? FlashcardInk.goodA.opacity(0.35) : .clear, radius: 10, y: 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), next review in \(interval)")
    }
}

struct ReviewUntilFooter: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Blossom(size: 12, color: Color.sakuraPink)
            Capsule().fill(FlashcardInk.muted.opacity(0.45)).frame(width: 28, height: 1)
            Image(systemName: "clock")
                .font(.caption.weight(.semibold))
            Text(text)
                .font(.caption.weight(.semibold))
            Capsule().fill(FlashcardInk.muted.opacity(0.45)).frame(width: 28, height: 1)
            Blossom(size: 12, color: Color.sakuraPink)
        }
        .foregroundStyle(FlashcardInk.muted)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
    }
}

/// Colors for the review card. Each accent has a cream version and a night version.
enum FlashcardInk {
    static let page = JojoPalette.color(
        sakuraLight: "#FFF6EE", sakuraDark: "#07060E",
        plumLight: "#F7F2FA", plumDark: "#0C0814",
        orangeLight: "#FFF8F2", orangeDark: "#100C08"
    )
    static let plate = JojoPalette.color(
        sakuraLight: "#FFFFFF", sakuraDark: "#1A1022",
        plumLight: "#FFFFFF", plumDark: "#161222",
        orangeLight: "#FFFFFF", orangeDark: "#1C140E"
    )
    static let row = JojoPalette.color(
        sakuraLight: "#FFF0F6", sakuraDark: "#2A1A32",
        plumLight: "#F4EEF7", plumDark: "#241C32",
        orangeLight: "#FFF4E8", orangeDark: "#2A1C12"
    )
    static let ink = JojoPalette.color(
        sakuraLight: "#1C1C1E", sakuraDark: "#FFFFFF",
        plumLight: "#1C1C1E", plumDark: "#FFFFFF",
        orangeLight: "#1C1C1E", orangeDark: "#FFFFFF"
    )
    static let muted = JojoPalette.color(
        sakuraLight: "#6B5E66", sakuraDark: "#C7C7CC",
        plumLight: "#655C6B", plumDark: "#C7C7CC",
        orangeLight: "#6B5E52", orangeDark: "#C7C7CC"
    )
    static let againFill = JojoPalette.color(
        sakuraLight: "#F8D0E4", sakuraDark: "#F7C6DE",
        plumLight: "#E3D2E8", plumDark: "#E4D0EE",
        orangeLight: "#F8E0C4", orangeDark: "#F6D4AE"
    )
    static let againInk = JojoPalette.color(
        sakuraLight: "#C2186A", sakuraDark: "#A01458",
        plumLight: "#5C3A72", plumDark: "#4A2C60",
        orangeLight: "#C45C00", orangeDark: "#8A3E00"
    )
    static let goodA = JojoPalette.color(
        sakuraLight: "#E21888", sakuraDark: "#FF4FA3",
        plumLight: "#9A62B0", plumDark: "#C084DC",
        orangeLight: "#E07A12", orangeDark: "#FFB020"
    )
    static let goodB = JojoPalette.color(
        sakuraLight: "#9B3DFF", sakuraDark: "#B44DFF",
        plumLight: "#5C3A72", plumDark: "#7A4684",
        orangeLight: "#C45C00", orangeDark: "#D35400"
    )
    static let posFill = JojoPalette.color(
        sakuraLight: "#F3D0E6", sakuraDark: "#5C2A6A",
        plumLight: "#E3D2E8", plumDark: "#5C3A72",
        orangeLight: "#F8E0C4", orangeDark: "#6B3A12"
    )
    static let posInk = JojoPalette.color(
        sakuraLight: "#7A2460", sakuraDark: "#F6D6EA",
        plumLight: "#5C3A72", plumDark: "#F3E6FA",
        orangeLight: "#8A3E00", orangeDark: "#FFE0B8"
    )
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

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
                    .transition(.asymmetric(
                        insertion: .modifier(
                            active: ReviewCardDeal(degrees: 26, offsetY: 46, scale: 0.94, opacity: 0),
                            identity: ReviewCardDeal(degrees: 0, offsetY: 0, scale: 1, opacity: 1)
                        ),
                        removal: .modifier(
                            active: ReviewCardDeal(degrees: -20, offsetY: -40, scale: 0.92, opacity: 0),
                            identity: ReviewCardDeal(degrees: 0, offsetY: 0, scale: 1, opacity: 1)
                        )
                    ))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .modifier(CardTurnModifier(angle: flipAngle))
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
        var reset = Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) {
            showAllDefs = false
            revealed = false
            flipAngle = 0
        }
        withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
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
            if playsClip, let clip {
                ClipThumbnailButton(clip: clip, emphasizesPlay: true) {
                    onPlayClip(clip)
                }
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

/// JOJO wordmark with the accent blossom.
struct ReviewWordmark: View {
    var body: some View {
        HStack(spacing: 5) {
            Text("JOJO")
                .font(.system(size: 22, weight: .heavy, design: .rounded))
            Blossom(size: 16, color: Color.sakuraPink)
        }
        .foregroundStyle(Color.sakuraPink)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Jojo")
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

/// Again is the pale accent. Good is the solid accent ramp. Both follow sakura, lavender, or orange.
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
                    .fill(FlashcardInk.goodA)
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

/// Colors for the review card. Sakura, Lavender, and Orange each have a white-page set and a night set.
enum FlashcardInk {
    static var page: Color { JojoPalette.color(
        sakuraLight: "#FFFFFF", sakuraDark: "#07060E",
        plumLight: "#FFFFFF", plumDark: "#0C0814",
        orangeLight: "#FFFFFF", orangeDark: "#100C08"
    ) }
    static var plate: Color { JojoPalette.color(
        sakuraLight: "#FFFFFF", sakuraDark: "#1A1022",
        plumLight: "#FFFFFF", plumDark: "#161222",
        orangeLight: "#FFFFFF", orangeDark: "#1C140E"
    ) }
    static var row: Color { JojoPalette.color(
        sakuraLight: "#FFF0F6", sakuraDark: "#2A1A32",
        plumLight: "#F4EEF7", plumDark: "#241C32",
        orangeLight: "#FFF4E8", orangeDark: "#2A1C12"
    ) }
    /// Word and definition type. Near-black on the white page for every accent.
    static var ink: Color { JojoPalette.color(
        sakuraLight: "#1C1C1E", sakuraDark: "#FFFFFF",
        plumLight: "#1C1C1E", plumDark: "#FFFFFF",
        orangeLight: "#1C1C1E", orangeDark: "#FFFFFF"
    ) }
    static var muted: Color { JojoPalette.color(
        sakuraLight: "#6B5E66", sakuraDark: "#C7C7CC",
        plumLight: "#655C6B", plumDark: "#C7C7CC",
        orangeLight: "#6B5E52", orangeDark: "#C7C7CC"
    ) }
    static var againFill: Color { JojoPalette.color(
        sakuraLight: "#F8D0E4", sakuraDark: "#F7C6DE",
        plumLight: "#E3D2E8", plumDark: "#E4D0EE",
        orangeLight: "#F8E0C4", orangeDark: "#F6D4AE"
    ) }
    static var againInk: Color { JojoPalette.color(
        sakuraLight: "#C2186A", sakuraDark: "#A01458",
        plumLight: "#5C3A72", plumDark: "#4A2C60",
        orangeLight: "#C45C00", orangeDark: "#8A3E00"
    ) }
    static var goodA: Color { JojoPalette.color(
        sakuraLight: "#FF4D8D", sakuraDark: "#FF4D8D",
        plumLight: "#8B5CF6", plumDark: "#8B5CF6",
        orangeLight: "#FF7A00", orangeDark: "#FF7A00"
    ) }
    static var goodB: Color { JojoPalette.color(
        sakuraLight: "#FF7EB8", sakuraDark: "#FF7EB8",
        plumLight: "#A78BFA", plumDark: "#C4B5FD",
        orangeLight: "#FF9A3C", orangeDark: "#FFB020"
    ) }
    static var posFill: Color { JojoPalette.color(
        sakuraLight: "#F3D0E6", sakuraDark: "#5C2A6A",
        plumLight: "#E3D2E8", plumDark: "#5C3A72",
        orangeLight: "#F8E0C4", orangeDark: "#6B3A12"
    ) }
    static var posInk: Color { JojoPalette.color(
        sakuraLight: "#7A2460", sakuraDark: "#F6D6EA",
        plumLight: "#5C3A72", plumDark: "#F3E6FA",
        orangeLight: "#8A3E00", orangeDark: "#FFE0B8"
    ) }
}

/// A card turn that lifts at the midpoint, so the reveal reads as a flip rather than a flat spin.
struct CardTurnModifier: ViewModifier, Animatable {
    var angle: Double

    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    func body(content: Content) -> some View {
        let turn = sin(angle * .pi / 180)
        content
            .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.52)
            .rotation3DEffect(.degrees(-7 * turn), axis: (x: 1, y: 0, z: 0), perspective: 0.8)
            .scaleEffect(1 - 0.045 * turn)
            .shadow(color: Color.sakuraPink.opacity(0.18 + 0.32 * turn), radius: 10 + 18 * turn, y: 6 + 8 * turn)
    }
}

/// The next card is dealt in; the answered card lifts away. Neither one un-flips.
struct ReviewCardDeal: ViewModifier, Animatable {
    var degrees: Double
    var offsetY: CGFloat
    var scale: CGFloat
    var opacity: Double

    var animatableData: AnimatablePair<AnimatablePair<Double, CGFloat>, AnimatablePair<CGFloat, Double>> {
        get { AnimatablePair(AnimatablePair(degrees, offsetY), AnimatablePair(scale, opacity)) }
        set {
            degrees = newValue.first.first
            offsetY = newValue.first.second
            scale = newValue.second.first
            opacity = newValue.second.second
        }
    }

    func body(content: Content) -> some View {
        content
            .rotation3DEffect(.degrees(degrees), axis: (x: 0, y: 1, z: 0), perspective: 0.7)
            .scaleEffect(scale)
            .offset(y: offsetY)
            .opacity(opacity)
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

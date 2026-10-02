import SwiftUI

/// Splash / welcome lockup: mascot above the wordmark with a brush stroke between them.
struct JojoLogo: View {
    var drawProgress: CGFloat = 1
    var size: CGFloat = 1
    var showsMascot: Bool = true
    var pose: MascotPose = .book
    var light: Bool = false

    var body: some View {
        VStack(spacing: 12 * size) {
            if showsMascot {
                JojoMascot(height: 200 * size, pose: pose)
            }
            JojoWordmark(size: 46 * size)
            FlowStroke()
                .trim(from: 0, to: drawProgress)
                .stroke(
                    LinearGradient(colors: [Color.jojoOrangeLight, .jojoVermilion], startPoint: .leading, endPoint: .trailing),
                    style: StrokeStyle(lineWidth: 6 * size, lineCap: .round, lineJoin: .round)
                )
                .frame(width: 150 * size, height: 22 * size)
            Text("日本語、流れるように")
                .font(JojoFont.jp(13 * size, relativeTo: .caption))
                .foregroundStyle(light ? Color.white.opacity(0.7) : Color.jojoInkSoft)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Jojo")
    }
}

/// A single flowing wave, like a stream.
struct FlowStroke: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let h = rect.height
        let w = rect.width
        path.move(to: CGPoint(x: 0, y: h * 0.7))
        path.addCurve(to: CGPoint(x: w * 0.5, y: h * 0.45), control1: CGPoint(x: w * 0.15, y: h * 0.05), control2: CGPoint(x: w * 0.32, y: h * 0.1))
        path.addCurve(to: CGPoint(x: w, y: h * 0.3), control1: CGPoint(x: w * 0.68, y: h * 0.8), control2: CGPoint(x: w * 0.85, y: h * 0.95))
        return path
    }
}

/// Hand-drawn underline swash for accent words in onboarding headlines.
struct AccentUnderline: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let y = rect.midY
        path.move(to: CGPoint(x: 0, y: y + 2))
        path.addCurve(
            to: CGPoint(x: rect.width, y: y - 1),
            control1: CGPoint(x: rect.width * 0.3, y: y + 6),
            control2: CGPoint(x: rect.width * 0.7, y: y - 5)
        )
        return path
    }
}

/// Large title + subtitle used on every question screen. Optional `accent` word paints pink with a swash.
struct OnboardingTitle: View {
    let title: String
    var subtitle: String?
    /// Substring of `title` to paint in sakura pink with an animated underline.
    var accent: String? = nil

    @Environment(\.brandSurface) private var surface
    @State private var underlineProgress: CGFloat = 0

    var body: some View {
        let palette = BrandPalette.resolve(surface)
        VStack(alignment: .leading, spacing: Spacing.s) {
            titleText(palette: palette)
            if let subtitle {
                Text(subtitle)
                    .font(.body)
                    .foregroundStyle(palette.subtle)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            withAnimation(.easeOut(duration: 0.55).delay(0.15)) { underlineProgress = 1 }
        }
        .onChange(of: title) { _, _ in
            underlineProgress = 0
            withAnimation(.easeOut(duration: 0.55).delay(0.1)) { underlineProgress = 1 }
        }
    }

    @ViewBuilder
    private func titleText(palette: BrandPalette) -> some View {
        if let accent, !accent.isEmpty, let range = title.range(of: accent) {
            let before = String(title[..<range.lowerBound])
            let mid = String(title[range])
            let after = String(title[range.upperBound...])
            (
                Text(before)
                    .foregroundStyle(palette.title)
                + Text(mid)
                    .foregroundStyle(Color.sakuraPink)
                + Text(after)
                    .foregroundStyle(palette.title)
            )
            .font(.system(.largeTitle, design: .rounded, weight: .bold))
            .fixedSize(horizontal: false, vertical: true)
            .overlay(alignment: .bottomLeading) {
                // Approximate underline under the accent word by measuring relative position.
                GeometryReader { geo in
                    let full = CGFloat(title.count)
                    let start = CGFloat(title.distance(from: title.startIndex, to: range.lowerBound)) / max(full, 1)
                    let width = CGFloat(accent.count) / max(full, 1)
                    AccentUnderline()
                        .trim(from: 0, to: underlineProgress)
                        .stroke(Color.sakuraPink, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                        .frame(width: geo.size.width * width * 1.05, height: 10)
                        .offset(x: geo.size.width * start * 0.92, y: 4)
                }
                .frame(height: 12)
                .allowsHitTesting(false)
            }
        } else {
            Text(title)
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .foregroundStyle(palette.title)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Non-interactive three-tier sentence (furigana / word / romaji).
struct StaticSentence: View {
    struct Word: Hashable {
        let surface: String
        var furigana: String?
        var romaji: String?
        var state: TokenVisualState = .normal
        var tappable: Bool = true
    }

    let words: [Word]
    var size: CGFloat = 24
    var showsUnderline: Bool = true
    /// Illustrations that mimic the in-app video chrome stay on the cinema surface.
    var surface: BrandSurface = .cinema
    /// Supply this to let the learner actually tap a word (value-prop demo).
    var onTapWord: ((Int) -> Void)?

    var body: some View {
        FlowLayout(spacing: 4, lineSpacing: 10) {
            ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                if let onTapWord, word.tappable {
                    Button { onTapWord(index) } label: { wordStack(word) }
                        .buttonStyle(PressableStyle())
                } else {
                    wordStack(word)
                }
            }
        }
    }

    private func wordStack(_ word: Word) -> some View {
        let palette = BrandPalette.resolve(surface)
        return VStack(spacing: 2) {
            Text(word.furigana ?? " ")
                .font(JojoFont.jp(size * 0.45, relativeTo: .caption2))
                .foregroundStyle(word.state == .selected ? Color.jojoOrange : palette.subtle)
            Text(word.surface)
                .font(JojoFont.jp(size, bold: true, relativeTo: .title2))
                .foregroundStyle(word.state == .selected ? Color.white : palette.title)
                .padding(.horizontal, 5)
                .background {
                    switch word.state {
                    case .selected:
                        RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.jojoOrange)
                    case .spoken:
                        RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.spokenGreen, lineWidth: 2)
                    case .normal:
                        Color.clear
                    }
                }
                .overlay(alignment: .bottom) {
                    if showsUnderline, word.tappable, word.state != .selected {
                        Capsule().fill(Color.tappableBlue).frame(height: 3).padding(.horizontal, 4).offset(y: 3)
                    }
                }
            if let romaji = word.romaji {
                Text(romaji)
                    .font(.system(size: size * 0.45))
                    .foregroundStyle(word.state == .selected ? Color.jojoOrange : palette.faint)
            }
        }
        .fixedSize()
    }
}

/// Selectable large card for single/multi-select questions. Frosted on night, paper on cream.
struct OptionCard: View {
    let title: String
    var subtitle: String?
    var symbol: String?
    let isSelected: Bool

    @Environment(\.brandSurface) private var surface

    private var isNight: Bool { surface == .night || surface == .cinema }

    var body: some View {
        HStack(spacing: Spacing.m) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(isSelected ? .white : (isNight ? Color.sakuraPink : Color.jojoVermilion))
                    .frame(width: 44, height: 44)
                    .background(
                        isSelected ? Color.white.opacity(0.22) : (isNight ? Color.white.opacity(0.1) : Color.jojoOrange.opacity(0.1)),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(isSelected ? .white : (isNight ? .white : Color.jojoInk))
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(isSelected ? Color.white.opacity(0.85) : (isNight ? Color.white.opacity(0.65) : Color.jojoInkSoft))
                }
            }
            Spacer(minLength: 0)
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isSelected ? .white : (isNight ? Color.white.opacity(0.35) : Color.jojoInkFaint.opacity(0.5)))
        }
        .padding(Spacing.l)
        .frame(minHeight: 72)
        .background {
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(
                    isSelected
                    ? AnyShapeStyle(LinearGradient(colors: [Color.jojoOrange, Color.jojoVermilion], startPoint: .topLeading, endPoint: .bottomTrailing))
                    : AnyShapeStyle(isNight ? Color.white.opacity(0.1) : Color.jojoPaper)
                )
                .background {
                    if isNight, !isSelected {
                        RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                            .fill(.ultraThinMaterial)
                    }
                }
        }
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(isSelected ? .clear : (isNight ? Color.white.opacity(0.12) : Color.jojoPaperStroke), lineWidth: 1)
        )
        .shadow(color: Color.jojoVermilion.opacity(isSelected ? 0.22 : (isNight ? 0 : 0.06)), radius: isSelected ? 14 : 10, y: 5)
        .contentShape(Rectangle())
        .animation(.snappy, value: isSelected)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Frozen tap-to-understand card (value-prop illustration). Mirrors the real in-app
/// popup, which floats over video — so it stays dark even on the cream canvas.
struct MockPopupCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: Spacing.s) {
                        Text("天気").font(JojoFont.jp(36, bold: true)).foregroundStyle(.white)
                        Image(systemName: "speaker.wave.2").foregroundStyle(.white.opacity(0.8))
                    }
                    Text("てんき").font(JojoFont.jp(14)).foregroundStyle(.white.opacity(0.85))
                    Text("tenki").font(.subheadline).foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
                OccurrenceBadge(count: 1, size: 36)
            }
            HStack(spacing: 6) {
                PillView(text: "noun", style: .neutralDark)
                PillView(text: "N5", style: .jlpt)
            }
            DefinitionRow(number: 1, tag: "noun", text: "weather; the elements", dark: true)
        }
        .padding(Spacing.l)
        .background(Color(hex: "#1C1C1E"), in: RoundedRectangle(cornerRadius: Radius.sheet, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.sheet, style: .continuous).strokeBorder(Color.white.opacity(0.08)))
        .shadow(color: .black.opacity(0.25), radius: 20, y: 10)
    }
}

/// Mini review card (value-prop illustration).
struct MockReviewCard: View {
    let clip: Clip?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack {
                Spacer()
                Text("食べる").font(JojoFont.jp(34, bold: true)).foregroundStyle(.white)
                Image(systemName: "speaker.wave.2").foregroundStyle(.white.opacity(0.8))
                Spacer()
            }
            Text("たべる · taberu").font(JojoFont.jp(14)).foregroundStyle(.white.opacity(0.55)).frame(maxWidth: .infinity)
            DefinitionRow(number: 1, tag: "ichidan", text: "to eat", dark: true)
            HighlightedSentence(sentence: "コンビニでおにぎりを食べました。", target: "食べ", size: 16, baseColor: .white)
            if let clip {
                Color(hex: "#1C1C1E")
                    .frame(height: 96)
                    .overlay { GradientPoster(clip: clip, showsSymbol: false).allowsHitTesting(false) }
                    .overlay { Image(systemName: "play.fill").foregroundStyle(.white).frame(width: 44, height: 44).background(.black.opacity(0.4), in: Circle()) }
                    .clipShape(.rect(cornerRadius: 14, style: .continuous))
            }
            HStack(spacing: Spacing.s) {
                Text("Again\n<1m").font(.footnote.weight(.bold)).multilineTextAlignment(.center).foregroundStyle(Color.againText)
                    .frame(maxWidth: .infinity, minHeight: 48).background(Color.againBackground, in: RoundedRectangle(cornerRadius: 14))
                Text("Good\n3d").font(.footnote.weight(.bold)).multilineTextAlignment(.center).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48).background(Color.goodBackground, in: RoundedRectangle(cornerRadius: 14))
            }
        }
        .padding(Spacing.l)
        .background(Color(hex: "#121212"), in: RoundedRectangle(cornerRadius: Radius.sheet, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.sheet, style: .continuous).strokeBorder(Color(hex: "#2A2A2A")))
        .shadow(color: .black.opacity(0.22), radius: 20, y: 10)
    }
}

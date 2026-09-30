import SwiftUI

/// Near-black atmospheric background with a slow warm glow.
struct OnboardingBackground: View {
    var body: some View {
        ZStack {
            Color.bgPlayer
            RadialGradient(colors: [Color.nagareOrange.opacity(0.22), .clear], center: .init(x: 0.85, y: -0.05), startRadius: 10, endRadius: 420)
            RadialGradient(colors: [Color(hex: "#3B82F6").opacity(0.08), .clear], center: .init(x: 0.0, y: 1.0), startRadius: 10, endRadius: 380)
        }
        .ignoresSafeArea()
    }
}

/// The 流れ wordmark with a self-drawing orange brush stroke.
struct NagareLogo: View {
    var drawProgress: CGFloat = 1
    var size: CGFloat = 1

    var body: some View {
        VStack(spacing: 10 * size) {
            Text("流れ")
                .font(NagareFont.jp(64 * size, bold: true, relativeTo: .largeTitle))
                .foregroundStyle(.white)
            FlowStroke()
                .trim(from: 0, to: drawProgress)
                .stroke(
                    LinearGradient(colors: [Color(hex: "#FF8A2B"), .nagareOrange], startPoint: .leading, endPoint: .trailing),
                    style: StrokeStyle(lineWidth: 7 * size, lineCap: .round, lineJoin: .round)
                )
                .frame(width: 170 * size, height: 26 * size)
            Text("NAGARE")
                .font(.system(size: 15 * size, weight: .semibold))
                .tracking(7 * size)
                .foregroundStyle(.white.opacity(0.7))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Nagare")
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

/// Large title + subtitle used on every question screen.
struct OnboardingTitle: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(title)
                .font(.system(.largeTitle, design: .default, weight: .bold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle {
                Text(subtitle)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    var body: some View {
        FlowLayout(spacing: 4, lineSpacing: 10) {
            ForEach(Array(words.enumerated()), id: \.offset) { _, word in
                VStack(spacing: 2) {
                    Text(word.furigana ?? " ")
                        .font(NagareFont.jp(size * 0.45, relativeTo: .caption2))
                        .foregroundStyle(word.state == .selected ? Color.nagareOrange : .white.opacity(0.6))
                    Text(word.surface)
                        .font(NagareFont.jp(size, bold: true, relativeTo: .title2))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .background {
                            switch word.state {
                            case .selected:
                                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.nagareOrange)
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
                            .foregroundStyle(word.state == .selected ? Color.nagareOrange : .white.opacity(0.5))
                    }
                }
                .fixedSize()
            }
        }
    }
}

/// Selectable large card for single/multi-select questions.
struct OptionCard: View {
    let title: String
    var subtitle: String?
    var symbol: String?
    let isSelected: Bool

    var body: some View {
        HStack(spacing: Spacing.m) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(isSelected ? .white : Color.nagareOrange)
                    .frame(width: 44, height: 44)
                    .background(isSelected ? Color.white.opacity(0.2) : Color.nagareOrangeSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).foregroundStyle(.white)
                if let subtitle {
                    Text(subtitle).font(.subheadline).foregroundStyle(.white.opacity(0.7))
                }
            }
            Spacer(minLength: 0)
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isSelected ? .white : .white.opacity(0.3))
        }
        .padding(Spacing.l)
        .frame(minHeight: 72)
        .background(isSelected ? Color.nagareOrange : Color.bgElevatedDark, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(isSelected ? .clear : Color.hairlineDark))
        .contentShape(Rectangle())
        .animation(.snappy, value: isSelected)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Frozen tap-to-understand card (value-prop illustration).
struct MockPopupCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: Spacing.s) {
                        Text("天気").font(NagareFont.jp(36, bold: true)).foregroundStyle(.white)
                        Image(systemName: "speaker.wave.2").foregroundStyle(.white.opacity(0.8))
                    }
                    Text("てんき").font(NagareFont.jp(14)).foregroundStyle(.white.opacity(0.85))
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
        .background(Color.bgElevatedDark, in: RoundedRectangle(cornerRadius: Radius.sheet, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.sheet, style: .continuous).strokeBorder(Color.white.opacity(0.08)))
        .shadow(color: .black.opacity(0.5), radius: 20, y: 10)
    }
}

/// Mini review card (value-prop illustration).
struct MockReviewCard: View {
    let clip: Clip?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack {
                Spacer()
                Text("食べる").font(NagareFont.jp(34, bold: true)).foregroundStyle(.white)
                Image(systemName: "speaker.wave.2").foregroundStyle(.white.opacity(0.8))
                Spacer()
            }
            Text("たべる · taberu").font(NagareFont.jp(14)).foregroundStyle(.white.opacity(0.55)).frame(maxWidth: .infinity)
            DefinitionRow(number: 1, tag: "ichidan", text: "to eat", dark: true)
            HighlightedSentence(sentence: "コンビニでおにぎりを食べました。", target: "食べ", size: 16, baseColor: .white)
            if let clip {
                Color.bgElevatedDark
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
        .background(Color.bgSurfaceDark, in: RoundedRectangle(cornerRadius: Radius.sheet, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.sheet, style: .continuous).strokeBorder(Color.hairlineDark))
    }
}

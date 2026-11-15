import SwiftUI

private struct AmberImmersionKaraokeKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var amberImmersionKaraoke: Bool {
        get { self[AmberImmersionKaraokeKey.self] }
        set { self[AmberImmersionKaraokeKey.self] = newValue }
    }
}

/// Visual state of a transcript word.
nonisolated enum TokenVisualState: Sendable {
    case normal, spoken, selected
}

/// A three-tier word: furigana (only above kanji), surface, romaji. Always at least 44pt tall and wide.
/// Hierarchy: mastery-coloured Japanese (amber→green), muted readings, POS underlines,
/// green spoken cursor, accent tap selection. The selected glow level applies to every word.
struct TokenView: View {
    let token: Token
    let state: TokenVisualState
    let isLookedUp: Bool
    var familiarity: SRSState? = nil
    var highlight: Bool = false
    var pulse: Bool = false
    var tooltip: String?
    var showFurigana: Bool = true
    var showRomaji: Bool = true
    var tapEnabled: Bool = true
    /// Feed karaoke keeps word lookup available even when profile-wide taps are disabled.
    var forceWordTaps: Bool = false
    /// Full immersion keeps the Japanese quiet while retaining the spoken cursor and lookup.
    var minimalStyling: Bool = false
    var stablePlaybackHighlight: Bool = false
    var playbackCompleted: Bool = false
    var lightPaper: Bool = false
    let onTap: () -> Void

    @Environment(AppModel.self) private var app
    @Environment(\.spokenTokenNamespace) private var spokenNamespace
    @Environment(\.karaokeOnPicture) private var onPicture
    @Environment(\.amberImmersionKaraoke) private var amberImmersionKaraoke
    @AppStorage(PlayerPrefs.immersionTextPaletteKey) private var immersionTextPalette = ImmersionTextPalette.warmAmber.rawValue
    // JojoFont.jp applies Dynamic Type; its input must be the unscaled base size.
    // Regular weight (not Bold) keeps karaoke neat like immersion reference screens.
    private static let furiganaSize: CGFloat = 9
    private static let wordSize: CGFloat = 22
    @ScaledMetric(relativeTo: .caption2) private var romajiSize: CGFloat = 10
    @State private var tapBounce: Bool = false

    private var contrastWord: Bool { amberImmersionKaraoke && !token.isPunctuation }
    private var isTappable: Bool {
        let hasText = !token.surface.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return token.tappable || (forceWordTaps && hasText && !token.isPunctuation)
    }
    private var picturePalette: ImmersionTextPalette? {
        // Preserve the original portrait immersion in Classic: words remain unboxed
        // with their familiar underline/cursor styling. Palettes belong to Amber Contrast.
        guard onPicture, amberImmersionKaraoke else { return nil }
        return ImmersionTextPalette(rawValue: immersionTextPalette) ?? .warmAmber
    }
    private var readingShadow: Color { contrastWord ? .black.opacity(0.85) : .clear }

    var body: some View {
        if isTappable && tapEnabled {
            Button {
                withAnimation(Motion.tapBounce) { tapBounce = true }
                onTap()
                Task {
                    try? await Task.sleep(for: .milliseconds(180))
                    withAnimation(Motion.tapBounce) { tapBounce = false }
                }
            } label: { content }
                .buttonStyle(PressableStyle())
                .accessibilityLabel(accessibilityText)
                .accessibilityHint("Explains the word and adds it to your flashcards")
        } else {
            content
                .accessibilityLabel(accessibilityText)
                .accessibilityHidden(token.isPunctuation)
        }
    }

    private var content: some View {
        VStack(spacing: 1) {
            rubyRow
                .padding(.horizontal, isTappable ? 5 : 0)
                .padding(.vertical, 1)
                .background { wordBackground }
                .overlay { spokenOutline }
                .overlay(alignment: .bottom) { underline }
                .textGlow(activeGlowColor, level: activeGlowLevel, boosted: state == .spoken || pulse)
            if showRomaji {
                Text(token.romaji.isEmpty ? " " : token.romaji)
                    .font(.system(size: romajiSize, weight: .regular))
                    .foregroundStyle(readingColor.opacity(onPicture ? 0.78 : 0.85))
                    .shadow(color: readingShadow, radius: 2, y: 1)
                    .textGlow(activeGlowColor, level: activeGlowLevel, boosted: state == .spoken || pulse)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .frame(minWidth: isTappable ? 40 : 8, minHeight: 40)
        .contentShape(Rectangle())
        // Feed karaoke keeps size stable; only the green outline marks the spoken word.
        .scaleEffect(pulse || tapBounce || (!stablePlaybackHighlight && state == .spoken) ? 1.04 : 1)
        .overlay(alignment: .top) {
            if let tooltip {
                Text(tooltip)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.black)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .frame(maxWidth: 220)
                    .background(.white, in: Capsule())
                    .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
                    .offset(y: -42)
                    .allowsHitTesting(false)
            }
        }
        .animation(stablePlaybackHighlight ? .easeInOut(duration: 0.12) : .spring(response: 0.3, dampingFraction: 0.6), value: state)
        .animation(.easeOut(duration: 0.2), value: familiarity)
    }

    /// Kanji carry their own furigana; okurigana sit beside without a reading overhead.
    private var rubyRow: some View {
        HStack(alignment: .bottom, spacing: 0) {
            ForEach(Array(token.rubySegments.enumerated()), id: \.offset) { _, segment in
                VStack(spacing: 1) {
                    if showFurigana {
                        Text(segment.reading ?? " ")
                            .font(JojoFont.jp(Self.furiganaSize, relativeTo: .caption2))
                            .foregroundStyle(readingColor)
                            .shadow(color: readingShadow, radius: 2, y: 1)
                            .multilineTextAlignment(.center)
                            // Let long readings wrap within a constrained token rather
                            // than truncating them at the karaoke panel's edge.
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                            .opacity(segment.reading == nil ? 0 : 1)
                    }
                    Text(segment.text)
                        .font(JojoFont.jp(Self.wordSize, bold: false, relativeTo: .title3))
                        .foregroundStyle(japaneseColor)
                        .shadow(color: onPicture ? .black.opacity(0.45) : .clear, radius: 2, y: 1)
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                }
            }
        }
    }

    /// Effective mastery for colouring — looked-up-but-unpainted reads as Learning.
    private var mastery: SRSState? {
        if let familiarity { return familiarity }
        if isLookedUp { return .learning }
        return isTappable ? .new : nil
    }

    @ViewBuilder
    private var wordBackground: some View {
        if let picturePalette, isTappable {
            RoundedRectangle(cornerRadius: 7)
                .fill(Color(hex: picturePalette.hex))
        } else if contrastWord {
            RoundedRectangle(cornerRadius: 7)
                .fill(state == .spoken ? Color(hex: "#F4A340") : Color(hex: "#252525").opacity(0.84))
        } else {
        switch state {
        case .selected:
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(LearningInk.selected.opacity(0.18))
        case .spoken:
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(LearningInk.spoken.opacity(stablePlaybackHighlight ? 0.1 : 0.16))
        case .normal:
            if minimalStyling || mastery == .known || mastery == .easy {
                Color.clear
            } else if highlight {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(LearningInk.selected.opacity(0.12))
            } else if let mastery, mastery != .new {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(LearningInk.mastery(mastery).opacity(0.12))
            }
        }
        }
    }

    @ViewBuilder
    private var spokenOutline: some View {
        if picturePalette != nil, isTappable, (state == .spoken || state == .selected) {
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(Color.white, lineWidth: 1.5)
        } else if contrastWord {
            if state == .spoken || state == .selected {
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(state == .spoken ? Color.white : LearningInk.selected, lineWidth: 1.5)
            }
        } else {
        switch state {
        case .spoken:
            Group {
                if !stablePlaybackHighlight, let ns = spokenNamespace {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(LearningInk.spoken, lineWidth: 2)
                        .matchedGeometryEffect(id: "spokenOutline", in: ns)
                } else {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(LearningInk.spoken, lineWidth: stablePlaybackHighlight ? 1.6 : 2)
                }
            }
            .modifier(KaraokeCursorPulse(glowEnabled: app.profile.glow != .off && !stablePlaybackHighlight))
        case .selected:
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(LearningInk.selected, lineWidth: 2)
        case .normal:
            if !minimalStyling && mastery == .known {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(LearningInk.known, lineWidth: 2)
            } else if !minimalStyling && mastery == .easy {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(LearningInk.easy, lineWidth: 1.6)
            }
        }
        }
    }

    @ViewBuilder
    private var underline: some View {
        // Underlines carry POS when still New; mastery ink otherwise. Hidden under boxes / known.
        if contrastWord {
            EmptyView()
        } else if minimalStyling, state == .spoken {
            Capsule()
                .fill(LearningInk.spoken)
                .frame(height: 2)
                .padding(.horizontal, 3)
                .offset(y: 2)
        } else if !minimalStyling, isTappable, state == .normal, mastery != .known, mastery != .easy {
            Capsule()
                .fill(underlineColor)
                .frame(height: 2)
                .padding(.horizontal, 3)
                .offset(y: 2)
        }
    }

    private var japaneseColor: Color {
        if let picturePalette, isTappable {
            return picturePalette.usesDarkInk ? Color(hex: "#191919") : .white
        }
        if contrastWord {
            return state == .spoken ? Color(hex: "#191919") : Color.white.opacity(playbackCompleted ? 0.8 : 1)
        }
        switch state {
        case .spoken: return LearningInk.spoken
        case .selected: return LearningInk.selected
        case .normal:
            if lightPaper && !isTappable { return Color(hex: "#292929") }
            guard isTappable && !minimalStyling else { return LearningInk.japanese(onPicture: onPicture) }
            // Mastery wall stays on paper; portrait bands keep white so bright footage stays readable.
            return onPicture ? LearningInk.japanese(onPicture: true) : LearningInk.mastery(mastery)
        }
    }

    private var readingColor: Color {
        if let picturePalette, isTappable {
            return picturePalette.usesDarkInk ? Color.black.opacity(0.58) : Color.white.opacity(0.72)
        }
        if contrastWord { return .white }
        switch state {
        case .spoken: return (lightPaper ? Color(hex: "#16834A") : LearningInk.spoken).opacity(0.9)
        case .selected: return (lightPaper ? Color(hex: "#B45B00") : LearningInk.selected).opacity(0.9)
        case .normal:
            if lightPaper { return Color(hex: "#777777") }
            if !onPicture, isTappable, let mastery, mastery != .new {
                return LearningInk.mastery(mastery).opacity(0.75)
            }
            return LearningInk.furigana(onPicture: onPicture)
        }
    }

    private var activeGlowLevel: GlowLevel {
        switch state {
        case .spoken, .selected: return app.profile.glow
        case .normal: return app.profile.fullTextGlow ? app.profile.glow : .off
        }
    }

    private var activeGlowColor: Color {
        // Amber Contrast uses solid word fills, which can hide the theme's usual green
        // playback halo. Keep the profile glow preference visible with a neutral rim.
        if contrastWord {
            switch state {
            case .spoken, .selected: return .white
            case .normal: return .white
            }
        }
        switch state {
        case .spoken: return LearningInk.spoken
        case .selected: return LearningInk.selected
        case .normal: return pulse ? LearningInk.spoken : LearningInk.glow
        }
    }

    private var accessibilityText: String {
        var parts = [token.surface]
        if showFurigana, let reading = token.reading { parts.append(reading) }
        if !minimalStyling, tapEnabled, let meaning = token.definitions.first { parts.append(meaning) }
        if !minimalStyling, let mastery { parts.append(mastery.title) }
        return parts.joined(separator: ", ")
    }

    private var underlineColor: Color {
        switch mastery {
        case .known: return LearningInk.known
        case .easy: return LearningInk.easy
        case .familiar: return LearningInk.familiar
        case .learning: return LearningInk.learning
        case .new, .none: return token.underlineColor
        }
    }
}

/// A soft playback pulse, separate from layout and disabled by Reduce Motion.
struct KaraokeCursorPulse: ViewModifier {
    var glowEnabled: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content.phaseAnimator([false, true]) { cursor, bright in
                cursor
                    .opacity(bright ? 1 : 0.68)
                    .shadow(color: LearningInk.spoken.opacity(glowEnabled ? (bright ? 0.4 : 0.15) : 0),
                            radius: bright ? 6 : 3)
            } animation: { _ in .easeInOut(duration: 0.75) }
        }
    }
}

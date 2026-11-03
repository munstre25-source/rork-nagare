import SwiftUI

/// Visual state of a transcript word.
nonisolated enum TokenVisualState: Sendable {
    case normal, spoken, selected
}

/// A three-tier word: furigana (only above kanji), surface, romaji. Always at least 44pt tall and wide.
/// Hierarchy: mastery-coloured Japanese (amber→green), muted readings, POS underlines,
/// green spoken cursor, accent tap selection. Glow only on spoken/selected.
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
    /// Full immersion keeps the Japanese quiet while retaining the spoken cursor and lookup.
    var minimalStyling: Bool = false
    var stablePlaybackHighlight: Bool = false
    let onTap: () -> Void

    @Environment(AppModel.self) private var app
    @Environment(\.spokenTokenNamespace) private var spokenNamespace
    // JojoFont.jp applies Dynamic Type; its input must be the unscaled base size.
    private static let furiganaSize: CGFloat = 10
    private static let wordSize: CGFloat = 24
    @ScaledMetric(relativeTo: .caption2) private var romajiSize: CGFloat = 11
    @State private var tapBounce: Bool = false

    var body: some View {
        if token.tappable && tapEnabled {
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
        VStack(spacing: 2) {
            rubyRow
                .padding(.horizontal, token.tappable ? 6 : 0)
                .padding(.vertical, 1)
                .background { wordBackground }
                .overlay { spokenOutline }
                .overlay(alignment: .bottom) { underline }
                .textGlow(activeGlowColor, level: activeGlowLevel, boosted: state == .spoken || pulse)
            if showRomaji {
                Text(token.romaji.isEmpty ? " " : token.romaji)
                    .font(.system(size: romajiSize))
                    .foregroundStyle(readingColor.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .frame(minWidth: token.tappable ? 44 : 10, minHeight: 44)
        .contentShape(Rectangle())
        .scaleEffect(pulse || tapBounce || (!stablePlaybackHighlight && state == .spoken) ? 1.06 : 1)
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
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                            .opacity(segment.reading == nil ? 0 : 1)
                    }
                    Text(segment.text)
                        .font(JojoFont.jp(Self.wordSize, bold: true, relativeTo: .title2))
                        .foregroundStyle(japaneseColor)
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
        return token.tappable ? .new : nil
    }

    @ViewBuilder
    private var wordBackground: some View {
        switch state {
        case .selected:
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(LearningInk.selected.opacity(0.18))
        case .spoken:
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(LearningInk.spoken.opacity(0.16))
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

    @ViewBuilder
    private var spokenOutline: some View {
        switch state {
        case .spoken:
            if !stablePlaybackHighlight, let ns = spokenNamespace {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(LearningInk.spoken, lineWidth: 2.4)
                    .matchedGeometryEffect(id: "spokenOutline", in: ns)
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(LearningInk.spoken, lineWidth: 2.4)
            }
        case .selected:
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(LearningInk.selected, lineWidth: 2.4)
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

    @ViewBuilder
    private var underline: some View {
        // Underlines carry POS when still New; mastery ink otherwise. Hidden under boxes / known.
        if minimalStyling, state == .spoken {
            Capsule()
                .fill(LearningInk.spoken)
                .frame(height: 3)
                .padding(.horizontal, 4)
                .offset(y: 3)
        } else if !minimalStyling, token.tappable, state == .normal, mastery != .known, mastery != .easy {
            Capsule()
                .fill(underlineColor)
                .frame(height: 3)
                .padding(.horizontal, 4)
                .offset(y: 3)
        }
    }

    private var japaneseColor: Color {
        switch state {
        case .spoken: return LearningInk.spoken
        case .selected: return LearningInk.selected
        case .normal:
            guard token.tappable && !minimalStyling else { return LearningInk.japanese }
            return LearningInk.mastery(mastery)
        }
    }

    private var readingColor: Color {
        switch state {
        case .spoken: return LearningInk.spoken.opacity(0.9)
        case .selected: return LearningInk.selected.opacity(0.9)
        case .normal:
            if token.tappable, let mastery, mastery != .new {
                return LearningInk.mastery(mastery).opacity(0.75)
            }
            return LearningInk.furigana
        }
    }

    private var activeGlowLevel: GlowLevel {
        switch state {
        case .spoken, .selected: return app.profile.glow
        case .normal: return pulse ? app.profile.glow : .off
        }
    }

    private var activeGlowColor: Color {
        switch state {
        case .spoken: return LearningInk.spoken
        case .selected: return LearningInk.selected
        case .normal: return pulse ? LearningInk.spoken : .clear
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

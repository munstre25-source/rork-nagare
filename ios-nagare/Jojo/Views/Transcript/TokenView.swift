import SwiftUI

/// Visual state of a transcript word.
nonisolated enum TokenVisualState: Sendable {
    case normal, spoken, selected
}

/// A three-tier word: furigana (only above kanji), surface, romaji. Always at least 44pt tall and wide.
struct TokenView: View {
    let token: Token
    let state: TokenVisualState
    let isLookedUp: Bool
    var highlight: Bool = false
    var pulse: Bool = false
    var tooltip: String?
    var showFurigana: Bool = true
    var showRomaji: Bool = true
    let onTap: () -> Void

    @ScaledMetric(relativeTo: .caption2) private var furiganaSize: CGFloat = 11
    @ScaledMetric(relativeTo: .title2) private var wordSize: CGFloat = 24
    @ScaledMetric(relativeTo: .caption2) private var romajiSize: CGFloat = 11

    var body: some View {
        if token.tappable {
            Button(action: onTap) { content }
                .buttonStyle(PressableStyle())
                .accessibilityLabel(accessibilityText)
                .accessibilityHint("Explains the word and adds it to your flashcards")
        } else {
            content
                .accessibilityHidden(true)
        }
    }

    private var content: some View {
        VStack(spacing: 2) {
            if showFurigana {
                Text(token.furigana ?? " ")
                    .font(JojoFont.jp(furiganaSize, relativeTo: .caption2))
                    .foregroundStyle(state == .selected ? Color.jojoOrange : Color.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
            Text(token.surface)
                .font(JojoFont.jp(wordSize, bold: true, relativeTo: .title2))
                .foregroundStyle(state == .selected ? Color.jojoOrange : Color.primary)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, token.tappable ? 6 : 0)
                .padding(.vertical, 1)
                .background { wordBackground }
                .overlay(alignment: .bottom) { underline }
            if showRomaji {
                Text(token.romaji.isEmpty ? " " : token.romaji)
                    .font(.system(size: romajiSize))
                    .foregroundStyle(state == .selected ? Color.jojoOrange : Color.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .frame(minWidth: token.tappable ? 44 : 10, minHeight: 44)
        .contentShape(Rectangle())
        .scaleEffect(pulse ? 1.08 : 1)
        .overlay(alignment: .top) {
            if let tooltip {
                Text(tooltip)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.white, in: Capsule())
                    .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
                    .fixedSize()
                    .offset(y: -42)
                    .allowsHitTesting(false)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: state)
    }

    @ViewBuilder
    private var wordBackground: some View {
        switch state {
        case .selected:
            // Outline so the word stays readable (always-visible reading aids).
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.jojoOrange, lineWidth: 2.5)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.jojoOrange.opacity(0.18))
                )
        case .spoken:
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.spokenGreen, lineWidth: 2)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.spokenGreen.opacity(0.12)))
        case .normal:
            if highlight {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.jojoOrange.opacity(0.28))
            }
        }
    }

    @ViewBuilder
    private var underline: some View {
        if token.tappable, state != .selected {
            Capsule()
                .fill(isLookedUp ? Color.lookedUpOrange : Color.tappableBlue)
                .frame(height: 3)
                .padding(.horizontal, 4)
                .offset(y: 3)
        }
    }

    private var accessibilityText: String {
        var parts = [token.surface]
        if let reading = token.reading { parts.append(reading) }
        if let meaning = token.definitions.first { parts.append(meaning) }
        if isLookedUp { parts.append("looked up before") }
        return parts.joined(separator: ", ")
    }
}

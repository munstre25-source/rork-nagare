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
    var familiarity: SRSState? = nil
    var highlight: Bool = false
    var pulse: Bool = false
    var tooltip: String?
    var showFurigana: Bool = true
    var showRomaji: Bool = true
    let onTap: () -> Void

    @Environment(\.spokenTokenNamespace) private var spokenNamespace
    @ScaledMetric(relativeTo: .caption2) private var furiganaSize: CGFloat = 11
    @ScaledMetric(relativeTo: .title2) private var wordSize: CGFloat = 24
    @ScaledMetric(relativeTo: .caption2) private var romajiSize: CGFloat = 11
    @State private var tapBounce: Bool = false

    var body: some View {
        if token.tappable {
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
                .accessibilityHidden(true)
        }
    }

    private var content: some View {
        VStack(spacing: 2) {
            if showFurigana {
                Text(token.furigana ?? " ")
                    .font(JojoFont.jp(furiganaSize, relativeTo: .caption2))
                    .foregroundStyle(state == .selected ? Color.designOrange : Color.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Text(token.surface)
                .font(JojoFont.jp(wordSize, bold: true, relativeTo: .title2))
                .foregroundStyle(state == .selected ? Color.designOrange : Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .padding(.horizontal, token.tappable ? 6 : 0)
                .padding(.vertical, 1)
                .background { wordBackground }
                .overlay { spokenOutline }
                .overlay(alignment: .bottom) { underline }
            if showRomaji {
                Text(token.romaji.isEmpty ? " " : token.romaji)
                    .font(.system(size: romajiSize))
                    .foregroundStyle(state == .selected ? Color.designOrange : Color.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .frame(minWidth: token.tappable ? 44 : 10, minHeight: 44)
        .contentShape(Rectangle())
        .scaleEffect(pulse || tapBounce ? 1.08 : 1)
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
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: state)
    }

    @ViewBuilder
    private var wordBackground: some View {
        switch state {
        case .selected:
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.designOrange, lineWidth: 2.5)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.sakuraPinkSoft)
                )
        case .spoken:
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.spokenGreen.opacity(0.12))
        case .normal:
            if familiarity == .known {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.spokenGreen, lineWidth: 2)
            } else if isLookedUp {
                // Saved / looked-up words get an orange fill like Kiku's 石炭.
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.sakuraPinkSoft)
            } else if highlight {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.sakuraPinkSoft)
            }
        }
    }

    @ViewBuilder
    private var spokenOutline: some View {
        if state == .spoken, let ns = spokenNamespace {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.spokenGreen, lineWidth: 2)
                .matchedGeometryEffect(id: "spokenOutline", in: ns)
        } else if state == .spoken {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.spokenGreen, lineWidth: 2)
        }
    }

    @ViewBuilder
    private var underline: some View {
        if token.tappable, state != .selected, familiarity != .known {
            Capsule()
                .fill(underlineColor)
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
        if familiarity == .known { parts.append("known") }
        if familiarity == .familiar { parts.append("familiar") }
        return parts.joined(separator: ", ")
    }

    private var underlineColor: Color {
        switch familiarity {
        case .known: Color.spokenGreen
        case .familiar: Color.designOrange
        default: isLookedUp ? Color.lookedUpOrange : token.underlineColor
        }
    }
}

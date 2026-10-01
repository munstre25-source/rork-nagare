import SwiftUI

nonisolated enum PillStyle: Sendable {
    case pos, jlpt, neutralDark
}

/// Small rounded label for part of speech, conjugation class or JLPT level.
struct PillView: View {
    let text: String
    var style: PillStyle = .pos

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(foreground)
            .background(background, in: Capsule())
    }

    private var foreground: Color {
        switch style {
        case .pos: .posPillText
        case .jlpt: .jlptPillText
        case .neutralDark: Color(hex: "#D1D1D6")
        }
    }

    private var background: Color {
        switch style {
        case .pos: .posPill
        case .jlpt: .jlptPill
        case .neutralDark: Color(hex: "#3A3A3C")
        }
    }
}

/// Orange circle showing how many times the user has encountered a word.
struct OccurrenceBadge: View {
    let count: Int
    var size: CGFloat = 32

    var body: some View {
        Text("\(count)")
            .font(.system(size: size * 0.44, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white)
            .contentTransition(.numericText(value: Double(count)))
            .frame(width: size, height: size)
            .background(Color.nagareOrange, in: Circle())
            .accessibilityLabel("Encountered \(count) times")
    }
}

/// Word metadata pills: POS, conjugation (verbs/adjectives), JLPT.
struct WordPills: View {
    let pos: String
    let conjugationClass: String?
    let jlpt: String?
    var dark: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            PillView(text: pos, style: dark ? .neutralDark : .pos)
            if let conjugationClass, showsConjugation {
                PillView(text: conjugationClass, style: dark ? .neutralDark : .pos)
            }
            if let jlpt {
                PillView(text: jlpt, style: .jlpt)
            }
        }
    }

    private var showsConjugation: Bool {
        pos == "verb" || pos.contains("adjective")
    }
}

/// Primary orange call-to-action button style with a press animation.
struct PrimaryButtonStyle: ButtonStyle {
    var isEnabled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(Color.nagareOrange.opacity(isEnabled ? 1 : 0.35), in: RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Subtle press-to-shrink style for cards and chips.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Filter chip used in Vocab and Explore.
struct FilterChip: View {
    let title: String
    var systemImage: String?
    var isSelected: Bool = false
    var dark: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage).font(.subheadline.weight(.semibold))
            }
            Text(title).font(.subheadline.weight(.medium))
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 40)
        .foregroundStyle(isSelected ? .white : (dark ? Color.white.opacity(0.9) : Color.primary))
        .background(
            isSelected ? Color.nagareOrange : (dark ? Color.bgElevatedDark : Color.fieldFill),
            in: Capsule()
        )
        .contentShape(Capsule())
    }
}

import SwiftUI

/// Guided first-session win: tap a word → hear it → mark Good once.
struct FirstSessionWinOverlay: View {
    let step: FirstSessionStep
    var onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("First win")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.sakuraPink)
                        .textCase(.uppercase)
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                    }
                    .accessibilityLabel("Skip first-session coach")
                }
                Text(step.title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
                Text(step.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                progressDots
            }
            .padding(18)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.sakuraPink.opacity(0.5), lineWidth: 1.2)
            )
            .padding(.horizontal, Spacing.l)
            .padding(.bottom, 100)
        }
        .allowsHitTesting(true)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var progressDots: some View {
        HStack(spacing: 6) {
            ForEach(FirstSessionStep.allCases, id: \.self) { s in
                Capsule()
                    .fill(s.rawValue <= step.rawValue ? Color.sakuraPink : Color.primary.opacity(0.15))
                    .frame(width: s == step ? 22 : 8, height: 6)
            }
        }
        .padding(.top, 4)
    }
}

nonisolated enum FirstSessionStep: Int, CaseIterable, Sendable {
    case tap = 0
    case hear = 1
    case good = 2
    case done = 3

    var title: String {
        switch self {
        case .tap: return "Tap any glowing word"
        case .hear: return "Hear how it sounds"
        case .good: return "Mark it Good"
        case .done: return "You did it"
        }
    }

    var detail: String {
        switch self {
        case .tap: return "Pause on a word you don’t know. Jojo saves it as a flashcard instantly."
        case .hear: return "Tap the speaker on the card so your ear locks the sound to the meaning."
        case .good: return "Paint Learning or tap Good — one honest mark beats a perfect queue."
        case .done: return "That’s your first loop. Keep scrolling — words will come back."
        }
    }
}

import SwiftUI

/// Toast when a saved word reappears in the spoken line.
struct CameBackToast: View {
    let surface: String
    let gloss: String
    var onReview: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Came back")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.sakuraPink)
                    .textCase(.uppercase)
                Text(surface)
                    .font(JojoFont.jp(18, bold: true, relativeTo: .headline))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if !gloss.isEmpty {
                    Text(gloss)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Button("Review", action: onReview)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(minHeight: 32)
                .background(Color.sakuraButton, in: Capsule())
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.sakuraPink.opacity(0.45), lineWidth: 1)
        )
        .padding(.horizontal, Spacing.l)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

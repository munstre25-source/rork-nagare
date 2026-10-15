import SwiftUI

/// “Continue where you left off” chip above the For You pager.
struct ResumeChip: View {
    let title: String
    let channel: String
    let time: Double
    var onResume: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onResume) {
                HStack(spacing: 10) {
                    Image(systemName: "play.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(Color.sakuraButton, in: Circle())
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Continue")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Color.sakuraPink)
                            .textCase(.uppercase)
                        Text(title.isEmpty ? channel : title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(formatClock(time) + (channel.isEmpty ? "" : " · \(channel)"))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
            }
            .accessibilityLabel("Dismiss resume")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.cardStroke)
        )
        .padding(.horizontal, Spacing.l)
        .padding(.bottom, 4)
    }
}

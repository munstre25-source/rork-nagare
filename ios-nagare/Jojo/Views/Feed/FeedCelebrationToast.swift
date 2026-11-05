import SwiftUI

/// A short top-of-screen moment for goals and achievements. Never covers playback controls.
struct FeedCelebration: Identifiable, Equatable {
    enum Kind { case goal, achievement }
    let id = UUID()
    let kind: Kind
    let title: String
    let detail: String
    var symbol: String = "flame.fill"

    var eyebrow: String { kind == .goal ? "DAILY GOAL" : "ACHIEVEMENT UNLOCKED" }
}

struct FeedCelebrationToast: View {
    let celebration: FeedCelebration
    @State private var pop = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Color.designOrange, Color.sakuraPink],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: celebration.kind == .goal ? "trophy.fill" : celebration.symbol)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .scaleEffect(pop ? 1 : 0.4)
                ConfettiBurst(count: 12, radius: 34)
            }
            .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(celebration.eyebrow)
                    .font(.caption2.weight(.heavy))
                    .tracking(1.2)
                    .foregroundStyle(Color.designOrange)
                Text(celebration.title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                Text(celebration.detail)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            JojoMascotAvatar(size: 34)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial.opacity(0.9), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.white.opacity(0.12)))
        .environment(\.colorScheme, .dark)
        .padding(.horizontal, 16)
        .frame(maxWidth: 480)
        .onAppear {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.5).delay(0.08)) { pop = true }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

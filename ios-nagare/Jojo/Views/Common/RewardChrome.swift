import SwiftUI

/// Due count and streak, once on the first open of the day.
struct WelcomeHomeBurst: View {
    var due: Int
    var streak: Int
    @State private var shown = false
    @State private var dueShown = 0
    @State private var streakShown = 0

    var body: some View {
        VStack(spacing: 8) {
            Text("Welcome back")
                .font(.headline.weight(.bold))
            if streak > 0 {
                Text("\(streakShown)")
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.designOrange)
                    .contentTransition(.numericText(value: Double(streakShown)))
                Text("streak")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            if due > 0 {
                Text("\(dueShown) due")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Color.sakuraButton)
                    .contentTransition(.numericText(value: Double(dueShown)))
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 22)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.sakuraButton.opacity(0.45), lineWidth: 1)
        }
        .shadow(color: Color.sakuraButton.opacity(shown ? 0.35 : 0), radius: 24)
        .scaleEffect(shown ? 1 : 0.55)
        .opacity(shown ? 1 : 0)
        .onAppear {
            Haptics.heavy()
            withAnimation(.spring(response: 0.48, dampingFraction: 0.62)) {
                shown = true
                dueShown = due
                streakShown = streak
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Chunky press for the review button. The tab capsule is unchanged.
struct ChunkyPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.5), value: configuration.isPressed)
    }
}

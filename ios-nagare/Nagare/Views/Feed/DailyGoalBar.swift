import SwiftUI

/// Thin orange daily-goal progress bar with remaining minutes and a trophy that fills on completion.
struct DailyGoalBar: View {
    @Environment(AppModel.self) private var app
    @State private var trophyBounce: Bool = false
    @State private var showConfetti: Bool = false

    var body: some View {
        HStack(spacing: Spacing.m) {
            Text(app.isGoalReached ? "Goal done" : "\(app.minutesLeft) min left")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.9))
                .contentTransition(.numericText())
                .fixedSize()
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))
                    Capsule()
                        .fill(LinearGradient(colors: [Color(hex: "#FF8A2B"), .nagareOrange], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(8, proxy.size.width * app.goalProgress))
                        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: app.goalProgress)
                }
            }
            .frame(height: 6)
            ZStack {
                Image(systemName: app.isGoalReached ? "trophy.fill" : "trophy")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(app.isGoalReached ? Color.nagareOrange : .white.opacity(0.7))
                    .scaleEffect(trophyBounce ? 1.5 : 1)
                    .rotationEffect(.degrees(trophyBounce ? -12 : 0))
                if showConfetti {
                    ConfettiBurst()
                }
            }
            .frame(width: 44, height: 44)
        }
        .padding(.horizontal, Spacing.l)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Daily goal")
        .accessibilityValue(app.isGoalReached ? "Completed" : "\(app.minutesLeft) minutes left of \(app.profile.dailyGoalMinutes)")
        .onChange(of: app.goalCelebrationCount) { _, _ in celebrate() }
    }

    private func celebrate() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.4)) { trophyBounce = true }
        showConfetti = true
        Task {
            try? await Task.sleep(for: .milliseconds(650))
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { trophyBounce = false }
            try? await Task.sleep(for: .milliseconds(900))
            showConfetti = false
        }
    }
}

/// Small radial particle burst.
struct ConfettiBurst: View {
    @State private var expanded: Bool = false
    var colors: [Color] = [.nagareOrange, Color(hex: "#FFD23F"), Color(hex: "#34C759"), .white]
    var count: Int = 14
    var radius: CGFloat = 40

    var body: some View {
        ZStack {
            ForEach(0..<count, id: \.self) { i in
                let angle = Double(i) / Double(count) * 2 * .pi
                Circle()
                    .fill(colors[i % colors.count])
                    .frame(width: 6, height: 6)
                    .offset(x: expanded ? cos(angle) * radius : 0, y: expanded ? sin(angle) * radius : 0)
                    .opacity(expanded ? 0 : 1)
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeOut(duration: 0.9)) { expanded = true }
        }
    }
}

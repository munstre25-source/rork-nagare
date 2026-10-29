import SwiftUI

/// Accent pill with how long this For You visit has been open. Pauses off the tab and in the background.
struct StudySessionClock: View {
    var running: Bool

    @State private var accumulated: TimeInterval = 0
    @State private var mark = Date()

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = shown(at: context.date)
            Text(formatClock(elapsed))
                .font(.caption.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .frame(minWidth: 52, minHeight: 26)
                .background(Color.sakuraButton, in: Capsule())
                .accessibilityLabel("Study time \(formatClock(elapsed))")
        }
        .onChange(of: running) { _, isRunning in
            if isRunning {
                mark = .now
            } else {
                accumulated += Date().timeIntervalSince(mark)
            }
        }
    }

    private func shown(at date: Date) -> TimeInterval {
        accumulated + (running ? date.timeIntervalSince(mark) : 0)
    }
}

/// Thin sakura daily-goal progress bar with remaining minutes and a trophy that fills on completion.
struct DailyGoalBar: View {
    @Environment(AppModel.self) private var app
    @State private var trophyBounce: Bool = false
    @State private var showConfetti: Bool = false
    @State private var bloom: Bool = false

    var body: some View {
        HStack(spacing: Spacing.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(app.isGoalReached ? "Daily goal done" : "\(app.minutesLeft) min left today")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.primary.opacity(0.9))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .contentTransition(.numericText())
                Text(app.isGoalReached ? "Nice work today" : "Daily goal · about \(app.clipsLeftToday) clip\(app.clipsLeftToday == 1 ? "" : "s")")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.sakuraPink)
                    .textCase(.uppercase)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.1))
                    Capsule()
                        .fill(Color.sakuraBar)
                        .frame(width: max(8, proxy.size.width * app.goalProgress))
                        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: app.goalProgress)
                }
            }
            .frame(height: 6)
            ZStack {
                Circle()
                    .fill(Color.sakuraButton.opacity(bloom ? 0 : 0.75))
                    .frame(width: 36, height: 36)
                    .blur(radius: 6)
                    .scaleEffect(bloom ? 3.4 : 0.25)
                    .opacity(showConfetti ? 1 : 0)
                Image(systemName: app.isGoalReached ? "trophy.fill" : "trophy")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(app.isGoalReached ? Color.sakuraPink : .secondary)
                    .scaleEffect(trophyBounce ? 1.5 : 1)
                    .rotationEffect(.degrees(trophyBounce ? -12 : 0))
                if showConfetti {
                    ConfettiBurst(colors: [Color.sakuraButton, Color.sakuraPinkLight, .white], count: 16, radius: 52)
                }
            }
            .frame(width: 44, height: 44)
        }
        .padding(.horizontal, Spacing.l)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Daily goal")
        .accessibilityValue(
            app.isGoalReached
                ? "Completed"
                : "\(app.minutesLeft) minutes left, about \(app.clipsLeftToday) clips, of \(app.profile.dailyGoalMinutes)"
        )
        .onChange(of: app.goalCelebrationCount) { _, _ in celebrate() }
    }

    private func celebrate() {
        Haptics.heavy()
        withAnimation(.easeOut(duration: 0.55)) { bloom = true }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.4)) { trophyBounce = true }
        showConfetti = true
        Task {
            try? await Task.sleep(for: .milliseconds(650))
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { trophyBounce = false }
            try? await Task.sleep(for: .milliseconds(900))
            showConfetti = false
            bloom = false
        }
    }
}

/// Small radial particle burst.
struct ConfettiBurst: View {
    @State private var expanded: Bool = false
    var colors: [Color] = [.sakuraPink, Color.sakuraPinkLight, Color(hex: "#34C759"), .white]
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

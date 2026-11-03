import SwiftUI

/// One-line feed chrome: hanko streak · minutes bar · words caught · wild catches · trophy.
/// Tapping opens the Today sheet. Replaces the taller DailyGoalBar row on For You.
struct ProgressStrip: View {
    var dueWords = 0
    var onReview: (() -> Void)?

    @Environment(AppModel.self) private var app
    @State private var showsToday = false
    @State private var trophyBounce = false

    var body: some View {
        Button {
            Haptics.selection()
            showsToday = true
        } label: {
            HStack(spacing: 10) {
                streakHanko
                minutesBar
                metric(app.wordsCaughtToday, label: "words")
                if app.wildCatchCountToday > 0 {
                    metric(app.wildCatchCountToday, label: "wild", accent: true)
                }
                Image(systemName: app.isGoalReached ? "trophy.fill" : "trophy")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(app.isGoalReached ? Color.sakuraPink : .secondary)
                    .scaleEffect(trophyBounce ? 1.25 : 1)
                    .frame(width: 28, height: 28)
            }
            .padding(.horizontal, Spacing.l)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Today's progress")
        .accessibilityValue(accessibilityValue)
        .accessibilityHint("Opens today's listening summary")
        .onChange(of: app.goalCelebrationCount) { _, _ in
            withAnimation(.spring(response: 0.35, dampingFraction: 0.4)) { trophyBounce = true }
            Task {
                try? await Task.sleep(for: .milliseconds(650))
                withAnimation { trophyBounce = false }
            }
        }
        .sheet(isPresented: $showsToday) {
            TodaySheet(dueWords: dueWords, onReview: onReview)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private var streakHanko: some View {
        ZStack {
            Circle()
                .strokeBorder(Color.sakuraPink.opacity(0.85), lineWidth: 1.6)
                .frame(width: 28, height: 28)
            Text("\(app.currentStreak)")
                .font(.caption2.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(Color.sakuraPink)
        }
        .accessibilityLabel("\(app.currentStreak) day streak")
    }

    private var minutesBar: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(app.isGoalReached
                 ? "Goal complete"
                 : "\(Int(app.todayWatchedSeconds / 60))/\(app.profile.dailyGoalMinutes)m")
                .font(.caption2.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(Color.sakuraPink)
                .lineLimit(1)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.1))
                    Capsule()
                        .fill(Color.sakuraBar)
                        .frame(width: max(4, proxy.size.width * app.goalProgress))
                }
            }
            .frame(height: 3)
        }
        .frame(maxWidth: 120)
    }

    private func metric(_ value: Int, label: String, accent: Bool = false) -> some View {
        VStack(spacing: 0) {
            Text("\(value)")
                .font(.caption.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(accent ? Color.sakuraPink : .primary)
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 36)
    }

    private var accessibilityValue: String {
        var parts = ["\(app.currentStreak) day streak"]
        parts.append(app.isGoalReached
                     ? "daily goal complete"
                     : "\(Int(app.todayWatchedSeconds / 60)) of \(app.profile.dailyGoalMinutes) minutes")
        parts.append("\(app.wordsCaughtToday) words saved today")
        if app.wildCatchCountToday > 0 {
            parts.append("\(app.wildCatchCountToday) caught in the wild")
        }
        return parts.joined(separator: ", ")
    }
}

/// Quiet daily summary — streak, goal, wild catches, immersion hours, comprehension.
struct TodaySheet: View {
    var dueWords = 0
    var onReview: (() -> Void)?

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Streak", value: "\(app.currentStreak) day\(app.currentStreak == 1 ? "" : "s")")
                    LabeledContent("Listening today", value: "\(Int(app.todayWatchedSeconds / 60)) / \(app.profile.dailyGoalMinutes) min")
                    LabeledContent("Words saved today", value: "\(app.wordsCaughtToday)")
                    LabeledContent("Caught in the wild", value: "\(app.wildCatchCountToday)")
                    if let avg = app.weeklyComprehensionAverage {
                        LabeledContent("Understood this week", value: "\(avg)%")
                    }
                    if app.profile.lastClipComprehension > 0 {
                        LabeledContent("Last clip", value: "\(app.profile.lastClipComprehension)% understood")
                    }
                } header: {
                    Text("Today")
                }

                Section {
                    if let level = app.immersionLevel {
                        LabeledContent("Level", value: "\(level.title) · \(level.hours)h")
                    } else {
                        LabeledContent("Level", value: "Just starting")
                    }
                    LabeledContent("Lifetime listening", value: String(format: "%.1f h", app.immersionHours))
                    if let next = app.nextImmersionLevel {
                        let remain = max(0, Double(next.hours) - app.immersionHours)
                        LabeledContent("Next · \(next.title)", value: String(format: "%.1f h to go", remain))
                    }
                } header: {
                    Text("Immersion")
                } footer: {
                    Text("Levels mark real hours of Japanese in your ears — not points.")
                }

                if !app.wildCatchesToday.isEmpty {
                    Section("Caught in the wild") {
                        ForEach(app.wildCatchesToday, id: \.self) { surface in
                            Text(surface)
                                .font(JojoFont.jp(17, bold: true, relativeTo: .body))
                        }
                    }
                }

                if dueWords > 0, let onReview {
                    Section {
                        Button("Review \(dueWords) word\(dueWords == 1 ? "" : "s")") {
                            dismiss()
                            onReview()
                        }
                    }
                }
            }
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

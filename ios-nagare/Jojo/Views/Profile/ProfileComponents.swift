import SwiftUI

/// Compact stat used in the Profile's three-up row.
struct ProfileStat: View {
    let symbol: String
    let tint: Color
    let value: String
    let caption: String
    var action: (() -> Void)? = nil

    var body: some View {
        let content = VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tint)
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .cardStyle()
        .accessibilityElement(children: .combine)
        if let action {
            Button(action: action) { content }
                .buttonStyle(.plain)
                .accessibilityHint("Opens your streak calendar and activity details")
        } else {
            content
        }
    }
}

/// 15 weeks of watch minutes as a GitHub-style grid. Darker means closer to the daily goal.
struct ActivityHeatmap: View {
    let log: [String: Double]
    let goalMinutes: Int
    var studySecondsForDay: ((Date) -> Double)? = nil
    var onSelectDay: ((Date) -> Void)? = nil
    private let weeks = 15

    private struct Day: Identifiable {
        let date: Date
        let minutes: Double
        var id: Date { date }
    }

    private var columns: [[Day?]] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weekday = calendar.component(.weekday, from: today) - calendar.firstWeekday
        let offsetInWeek = (weekday + 7) % 7
        guard let start = calendar.date(byAdding: .day, value: -(offsetInWeek + (weeks - 1) * 7), to: today) else { return [] }
        return (0..<weeks).map { week in
            (0..<7).map { day -> Day? in
                guard let date = calendar.date(byAdding: .day, value: week * 7 + day, to: start),
                      date <= today else { return nil }
                let seconds = studySecondsForDay?(date) ?? log[AppModel.dayKey(date), default: 0]
                return Day(date: date, minutes: seconds / 60)
            }
        }
    }

    private var activeDays: Int {
        columns.joined().compactMap { $0 }.filter { $0.minutes >= 1 }.count
    }

    private func color(for minutes: Double) -> Color {
        guard minutes >= 1 else { return Color.primary.opacity(0.08) }
        let ratio = min(1, minutes / Double(max(goalMinutes, 1)))
        return Color.designOrange.opacity(0.3 + 0.7 * ratio)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(alignment: .firstTextBaseline) {
                Text("Activity").font(.headline)
                Spacer()
                Text(activeDays == 1 ? "1 active day" : "\(activeDays) active days")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            GeometryReader { proxy in
                let gap: CGFloat = 4
                let cell = max(6, (proxy.size.width - gap * CGFloat(weeks - 1)) / CGFloat(weeks))
                HStack(alignment: .top, spacing: gap) {
                    ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                        VStack(spacing: gap) {
                            ForEach(0..<7, id: \.self) { index in
                                if let day = column[index] {
                                    Button {
                                        Haptics.selection()
                                        onSelectDay?(day.date)
                                    } label: {
                                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                                            .fill(color(for: day.minutes))
                                            .frame(width: cell, height: cell)
                                            .overlay {
                                                if Calendar.current.isDateInToday(day.date) {
                                                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                                                        .strokeBorder(Color.designOrange, lineWidth: 1.5)
                                                }
                                            }
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(day.date.formatted(date: .complete, time: .omitted))
                                    .accessibilityValue(day.minutes >= 1 ? "\(Int(day.minutes)) minutes studied" : "No study recorded")
                                    .accessibilityHint("Opens the streak calendar for this day")
                                } else {
                                    Color.clear.frame(width: cell, height: cell)
                                }
                            }
                        }
                    }
                }
            }
            .aspectRatio(CGFloat(weeks) / 7 * 1.02, contentMode: .fit)
            HStack(spacing: 6) {
                Text("Less").font(.caption2).foregroundStyle(.secondary)
                ForEach([0.0, 0.3, 0.6, 1.0], id: \.self) { ratio in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color(for: ratio == 0 ? 0 : max(1, ratio * Double(goalMinutes))))
                        .frame(width: 10, height: 10)
                }
                Text("Goal met").font(.caption2).foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(Spacing.l)
        .cardStyle()
        .accessibilityElement(children: .contain)
    }
}

/// Milestones computed from progress the app already tracks; nothing extra is stored.
struct ProfileAchievement: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    let symbol: String
    let unlocked: Bool
    let progress: Double
    let value: Int
    let target: Int

    var category: String {
        switch id {
        case "streak-3", "streak-7", "streak-30": "Streak"
        case "minutes-60", "minutes-600": "Watch time"
        default: "Vocabulary"
        }
    }

    var unit: String {
        switch category {
        case "Streak": "days"
        case "Watch time": "minutes"
        default: "words"
        }
    }

    static func all(streak: Int, words: Int, known: Int, minutes: Int) -> [ProfileAchievement] {
        func make(_ id: String, _ title: String, _ detail: String, _ symbol: String, value: Int, target: Int) -> ProfileAchievement {
            ProfileAchievement(id: id, title: title, detail: detail, symbol: symbol,
                               unlocked: value >= target, progress: min(1, Double(value) / Double(max(target, 1))),
                               value: value, target: target)
        }
        return [
            make("first-word", "First catch", "Save your first word", "sparkle", value: words, target: 1),
            make("words-25", "Word hunter", "Save 25 words", "character.book.closed.fill", value: words, target: 25),
            make("words-100", "Collector", "Save 100 words", "books.vertical.fill", value: words, target: 100),
            make("known-10", "It sticks", "Know 10 words", "brain.head.profile", value: known, target: 10),
            make("known-50", "Fluent fifty", "Know 50 words", "graduationcap.fill", value: known, target: 50),
            make("streak-3", "On a roll", "3-day streak", "flame", value: streak, target: 3),
            make("streak-7", "One week", "7-day streak", "flame.fill", value: streak, target: 7),
            make("streak-30", "Unstoppable", "30-day streak", "crown.fill", value: streak, target: 30),
            make("minutes-60", "First hour", "Watch 60 minutes", "clock.fill", value: minutes, target: 60),
            make("minutes-600", "Deep dive", "Watch 10 hours", "water.waves", value: minutes, target: 600),
        ]
    }
}

struct AchievementBadge: View {
    let item: ProfileAchievement

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.08), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: item.progress)
                    .stroke(item.unlocked ? Color.designOrange : Color.sakuraPink.opacity(0.6),
                            style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: item.symbol)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(item.unlocked ? Color.designOrange : Color.secondary.opacity(0.6))
            }
            .frame(width: 58, height: 58)
            Text(item.title)
                .font(.caption.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(item.unlocked ? .primary : .secondary)
            Text(item.detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(item.unlocked ? "Unlocked" : "\(Int(item.progress * 100)) percent")
    }
}

struct AchievementsView: View {
    let achievements: [ProfileAchievement]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 16)], spacing: 22) {
                ForEach(achievements) { item in
                    NavigationLink {
                        AchievementDetailView(item: item)
                    } label: {
                        AchievementBadge(item: item)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
        }
        .background(Color.canvas.ignoresSafeArea())
        .navigationTitle("Achievements")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
    }
}

struct AchievementDetailView: View {
    let item: ProfileAchievement

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.l) {
                Image(systemName: item.symbol)
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(Color.studyAccent)
                    .frame(width: 90, height: 90)
                    .background(Color.studyAccent.opacity(0.12), in: .circle)
                    .accessibilityHidden(true)
                VStack(spacing: Spacing.s) {
                    Text(item.title).font(.title.bold())
                        .accessibilityAddTraits(.isHeader)
                    Text(item.category).font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.studyAccent)
                    Text(item.detail).foregroundStyle(.secondary)
                }
                Label(item.unlocked ? "Unlocked" : "Locked",
                      systemImage: item.unlocked ? "checkmark.seal.fill" : "lock.fill")
                    .font(.subheadline.weight(.semibold))
                VStack(alignment: .leading, spacing: Spacing.s) {
                    ProgressView(value: item.progress) {
                        Text("Progress")
                    } currentValueLabel: {
                        Text("\(min(item.value, item.target)) of \(item.target) \(item.unit)")
                            .monospacedDigit()
                    }
                    .tint(Color.studyAccent)
                    if !item.unlocked {
                        Text("Remaining · \(item.target - item.value) \(item.unit)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(Spacing.l)
                .cardStyle()
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: 440)
            .padding(Spacing.l)
            .frame(maxWidth: .infinity)
        }
        .background(Color.canvas.ignoresSafeArea())
        .navigationTitle("Achievement")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
    }
}

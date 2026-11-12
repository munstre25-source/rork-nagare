import SwiftUI
import SwiftData

struct StreakView: View {
    @Environment(AppModel.self) private var app
    @Query private var words: [SavedWord]
    @Environment(\.colorScheme) private var colorScheme
    @State private var displayedMonth = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()
    @State private var selectedDate = Date()
    @State private var showsSettings = false

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 5), count: 7)
    private var startMinutes: Int { app.profile.streakDayStartMinutes }
    private var monthLabel: String { displayedMonth.formatted(.dateTime.month(.abbreviated).year()) }
    private var monthDays: [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: displayedMonth),
              let dayRange = calendar.range(of: .day, in: .month, for: displayedMonth) else { return [] }
        let weekday = calendar.component(.weekday, from: interval.start)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        return Array(repeating: nil, count: leading) + dayRange.compactMap { day in
            calendar.date(byAdding: .day, value: day - 1, to: interval.start)
        }.map { Optional($0) }
    }
    private var activeDayKeys: Set<String> {
        let keys = Set(app.watchLog.keys).union(app.streakActivity.keys)
        return Set(keys.filter { key in
            guard let date = date(from: key) else { return false }
            return app.studySeconds(for: date) >= 60
        })
    }
    private var bestStreak: Int {
        let dates = activeDayKeys.compactMap { date(from: $0) }.sorted()
        guard !dates.isEmpty else { return 0 }
        var best = 1
        var current = 1
        for pair in zip(dates, dates.dropFirst()) {
            if calendar.dateComponents([.day], from: pair.0, to: pair.1).day == 1 {
                current += 1
                best = max(best, current)
            } else {
                current = 1
            }
        }
        return best
    }
    private var daysStudiedThisYear: Int {
        let year = calendar.component(.year, from: Date())
        return activeDayKeys.filter { date(from: $0).map { calendar.component(.year, from: $0) == year } ?? false }.count
    }
    private var selectedActivity: StreakDayActivity { app.activity(for: selectedDate) }
    private var selectedStudySeconds: Double { app.studySeconds(for: selectedDate) }
    private var selectedVideoSeconds: Double {
        let key = AppModel.dayKey(selectedDate)
        let tracked = app.streakActivity[key]?.videoSeconds ?? 0
        return tracked > 0 ? tracked : app.watchLog[key, default: 0]
    }
    private var selectedWordsSaved: Int {
        let key = AppModel.dayKey(selectedDate)
        if selectedActivity.wordsSaved > 0 { return selectedActivity.wordsSaved }
        guard let startedAt = app.profile.streakDetailsTrackingStartedAt,
              selectedDate >= calendar.startOfDay(for: startedAt) else {
            return words.count { AppModel.dayKey($0.addedAt) == key }
        }
        return selectedActivity.wordsSaved
    }
    private var trackingStartedForSelectedDay: Bool {
        guard let startedAt = app.profile.streakDetailsTrackingStartedAt else { return true }
        return selectedDate >= calendar.startOfDay(for: startedAt)
    }
    private var selectedClipsWatched: Int? {
        if selectedActivity.clipsFinished > 0 || !selectedActivity.watchedClipIds.isEmpty {
            return max(selectedActivity.clipsFinished, selectedActivity.watchedClipIds.count)
        }
        guard trackingStartedForSelectedDay else { return nil }
        return 0
    }
    private var selectedCardsReviewed: Int? {
        if selectedActivity.cardsReviewed > 0 { return selectedActivity.cardsReviewed }
        if trackingStartedForSelectedDay { return 0 }
        let dayKey = AppModel.dayKey(selectedDate)
        let mostRecentReviews = words.count { word in
            guard let lastReviewedAt = word.lastReviewedAt else { return false }
            return AppModel.dayKey(lastReviewedAt) == dayKey
        }
        return mostRecentReviews > 0 ? mostRecentReviews : nil
    }
    private var dayRating: String {
        if selectedStudySeconds >= app.dailyGoalSeconds { return "Great day" }
        return selectedStudySeconds >= 60 ? "Good day" : "Rest day"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                activityGrid
                monthCalendar
                selectedDayCard
                summaryCard
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .background(Color.canvas.ignoresSafeArea())
        .navigationTitle("Streak")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showsSettings = true } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Streak settings")
            }
        }
        .sheet(isPresented: $showsSettings) {
            StreakSettingsSheet()
                .presentationDetents([.height(250)])
                .presentationDragIndicator(.visible)
        }
        .onAppear {
            let today = effectiveToday
            displayedMonth = calendar.dateInterval(of: .month, for: today)?.start ?? today
            selectedDate = calendar.startOfDay(for: today)
        }
        .onChange(of: startMinutes) { _, _ in
            let today = effectiveToday
            displayedMonth = calendar.dateInterval(of: .month, for: today)?.start ?? today
            selectedDate = calendar.startOfDay(for: today)
        }
    }

    private var activityGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Activity").font(.headline)
                Spacer()
                Text("Last 16 weeks").font(.caption).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 16), spacing: 4) {
                ForEach(heatmapDates, id: \.self) { date in
                    let seconds = app.studySeconds(for: date)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(activityColor(seconds))
                        .aspectRatio(1, contentMode: .fit)
                        .overlay {
                            if calendar.isDate(date, inSameDayAs: selectedDate) {
                                RoundedRectangle(cornerRadius: 3).strokeBorder(Color.designOrange, lineWidth: 1.5)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { selectedDate = date; alignMonth(to: date) }
                }
            }
            HStack(spacing: 5) {
                Text("Less").font(.caption2).foregroundStyle(.secondary)
                ForEach(0..<4, id: \.self) { level in
                    RoundedRectangle(cornerRadius: 2).fill(activityColor(Double(level) * 600))
                        .frame(width: 10, height: 10)
                }
                Text("More").font(.caption2).foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(16)
        .streakCardStyle()
    }

    private var monthCalendar: some View {
        VStack(spacing: 12) {
            HStack {
                ForEach(weekdaySymbols, id: \.self) { day in
                    Text(day).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Array(monthDays.enumerated()), id: \.offset) { _, day in
                    if let day {
                        let date = streakDate(for: calendar.component(.day, from: day), in: displayedMonth)
                        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
                        let active = app.studySeconds(for: date) >= 60
                        Button { selectedDate = date } label: {
                            Text("\(calendar.component(.day, from: day))")
                                .font(.system(size: 15, weight: active ? .semibold : .medium, design: .rounded))
                                .foregroundStyle(active ? Color.white : dayIsFuture(date) ? Color.secondary.opacity(0.35) : Color.secondary)
                                .frame(maxWidth: .infinity).frame(height: 38)
                                .background {
                                    if active { RoundedRectangle(cornerRadius: 12).fill(Color.designOrange) }
                                    if isSelected { RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white, lineWidth: 2) }
                                }
                        }
                        .buttonStyle(.plain)
                        .disabled(dayIsFuture(date))
                    } else {
                        Color.clear.frame(height: 38)
                    }
                }
            }
            HStack(spacing: 8) {
                Menu {
                    ForEach(monthOptions, id: \.self) { month in
                        Button(month.formatted(.dateTime.month(.wide).year())) {
                            displayedMonth = month
                            selectedDate = streakDate(for: min(calendar.component(.day, from: selectedDate), dayCount(in: month)), in: month)
                        }
                    }
                } label: {
                    HStack {
                        Text(monthLabel).font(.subheadline.weight(.semibold))
                        Image(systemName: "chevron.down").font(.caption2.weight(.bold))
                    }
                    .frame(maxWidth: .infinity).frame(height: 42)
                    .background(Color.primary.opacity(0.06), in: Capsule())
                }
                .tint(.primary)
                Button { moveMonth(-1) } label: { Image(systemName: "chevron.left") }
                    .streakRoundButton()
                Button { moveMonth(1) } label: { Image(systemName: "chevron.right") }
                    .streakRoundButton()
                    .disabled(!canMoveForward)
                Button { showsSettings = true } label: { Image(systemName: "pencil") }
                    .streakRoundButton()
                    .accessibilityLabel("Edit streak settings")
            }
            .padding(.top, 6)
        }
        .padding(16)
        .streakCardStyle()
    }

    private var selectedDayCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(selectedDate.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.headline)
                Spacer()
                Label(dayRating, systemImage: selectedStudySeconds >= app.dailyGoalSeconds ? "sun.max.fill" : selectedStudySeconds >= 60 ? "sun.max" : "moon")
                    .font(.caption.weight(.medium)).foregroundStyle(selectedStudySeconds >= 60 ? Color.designOrange : Color.secondary)
            }
            detailRow("Study time", value: durationText(selectedStudySeconds), icon: "clock")
            detailRow("Videos", value: durationText(selectedVideoSeconds), icon: "play")
            detailRow("Flashcards", value: durationText(selectedActivity.flashcardSeconds), icon: "square.stack.3d.up")
            detailRow("Clips watched", value: selectedClipsWatched.map(countText) ?? "—", icon: "film")
            detailRow("Cards reviewed", value: selectedCardsReviewed.map(countText) ?? "—", icon: "arrow.counterclockwise")
            detailRow("Words saved", value: countText(selectedWordsSaved), icon: "bookmark")
            if selectedClipsWatched == nil || selectedCardsReviewed == nil {
                Text("Clip counts are recorded from \(app.profile.streakDetailsTrackingStartedAt?.formatted(date: .abbreviated, time: .omitted) ?? "today"). Earlier dates show review counts only when the word record still has that review date.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
        .padding(16)
        .streakCardStyle()
    }

    private var summaryCard: some View {
        VStack(spacing: 0) {
            summaryRow("Current streak", value: "\(app.currentStreak) days")
            Divider().opacity(0.5)
            summaryRow("Best streak", value: "\(bestStreak) days")
            Divider().opacity(0.5)
            summaryRow("Days studied this year", value: "\(daysStudiedThisYear)")
        }
        .padding(.horizontal, 16)
        .streakCardStyle()
    }

    private var heatmapDates: [Date] {
        let today = calendar.startOfDay(for: effectiveToday)
        return (0..<112).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
    }

    private var effectiveToday: Date {
        calendar.date(byAdding: .minute, value: -startMinutes, to: Date()) ?? Date()
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let offset = calendar.firstWeekday - 1
        return Array(symbols[offset...] + symbols[..<offset])
    }

    private var monthOptions: [Date] {
        (0..<18).reversed().compactMap { calendar.date(byAdding: .month, value: -$0, to: calendar.dateInterval(of: .month, for: Date())?.start ?? Date()) }
    }

    private var canMoveForward: Bool { displayedMonth < (calendar.dateInterval(of: .month, for: Date())?.start ?? Date()) }

    private func moveMonth(_ amount: Int) {
        guard let next = calendar.date(byAdding: .month, value: amount, to: displayedMonth),
              next <= (calendar.dateInterval(of: .month, for: Date())?.start ?? Date()) else { return }
        displayedMonth = next
        selectedDate = streakDate(for: min(calendar.component(.day, from: selectedDate), dayCount(in: next)), in: next)
    }

    private func alignMonth(to date: Date) {
        displayedMonth = calendar.dateInterval(of: .month, for: date)?.start ?? date
    }

    private func streakDate(for day: Int, in month: Date) -> Date {
        let interval = calendar.dateInterval(of: .month, for: month)?.start ?? month
        let date = calendar.date(byAdding: .day, value: max(0, day - 1), to: interval) ?? interval
        return calendar.startOfDay(for: date)
    }

    private func dayCount(in month: Date) -> Int {
        calendar.range(of: .day, in: .month, for: month)?.count ?? 1
    }

    private func dayIsFuture(_ date: Date) -> Bool { AppModel.dayKey(date) > AppModel.dayKey(Date()) }

    private func date(from key: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: key)
    }

    private func activityColor(_ seconds: Double) -> Color {
        guard seconds >= 60 else { return Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.06) }
        let ratio = min(1, seconds / Double(max(app.profile.dailyGoalMinutes, 1) * 60))
        return Color.designOrange.opacity(0.3 + ratio * 0.7)
    }

    private func durationText(_ seconds: Double) -> String {
        guard seconds >= 60 else { return seconds > 0 ? "<1m" : "—" }
        let minutes = Int(seconds / 60)
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }

    private func countText(_ count: Int) -> String { count == 0 ? "—" : "\(count)" }

    private func detailRow(_ title: String, value: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 15)).foregroundStyle(.secondary).frame(width: 20)
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.semibold).monospacedDigit()
        }
        .font(.subheadline)
    }

    private func summaryRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.semibold).monospacedDigit()
        }
        .font(.subheadline)
        .padding(.vertical, 14)
    }
}

private struct StreakSettingsSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var startTime = Date()

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Day starts at", selection: $startTime, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.compact)
                    .onChange(of: startTime) { _, value in
                        let parts = Calendar.current.dateComponents([.hour, .minute], from: value)
                        app.setStreakDayStartMinutes((parts.hour ?? 0) * 60 + (parts.minute ?? 0))
                    }
                Text("Your streak day rolls over at this time. New activity before it belongs to the previous day. Past totals stay on their original dates because older watch time was stored by calendar day.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .navigationTitle("Streak settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .onAppear {
            startTime = Calendar.current.startOfDay(for: Date()).addingTimeInterval(TimeInterval(app.profile.streakDayStartMinutes * 60))
        }
    }
}

private extension View {
    func streakCardStyle() -> some View {
        background(Color.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.cardStroke))
    }

    func streakRoundButton() -> some View {
        font(.system(size: 14, weight: .semibold))
            .frame(width: 42, height: 42)
            .background(Color.primary.opacity(0.05), in: Circle())
            .overlay(Circle().strokeBorder(Color.cardStroke))
            .buttonStyle(.plain)
    }
}

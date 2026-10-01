import SwiftUI
import SwiftData
import Charts
import StoreKit

/// Progress + settings. Follows system light/dark.
struct ProfileView: View {
    @Environment(AppModel.self) private var app
    @Query private var words: [SavedWord]
    @State private var reviewSession: ReviewSessionConfig?
    @State private var showGoalPicker: Bool = false
    @State private var showManageSubs: Bool = false
    @State private var showCustomerCenter: Bool = false
    @State private var restoreMessage: String?
    @State private var confirmReset: Bool = false
    @State private var showMarketingShowcase: Bool = false
    var onGiveFeedback: (() -> Void)? = nil

    private var known: Int { words.filter { $0.state == .known }.count }
    private var learning: Int { words.filter { $0.state == .learning }.count }
    private var newCount: Int { words.filter { $0.state == .new }.count }

    /// JLPT level estimate from known + learning words.
    private var level: (jlpt: String, label: String) {
        let score = known * 2 + learning
        switch score {
        case ..<40: return ("N5", "Beginner")
        case ..<120: return ("N4", "Beginner")
        case ..<300: return ("N3", "Intermediate")
        case ..<700: return ("N2", "Intermediate")
        default: return ("N1", "Advanced")
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.l) {
                    Text("Keep going. A more fluent you is ahead.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    hero
                    HStack(spacing: Spacing.m) {
                        StatTile(symbol: "flame.fill", tint: .nagareOrange, value: "\(app.currentStreak)-day", caption: "streak")
                        StatTile(symbol: "clock", tint: .secondary, value: watchText, caption: "watched")
                    }
                    weeklyChart
                    mastery
                    Button {
                        let due = words.filter { $0.dueAt <= Date() }.sorted { $0.dueAt < $1.dueAt }
                        let pool = due.isEmpty ? words.shuffled() : due
                        let keys = Array(pool.prefix(10).map(\.key))
                        guard !keys.isEmpty else { return }
                        Haptics.medium()
                        reviewSession = ReviewSessionConfig(title: "Review", keys: keys)
                    } label: {
                        Label("Review 10 cards", systemImage: "play.fill")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(words.isEmpty)
                    settings
                    Text("Jojo 流れ · Scroll, Listen, Flow into Japanese.")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                        .padding(.top, Spacing.s)
                }
                .padding(.horizontal, Spacing.l)
                .padding(.bottom, Spacing.xl)
            }
            .background(Color.canvas.ignoresSafeArea())
            .navigationTitle("Profile")
        }
        .fullScreenCover(item: $reviewSession) { ReviewSessionView(config: $0) }
        .fullScreenCover(isPresented: $showMarketingShowcase) {
            MarketingShowcaseView()
        }
        .sheet(isPresented: $showGoalPicker) { DailyGoalSheet() }
        .manageSubscriptionsSheet(isPresented: $showManageSubs)
        .sheet(isPresented: $showCustomerCenter) { JojoCustomerCenter() }
        .alert("Restore Purchases", isPresented: Binding(get: { restoreMessage != nil }, set: { if !$0 { restoreMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(restoreMessage ?? "")
        }
        .confirmationDialog("Reset demo data?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset words & history", role: .destructive) { app.resetDemoData() }
        } message: {
            Text("Your saved words and watch history return to the starter set.")
        }
    }

    private var planText: String? {
        guard let status = app.purchases.status else { return nil }
        let plan = status.productId.contains("year") ? "Yearly" : "Monthly"
        return status.isInTrial ? "\(plan) · Trial" : plan
    }

    private var watchText: String {
        let minutes = Int(app.totalWatchSeconds / 60)
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }

    private var hero: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(known)")
                    .font(.system(size: 60, weight: .bold, design: .rounded))
                    .contentTransition(.numericText(value: Double(known)))
                    .animation(.snappy, value: known)
                Text("Words you know").font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(level.jlpt) · \(level.label)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.adaptive(light: "#15803D", dark: "#5EE39A"))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.jlptPill.opacity(0.18), in: Capsule())
        }
        .padding(Spacing.l)
        .cardStyle()
        .accessibilityElement(children: .combine)
    }

    private var weeklyChart: some View {
        let data = app.weeklyMinutes
        let today = Calendar.current.startOfDay(for: Date())
        return VStack(alignment: .leading, spacing: Spacing.s) {
            Text("This week").font(.headline)
            Text("Minutes watched").font(.subheadline).foregroundStyle(.secondary)
            Chart(data) { item in
                BarMark(
                    x: .value("Day", item.date, unit: .day),
                    y: .value("Minutes", item.minutes),
                    width: .ratio(0.55)
                )
                .foregroundStyle(item.date == today ? Color.nagareOrange : Color.nagareOrange.opacity(0.55))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                RuleMark(y: .value("Goal", app.profile.dailyGoalMinutes))
                    .foregroundStyle(Color.secondary.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                }
            }
            .frame(height: 150)
        }
        .padding(Spacing.l)
        .cardStyle()
    }

    private var mastery: some View {
        let total = max(words.count, 1)
        return VStack(alignment: .leading, spacing: Spacing.m) {
            Text("Mastery overview").font(.headline)
            GeometryReader { proxy in
                HStack(spacing: 2) {
                    Capsule().fill(Color.gray).frame(width: proxy.size.width * CGFloat(newCount) / CGFloat(total))
                    Capsule().fill(Color.nagareOrange).frame(width: proxy.size.width * CGFloat(learning) / CGFloat(total))
                    Capsule().fill(Color.goodBackground)
                }
            }
            .frame(height: 12)
            HStack {
                MasteryStat(color: .gray, label: "New", value: newCount)
                Divider().frame(height: 36)
                MasteryStat(color: .nagareOrange, label: "Learning", value: learning)
                Divider().frame(height: 36)
                MasteryStat(color: .goodBackground, label: "Known", value: known)
            }
        }
        .padding(Spacing.l)
        .cardStyle()
    }

    private var settings: some View {
        VStack(spacing: 0) {
            settingsHeader("Appearance")
            Menu {
                ForEach(AppearanceMode.allCases) { mode in
                    Button(mode.title) { app.setAppearance(mode) }
                }
            } label: {
                SettingsRowLabel(symbol: "circle.lefthalf.filled", title: "Theme", value: app.profile.appearance.title)
            }
            Divider().padding(.leading, 52)

            settingsHeader("Subtitles & reading")
            Menu {
                ForEach(SubtitleMode.allCases) { mode in
                    Button(mode.title) { app.setSubtitleMode(mode) }
                }
            } label: {
                SettingsRowLabel(symbol: "captions.bubble", title: "Subtitles", value: app.profile.subtitles.title)
            }
            Divider().padding(.leading, 52)
            settingsToggle(symbol: "textformat.ja", title: "Furigana on cards",
                           isOn: Binding(get: { app.profile.showFurigana }, set: { app.setShowFurigana($0) }))
            Divider().padding(.leading, 52)
            settingsToggle(symbol: "character", title: "Romaji under words",
                           isOn: Binding(get: { app.profile.showRomaji }, set: { app.setShowRomaji($0) }))
            Divider().padding(.leading, 52)
            Menu {
                ForEach(DictionaryMode.allCases) { mode in
                    Button(mode.title) { app.setDictionaryMode(mode) }
                }
            } label: {
                SettingsRowLabel(symbol: "character.book.closed.ja", title: "Dictionary", value: app.profile.dictionary.title)
            }
            Divider().padding(.leading, 52)

            settingsHeader("Study focus")
            Menu {
                ForEach(ReadingLevel.allCases) { level in
                    Button(level.title) { app.setReadingLevel(level) }
                }
            } label: {
                SettingsRowLabel(symbol: "chart.bar.fill", title: "Content level", value: app.profile.readingLevel.title)
            }
            Divider().padding(.leading, 52)
            settingsToggle(symbol: "lock.open", title: "Unlock by level",
                           isOn: Binding(get: { app.profile.gateContentByLevel }, set: { app.setGateContentByLevel($0) }))
            Divider().padding(.leading, 52)
            settingsToggle(symbol: "timer", title: "Hide daily goal bar",
                           isOn: Binding(get: { app.profile.hideDailyGoalBar }, set: { app.setHideDailyGoalBar($0) }))
            Divider().padding(.leading, 52)

            settingsHeader("Creator")
            SettingsRow(symbol: "record.circle", title: "Record marketing demo") {
                showMarketingShowcase = true
            }
            Divider().padding(.leading, 52)
            if let onGiveFeedback {
                SettingsRow(symbol: "bubble.left.and.bubble.right", title: "Give feedback") {
                    onGiveFeedback()
                }
                Divider().padding(.leading, 52)
            }

            settingsHeader("Account")
            SettingsRow(symbol: "target", title: "Daily goal", value: "\(app.profile.dailyGoalMinutes) min") { showGoalPicker = true }
            Divider().padding(.leading, 52)
            HStack(spacing: Spacing.m) {
                Image(systemName: "bell").frame(width: 28)
                Toggle("Reminders", isOn: Binding(
                    get: { app.profile.remindersEnabled },
                    set: { value in Task { await app.setReminders(value) } }
                ))
                .tint(.nagareOrange)
            }
            .padding(.horizontal, Spacing.l)
            .frame(minHeight: 54)
            Divider().padding(.leading, 52)
            SettingsRow(symbol: "star", title: "Manage Subscription", value: planText) {
                if app.purchases.isConfigured { showCustomerCenter = true } else { showManageSubs = true }
            }
            Divider().padding(.leading, 52)
            SettingsRow(symbol: "clock.arrow.circlepath", title: "Restore Purchases") {
                Task {
                    let outcome = await app.purchases.restore()
                    switch outcome {
                    case .success: restoreMessage = "Your Jojo Pro access is active."
                    case .cancelled, .pending: break
                    case .failed(let message): restoreMessage = message
                    }
                }
            }
            Divider().padding(.leading, 52)
            SettingsRow(symbol: "arrow.uturn.backward", title: "Reset demo data", tint: .red) { confirmReset = true }
        }
        .cardStyle()
    }

    private func settingsHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.l)
            .padding(.top, Spacing.m)
            .padding(.bottom, 4)
    }

    private func settingsToggle(symbol: String, title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: Spacing.m) {
            Image(systemName: symbol).frame(width: 28)
            Toggle(title, isOn: isOn).tint(.nagareOrange)
        }
        .padding(.horizontal, Spacing.l)
        .frame(minHeight: 54)
    }
}

private struct SettingsRowLabel: View {
    let symbol: String
    let title: String
    var value: String?

    var body: some View {
        HStack(spacing: Spacing.m) {
            Image(systemName: symbol).frame(width: 28)
            Text(title).foregroundStyle(.primary)
            Spacer()
            if let value { Text(value).foregroundStyle(.secondary) }
            Image(systemName: "chevron.up.chevron.down").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, Spacing.l)
        .frame(minHeight: 54)
        .contentShape(Rectangle())
    }
}

private struct StatTile: View {
    let symbol: String
    let tint: Color
    let value: String
    let caption: String

    var body: some View {
        HStack(spacing: Spacing.m) {
            Image(systemName: symbol).font(.title).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 0) {
                Text(value).font(.title3.weight(.bold)).lineLimit(1).minimumScaleFactor(0.7)
                Text(caption).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(Spacing.l)
        .frame(maxWidth: .infinity)
        .cardStyle()
        .accessibilityElement(children: .combine)
    }
}

private struct MasteryStat: View {
    let color: Color
    let label: String
    let value: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(label).font(.subheadline)
            }
            Text("\(value)").font(.title3.weight(.semibold)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct SettingsRow: View {
    let symbol: String
    let title: String
    var value: String?
    var tint: Color = .primary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.m) {
                Image(systemName: symbol).frame(width: 28)
                Text(title)
                Spacer()
                if let value { Text(value).foregroundStyle(.secondary) }
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .foregroundStyle(tint)
            .padding(.horizontal, Spacing.l)
            .frame(minHeight: 54)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct DailyGoalSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach([5, 10, 15, 20], id: \.self) { minutes in
                    Button {
                        Haptics.selection()
                        app.setDailyGoal(minutes)
                        dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text("\(minutes) min").font(.headline)
                                Text(DailyGoalOption.caption(minutes)).font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if app.profile.dailyGoalMinutes == minutes {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.nagareOrange)
                            }
                        }
                    }
                    .tint(.primary)
                }
            }
            .navigationTitle("Daily goal")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }
}

nonisolated enum DailyGoalOption {
    static func caption(_ minutes: Int) -> String {
        switch minutes {
        case 5: "~1 clip · a quick taste"
        case 10: "~2 clips · steady habit"
        case 15: "~3 clips · real momentum"
        default: "~4-5 clips · serious flow"
        }
    }
}

extension View {
    func cardStyle() -> some View {
        background(Color.card, in: RoundedRectangle(cornerRadius: Radius.sheet, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.sheet, style: .continuous).strokeBorder(Color.cardStroke))
    }
}

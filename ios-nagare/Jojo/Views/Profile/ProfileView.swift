import SwiftUI
import SwiftData
import Charts
import StoreKit

/// Progress + settings. Follows system light/dark.
struct ProfileView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL
    @AppStorage("jojo.quickChecksEnabled") private var quickChecksEnabled = true
    @Environment(\.marketingScrollsToTheme) private var marketingScrollsToTheme
    @Environment(\.marketingProfileAnchor) private var marketingProfileAnchor
    @Query private var words: [SavedWord]
    @State private var reviewSession: ReviewSessionConfig?
    @State private var showGoalPicker: Bool = false
    @State private var showManageSubs: Bool = false
    @State private var showCustomerCenter: Bool = false
    @State private var restoreMessage: String?
    @State private var confirmDeleteAccount: Bool = false
    @State private var showHelp: Bool = false
    #if DEBUG
    @State private var confirmReset: Bool = false
    @State private var marketingScript: MarketingScript?
    #endif
    var onGiveFeedback: (() -> Void)? = nil
    var tabBarHidden: Binding<Bool> = .constant(false)

    private var known: Int { words.filter { $0.state == .known }.count }
    private var familiar: Int { words.filter { $0.state == .familiar }.count }
    private var learning: Int { words.filter { $0.state == .learning }.count }
    private var newCount: Int { words.filter { $0.state == .new }.count }

    private var greeting: String {
        app.profile.firstName.isEmpty ? "Welcome back" : "Welcome back, \(app.profile.firstName)"
    }

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
            ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Profile")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text("Keep going. A more fluent you is ahead.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(spacing: Spacing.m) {
                        JojoMascotAvatar(size: 48)
                        Text(greeting)
                            .font(.title3.weight(.bold))
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    hero
                    HStack(spacing: Spacing.m) {
                        StatTile(symbol: "flame.fill", tint: .designOrange, value: "\(app.currentStreak)-day", caption: "streak")
                        StatTile(symbol: "clock", tint: .designOrangeDeep, value: watchText, caption: "watched")
                    }
                    streakWeek
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
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 48)
                            .background {
                                Capsule().fill(words.isEmpty ? Color.accentDisabled : Color.sakuraButton)
                            }
                    }
                    .buttonStyle(ChunkyPressStyle())
                    .disabled(words.isEmpty)
                    if words.isEmpty {
                        Text("Reviews unlock after you tap your first word in the feed.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .multilineTextAlignment(.center)
                    }
                    settings
                    Text("Jojo 流れ · Scroll, Listen, Flow into Japanese.")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                        .padding(.top, Spacing.s)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .background(Color.canvas.ignoresSafeArea())
            .onAppear {
                scrollMarketingProfile(proxy)
            }
            .onChange(of: marketingScrollsToTheme) { _, _ in
                scrollMarketingProfile(proxy)
            }
            .onChange(of: marketingProfileAnchor) { _, _ in
                scrollMarketingProfile(proxy)
            }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showHelp) { HelpView(onGiveFeedback: onGiveFeedback) }
        }
        .fullScreenCover(item: $reviewSession) { ReviewSessionView(config: $0) }
        #if DEBUG
        .fullScreenCover(item: $marketingScript) { script in
            MarketingShowcaseView(initialScript: script, accent: app.profile.theme, autoBegin: false)
        }
        #endif
        .sheet(isPresented: $showGoalPicker) { DailyGoalSheet() }
        .manageSubscriptionsSheet(isPresented: $showManageSubs)
        .sheet(isPresented: $showCustomerCenter) { JojoCustomerCenter() }
        .alert("Restore Purchases", isPresented: Binding(get: { restoreMessage != nil }, set: { if !$0 { restoreMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(restoreMessage ?? "")
        }
        #if DEBUG
        .confirmationDialog("Reset demo data?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset words & history", role: .destructive) { app.resetDemoData() }
        } message: {
            Text("Your saved words and watch history return to the starter set.")
        }
        #endif
        .confirmationDialog("Delete all data?", isPresented: $confirmDeleteAccount, titleVisibility: .visible) {
            Button("Delete All Data", role: .destructive) { app.deleteAllUserData() }
        } message: {
            Text("This permanently erases words, decks, watch history, and settings on this device, deletes the synced vocab, speaking practice, and video requests stored for this device, and returns you to onboarding. To cancel Jojo Pro, use Manage Subscription or Settings → Apple ID → Subscriptions.")
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
                Text(known == 0
                     ? "A word counts as known once you can recall it with 3 weeks between reviews."
                     : "Recalled with 3+ weeks between reviews.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                JLPTBadge(level: level.jlpt)
                Text(level.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(Spacing.l)
        .cardStyle()
        .accessibilityElement(children: .combine)
    }

    private var streakWeek: some View {
        let days = app.weeklyMinutes
        return HStack(spacing: 8) {
            ForEach(days) { day in
                let studied = day.minutes >= 1
                let isToday = Calendar.current.isDateInToday(day.date)
                VStack(spacing: 6) {
                    Text(day.date.formatted(.dateTime.weekday(.narrow)))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(isToday ? Color.sakuraButton : .secondary)
                    Circle()
                        .fill(studied ? Color.designOrange : Color.primary.opacity(0.12))
                        .frame(width: 28, height: 28)
                        .overlay {
                            if studied {
                                Image(systemName: "checkmark")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .shadow(color: isToday ? Color.sakuraButton.opacity(0.85) : .clear, radius: isToday ? 8 : 0)
                }
                .frame(maxWidth: .infinity)
                .accessibilityLabel("\(day.date.formatted(.dateTime.weekday(.wide)))\(studied ? ", studied" : "")")
            }
        }
        .padding(.vertical, 4)
    }

    private var weeklyChart: some View {
        let data = app.weeklyMinutes
        let today = Calendar.current.startOfDay(for: Date())
        return VStack(alignment: .leading, spacing: Spacing.s) {
            Text("This week").font(.headline)
            Text("Minutes watched · dashed line is your \(app.profile.dailyGoalMinutes)-min daily goal")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Chart(data) { item in
                BarMark(
                    x: .value("Day", item.date, unit: .day),
                    y: .value("Minutes", item.minutes),
                    width: .ratio(0.55)
                )
                .foregroundStyle(item.date == today ? Color.sakuraPink : Color.sakuraPinkSoft)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                RuleMark(y: .value("Goal", app.profile.dailyGoalMinutes))
                    .foregroundStyle(Color.sakuraPinkSoft)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                }
            }
            .frame(height: 150)
            .overlay {
                if data.allSatisfy({ $0.minutes < 1 }) {
                    Text("Watch a clip and your minutes show up here.")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.card.opacity(0.92), in: Capsule())
                }
            }
        }
        .padding(Spacing.l)
        .cardStyle()
    }

    private var mastery: some View {
        let total = max(words.count, 1)
        return VStack(alignment: .leading, spacing: Spacing.m) {
            Text("Mastery overview").font(.headline)
            Text(words.isEmpty
                 ? "Words you look up start as New, then move to Learning, Familiar and Known as you review them."
                 : "Each review moves a word one step closer to Known.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            GeometryReader { proxy in
                if words.isEmpty {
                    Capsule().fill(Color.primary.opacity(0.1))
                } else {
                    HStack(spacing: 2) {
                        Capsule().fill(Color.gray.opacity(0.45)).frame(width: proxy.size.width * CGFloat(newCount) / CGFloat(total))
                        Capsule().fill(Color.sakuraPinkSoft).frame(width: proxy.size.width * CGFloat(learning) / CGFloat(total))
                        Capsule().fill(Color.designOrange).frame(width: proxy.size.width * CGFloat(familiar) / CGFloat(total))
                        Capsule().fill(Color.spokenGreen)
                    }
                }
            }
            .frame(height: 12)
            .accessibilityHidden(true)
            HStack {
                MasteryStat(color: .gray.opacity(0.7), label: "New", value: newCount)
                MasteryStat(color: Color.sakuraPinkSoft, label: "Learning", value: learning)
                MasteryStat(color: .designOrange, label: "Familiar", value: familiar)
                MasteryStat(color: .spokenGreen, label: "Known", value: known)
            }
        }
        .padding(Spacing.l)
        .cardStyle()
    }

    private func scrollMarketingProfile(_ proxy: ScrollViewProxy) {
        if let marketingProfileAnchor {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(60))
                withAnimation(.easeInOut(duration: 0.35)) {
                    proxy.scrollTo(marketingProfileAnchor, anchor: .center)
                }
            }
            return
        }
        guard marketingScrollsToTheme else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(60))
            proxy.scrollTo("appearance", anchor: .top)
        }
    }

    private var settings: some View {
        VStack(spacing: 0) {
            settingsHeader("Appearance")
                .id("appearance")
            Menu {
                ForEach(AccentTheme.allCases) { theme in
                    Button(theme.title) { app.setTheme(theme) }
                }
            } label: {
                SettingsRowLabel(symbol: "paintpalette", title: "Theme", value: app.profile.theme.title)
            }
            Divider().padding(.leading, 52)
            Menu {
                ForEach(JojoScheme.allCases) { scheme in
                    Button(scheme.title) { app.setScheme(scheme) }
                }
            } label: {
                SettingsRowLabel(symbol: "circle.lefthalf.filled", title: "Appearance", value: app.profile.scheme.title)
            }
            Divider().padding(.leading, 52)
            GlowLevelRow()
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
            settingsToggle(symbol: "timer", title: "Daily progress bar",
                           isOn: Binding(
                            get: { !app.profile.hideDailyGoalBar },
                            set: { app.setHideDailyGoalBar(!$0) }
                           ))
            Divider().padding(.leading, 52)
            settingsToggle(symbol: "eye.slash", title: "Fade controls while watching",
                           isOn: Binding(
                            get: { app.profile.fadeWatchChrome },
                            set: { app.setFadeWatchChrome($0) }
                           ))
            Divider().padding(.leading, 52)

            settingsHeader("Playback")
            settingsToggle(symbol: "checkmark.message", title: "Pause for quick checks after videos",
                           isOn: $quickChecksEnabled)
            Divider().padding(.leading, 52)

            #if DEBUG
            settingsHeader("Debug · Marketing")
            SettingsRow(symbol: "play.circle", title: "1 · Sakura dark neon") {
                marketingScript = .coreSakuraDarkNeon
            }
            Divider().padding(.leading, 52)
            SettingsRow(symbol: "play.circle", title: "2 · Sakura dark") {
                marketingScript = .coreSakuraDarkOff
            }
            Divider().padding(.leading, 52)
            SettingsRow(symbol: "play.circle", title: "3 · Amber dark neon") {
                marketingScript = .coreAmberDarkNeon
            }
            Divider().padding(.leading, 52)
            SettingsRow(symbol: "play.circle", title: "4 · Amber dark") {
                marketingScript = .coreAmberDarkOff
            }
            Divider().padding(.leading, 52)
            SettingsRow(symbol: "film", title: "5 · Full app tour") {
                marketingScript = .fullTour
            }
            Divider().padding(.leading, 52)
            SettingsRow(symbol: "arrow.uturn.backward", title: "Reset demo data", tint: .red, iconTint: .red) { confirmReset = true }
            Divider().padding(.leading, 52)
            #endif

            SettingsRow(symbol: "lightbulb", title: "How Jojo works") { showHelp = true }
            Divider().padding(.leading, 52)
            if let onGiveFeedback {
                SettingsRow(symbol: "bubble.left.and.bubble.right", title: "Feedback") {
                    onGiveFeedback()
                }
                Divider().padding(.leading, 52)
            }

            settingsHeader("Account")
            SettingsRow(symbol: "target", title: "Daily goal", value: "\(app.profile.dailyGoalMinutes) min") { showGoalPicker = true }
            Divider().padding(.leading, 52)
            HStack(spacing: Spacing.m) {
                Image(systemName: "bell")
                    .foregroundStyle(Color.designOrangeDeep)
                    .frame(width: 28)
                Toggle("Study & review reminders", isOn: Binding(
                    get: { app.profile.remindersEnabled },
                    set: { value in Task { await app.setReminders(value) } }
                ))
                .tint(Color.designOrange)
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
            SettingsRow(symbol: "trash", title: "Delete All Data", tint: .red, iconTint: .red) { confirmDeleteAccount = true }
            Divider().padding(.leading, 52)

            settingsHeader("Legal & support")
            HStack(spacing: Spacing.m) {
                Image(systemName: "chart.bar.xaxis")
                    .foregroundStyle(Color.designOrangeDeep)
                    .frame(width: 28)
                AnalyticsConsentToggle()
            }
            .padding(.horizontal, Spacing.l)
            .frame(minHeight: 54)
            Divider().padding(.leading, 52)
            if let support = StoreConstants.supportURL {
                SettingsRow(symbol: "questionmark.circle", title: "Support") { openURL(support) }
                Divider().padding(.leading, 52)
            }
            if let privacy = StoreConstants.privacyURL {
                SettingsRow(symbol: "hand.raised", title: "Privacy Policy") { openURL(privacy) }
                Divider().padding(.leading, 52)
            }
            if let terms = StoreConstants.termsURL {
                SettingsRow(symbol: "doc.text", title: "Terms of Use") { openURL(terms) }
                Divider().padding(.leading, 52)
            }
            SettingsRow(symbol: "envelope", title: "Email support", value: StoreConstants.supportEmail) {
                if let mail = URL(string: "mailto:\(StoreConstants.supportEmail)?subject=Jojo%20Support") {
                    openURL(mail)
                }
            }
        }
        .cardStyle()
    }

    private func settingsHeader(_ title: String) -> some View {
            Text(title.uppercased())
            .font(.caption.weight(.bold))
            .foregroundStyle(Color.designOrange)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.l)
            .padding(.top, Spacing.m)
            .padding(.bottom, 4)
    }

    private func settingsToggle(symbol: String, title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: Spacing.m) {
            Image(systemName: symbol)
                .foregroundStyle(Color.designOrangeDeep)
                .frame(width: 28)
            Toggle(title, isOn: isOn).tint(Color.designOrange)
        }
        .padding(.horizontal, Spacing.l)
        .frame(minHeight: 54)
    }
}

/// Glow choices with a small word that breathes at the selected level.
private struct GlowLevelRow: View {
    @Environment(AppModel.self) private var app
    @State private var breath = false
    @State private var pickPulse = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: Spacing.m) {
                Image(systemName: "sparkles")
                    .foregroundStyle(Color.designOrangeDeep)
                    .frame(width: 28)
                Text("Text glow")
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                Text("光")
                    .font(JojoFont.jp(28, bold: true, relativeTo: .title2))
                    .foregroundStyle(LearningInk.dictionaryWord)
                    .textGlow(LearningInk.glow, level: app.profile.glow, boosted: breath || pickPulse)
                    .scaleEffect(pickPulse ? 1.12 : 1)
                    .animation(.spring(response: 0.28, dampingFraction: 0.55), value: pickPulse)
                    .accessibilityHidden(true)
            }
            HStack(spacing: 8) {
                ForEach(GlowLevel.allCases) { level in
                    let selected = app.profile.glow == level
                    Button {
                        guard app.profile.glow != level else { return }
                        Haptics.selection()
                        app.setGlowLevel(level)
                        pickPulse = true
                        Task {
                            try? await Task.sleep(for: .milliseconds(320))
                            pickPulse = false
                        }
                    } label: {
                        Text(level.title)
                            .font(.caption.weight(.bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity, minHeight: 32)
                            .foregroundStyle(selected ? Color.white : Color.primary)
                            .background(selected ? Color.sakuraButton : Color.fieldFill, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(level.title) glow")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.leading, 28 + Spacing.m)
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, 12)
        .id("text-glow")
        .animation(.easeInOut(duration: 0.35), value: app.profile.glow)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.15).repeatForever(autoreverses: true)) {
                breath = true
            }
        }
        .onChange(of: app.profile.glow) { _, _ in
            pickPulse = true
            Task {
                try? await Task.sleep(for: .milliseconds(320))
                pickPulse = false
            }
        }
    }
}

private struct SettingsRowLabel: View {
    let symbol: String
    let title: String
    var value: String?

    var body: some View {
        HStack(spacing: Spacing.m) {
            Image(systemName: symbol)
                .foregroundStyle(Color.designOrangeDeep)
                .frame(width: 28)
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
                Text(label)
                    .font(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
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
    var iconTint: Color = .designOrangeDeep
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.m) {
                Image(systemName: symbol)
                    .foregroundStyle(iconTint)
                    .frame(width: 28)
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
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.designOrange)
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

private struct MarketingScrollsToThemeKey: EnvironmentKey {
    static let defaultValue = false
}

private struct MarketingProfileAnchorKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    /// Marketing theme tour scrolls Profile to the Theme row.
    var marketingScrollsToTheme: Bool {
        get { self[MarketingScrollsToThemeKey.self] }
        set { self[MarketingScrollsToThemeKey.self] = newValue }
    }

    /// When set, the theme tour scrolls Profile to this row instead.
    var marketingProfileAnchor: String? {
        get { self[MarketingProfileAnchorKey.self] }
        set { self[MarketingProfileAnchorKey.self] = newValue }
    }
}

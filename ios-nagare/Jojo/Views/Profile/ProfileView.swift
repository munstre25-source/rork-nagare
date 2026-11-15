import SwiftUI
import SwiftData
import UIKit

/// Progress at a glance: streak, words, time, activity and achievements. Settings live behind the gear.
struct ProfileView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL
    @Environment(\.marketingScrollsToTheme) private var marketingScrollsToTheme
    @Environment(\.marketingProfileAnchor) private var marketingProfileAnchor
    @Query private var words: [SavedWord]
    @State private var reviewSession: ReviewSessionConfig?
    @State private var showSettings = false
    @State private var showStreak = false
    @State private var selectedStreakDate: Date?
    @State private var showHelp = false
    @State private var showLibrary = false
    @State private var showAchievements = false
    @State private var selectedAchievement: ProfileAchievement?
    @State private var showAchievementDetail = false
    @State private var showFeedbackBoard = false
    @State private var showFounderContact = false
    @State private var copiedFounderEmail = false
    private let founderEmail = "ralpayer@outlook.com"
    var onGiveFeedback: (() -> Void)? = nil
    var onAcquisitionSurvey: (() -> Void)? = nil
    var tabBarHidden: Binding<Bool> = .constant(false)

    private var known: Int { words.filter { $0.state == .known }.count }

    private var greeting: String {
        app.profile.firstName.isEmpty ? "Welcome back" : "Welcome back, \(app.profile.firstName)"
    }

    private var reviewPool: [SavedWord] {
        _ = app.reviewAvailabilityRevision
        return ReviewQueue.session(in: words)
    }

    private var showsInlineSettings: Bool {
        marketingScrollsToTheme || marketingProfileAnchor != nil
    }

    private var hasPushedDestination: Bool {
        showSettings || showHelp || showStreak || showLibrary || showAchievements
            || showAchievementDetail || showFeedbackBoard || showFounderContact
    }

    private var achievements: [ProfileAchievement] {
        ProfileAchievement.all(streak: app.currentStreak, words: words.count, known: known,
                               minutes: Int(app.totalWatchSeconds / 60))
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    topBar
                    HStack(spacing: Spacing.m) {
                        JojoMascotAvatar(size: 56)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(greeting)
                                .font(.title3.weight(.bold))
                                .lineLimit(2)
                                .minimumScaleFactor(0.8)
                            Text("Keep going. A more fluent you is ahead.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    HStack(spacing: 10) {
                        ProfileStat(symbol: "flame.fill", tint: .designOrange, value: "\(app.currentStreak)", caption: "day streak") {
                            showStreak = true
                        }
                        ProfileStat(symbol: "character.book.closed.fill", tint: .sakuraPink, value: "\(words.count)", caption: "words")
                        ProfileStat(symbol: "clock.fill", tint: .designOrangeDeep, value: watchText, caption: "watched")
                    }
                    hero
                    ActivityHeatmap(
                        log: app.watchLog,
                        goalMinutes: app.profile.dailyGoalMinutes,
                        studySecondsForDay: { app.studySeconds(for: $0) },
                        onSelectDay: { date in
                            selectedStreakDate = date
                            showStreak = true
                        }
                    )
                    achievementsCard
                    mastery
                    reviewButton
                    linksCard
                    if showsInlineSettings {
                        settings
                    }
                    Text("Jojo 流れ · Scroll, Listen, Flow into Japanese.")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
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
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showSettings) {
                SettingsView(onGiveFeedback: onGiveFeedback, onAcquisitionSurvey: onAcquisitionSurvey)
                    .toolbar(.hidden, for: .tabBar)
            }
            .navigationDestination(isPresented: $showHelp) {
                HelpView(onGiveFeedback: onGiveFeedback)
                    .toolbar(.visible, for: .navigationBar)
                    .toolbar(.hidden, for: .tabBar)
            }
            .navigationDestination(isPresented: $showStreak) {
                StreakView(initialDate: selectedStreakDate)
                    .toolbar(.hidden, for: .tabBar)
            }
            .navigationDestination(isPresented: $showLibrary) {
                LibraryView()
            }
            .navigationDestination(isPresented: $showAchievements) {
                AchievementsView(achievements: achievements)
            }
            .navigationDestination(isPresented: $showAchievementDetail) {
                if let selectedAchievement {
                    AchievementDetailView(item: selectedAchievement)
                }
            }
            .navigationDestination(isPresented: $showFeedbackBoard) {
                FeedbackBoardView(embeddedInNavigation: true)
            }
            .navigationDestination(isPresented: $showFounderContact) {
                founderContact
            }
        }
        .fullScreenCover(item: $reviewSession) { ReviewSessionView(config: $0) }
        .onAppear { app.hidesMainTabBar = hasPushedDestination }
        .onDisappear { app.hidesMainTabBar = false }
        .onChange(of: hasPushedDestination) { _, isPushed in
            app.hidesMainTabBar = isPushed
        }
    }

    private var topBar: some View {
        HStack(alignment: .center) {
            Text("Profile")
                .font(.system(size: 34, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer()
            Button {
                Haptics.selection()
                GuidanceCenter.shared.noteOpenedSettings()
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .background(Color.card, in: Circle())
                    .overlay(Circle().strokeBorder(Color.cardStroke))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
            .coachTarget(.settings)
        }
    }

    private var reviewButton: some View {
        VStack(spacing: 8) {
            Button {
                let keys = reviewPool.map(\.key)
                guard !keys.isEmpty else { return }
                Haptics.medium()
                reviewSession = ReviewSessionConfig(title: ReviewQueue.label(for: reviewPool), keys: keys)
            } label: {
                Label(ReviewQueue.label(for: reviewPool), systemImage: "rectangle.stack")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 48)
                    .background {
                        Capsule().fill(reviewPool.isEmpty ? Color.accentDisabled : Color.sakuraButton)
                    }
            }
            .buttonStyle(ChunkyPressStyle())
            .disabled(reviewPool.isEmpty)
            if words.isEmpty {
                Text("Reviews unlock after you tap your first word in the feed.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else if reviewPool.isEmpty {
                Text("Your saved words are marked Known. Find more in clips, or practice a deck in Vocab.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var achievementsCard: some View {
        let unlocked = achievements.filter(\.unlocked).count
        return VStack(alignment: .leading, spacing: Spacing.m) {
            HStack {
                Text("Achievements").font(.headline)
                Text("\(unlocked)/\(achievements.count)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("View all") {
                    Haptics.selection()
                    showAchievements = true
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.sakuraPink)
            }
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(achievements.sorted { $0.unlocked && !$1.unlocked }) { item in
                        Button {
                            selectedAchievement = item
                            showAchievementDetail = true
                        } label: {
                            AchievementBadge(item: item)
                                .frame(width: 92)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(Spacing.l)
        .cardStyle()
    }

    private var linksCard: some View {
        VStack(spacing: 0) {
            SettingsRow(symbol: "bubble.left.and.text.bubble.right", title: "Feedback Board") {
                showFeedbackBoard = true
            }
            Divider().padding(.leading, 52)
            SettingsRow(symbol: "books.vertical", title: "Library", value: "Saved · History") {
                showLibrary = true
            }
            Divider().padding(.leading, 52)
            SettingsRow(symbol: "questionmark.circle", title: "How Jojo works") {
                showHelp = true
            }
            Divider().padding(.leading, 52)
            SettingsRow(symbol: "envelope", title: "Contact the founder") {
                copiedFounderEmail = false
                showFounderContact = true
            }
        }
        .cardStyle()
    }

    private var founderContact: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                Text("Tell me what’s working, report a bug, or suggest something you’d like to see in Jojo.")
                    .foregroundStyle(.secondary)
                LabeledContent("Email", value: founderEmail)
                Button {
                    if let mail = URL(string: "mailto:\(founderEmail)?subject=Hi%20from%20Jojo") {
                        openURL(mail)
                    }
                } label: {
                    Label("Write an email", systemImage: "envelope")
                }
                .buttonStyle(PrimaryButtonStyle())
                Button {
                    UIPasteboard.general.string = founderEmail
                    copiedFounderEmail = true
                } label: {
                    Label(copiedFounderEmail ? "Email copied" : "Copy email address",
                          systemImage: copiedFounderEmail ? "checkmark" : "doc.on.doc")
                }
            }
            .padding(Spacing.l)
        }
        .background(Color.canvas)
        .navigationTitle("Contact the founder")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
    }

    private var watchText: String {
        let minutes = Int(app.totalWatchSeconds / 60)
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(known)")
                        .font(.system(size: 60, weight: .bold, design: .rounded))
                        .contentTransition(.numericText(value: Double(known)))
                        .animation(.snappy, value: known)
                    Text("Words you know").font(.subheadline).foregroundStyle(.secondary)
                    Text("Marked Known by you or through spaced reviews.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Text("Feed level")
                        .font(.caption2).foregroundStyle(.secondary)
                    Text(app.profile.readingLevel.difficulty.rawValue)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.immersionLevel?.title ?? "Dawn")
                        .font(.headline.weight(.bold))
                    Text(String(format: "%.1f hours of real Japanese", app.immersionHours))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let next = app.nextImmersionLevel {
                    Text(String(format: "%.1fh to %@", max(0, Double(next.hours) - app.immersionHours), next.title))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.studyAccent)
                }
            }

            if !app.seriesMastery().isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Series mastery")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    ForEach(app.seriesMastery(limit: 4)) { series in
                        HStack {
                            Text(series.channelName)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text("\(series.percent)%")
                                .font(.caption.weight(.bold))
                                .monospacedDigit()
                                .foregroundStyle(Color.studyAccent)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(series.channelName), \(series.percent) percent of seen words known")
                    }
                }
            }
        }
        .padding(Spacing.l)
        .cardStyle()
        .accessibilityElement(children: .contain)
    }

    private var mastery: some View {
        let total = max(words.count, 1)
        return VStack(alignment: .leading, spacing: Spacing.m) {
            Text("Mastery overview").font(.headline)
            Text("Review your saved words, or choose a familiarity mark in the word popup.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            GeometryReader { proxy in
                if words.isEmpty {
                    Capsule().fill(Color.primary.opacity(0.1))
                } else {
                    HStack(spacing: 0) {
                        ForEach(SRSState.allCases, id: \.rawValue) { state in
                            let count = words.filter { $0.state == state }.count
                            Rectangle().fill(LearningInk.mastery(state))
                                .frame(width: proxy.size.width * CGFloat(count) / CGFloat(total))
                        }
                    }
                    .clipShape(Capsule())
                }
            }
            .frame(height: 12)
            .accessibilityHidden(true)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 88))], alignment: .leading, spacing: 10) {
                ForEach(SRSState.allCases, id: \.rawValue) { state in
                    MasteryStat(color: LearningInk.mastery(state), label: state.title,
                                value: words.filter { $0.state == state }.count)
                }
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
        SettingsSectionsCard(onGiveFeedback: onGiveFeedback, onAcquisitionSurvey: onAcquisitionSurvey)
    }

}

/// Glow choices with a small word that breathes at the selected level.
struct GlowLevelRow: View {
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
            if app.profile.glow != .off {
                Toggle(isOn: Binding(
                    get: { app.profile.fullTextGlow },
                    set: { app.setFullTextGlow($0) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Full text glow")
                            .font(.subheadline.weight(.semibold))
                        Text(app.profile.fullTextGlow
                             ? "Glow every visible subtitle and reading."
                             : "Glow only the active or selected word.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(Color.sakuraButton)
                .padding(.leading, 28 + Spacing.m)
                .accessibilityHint("Switches between full subtitle glow and active-word-only glow")
            }
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, 12)
        .id("text-glow")
        .animation(.easeInOut(duration: 0.35), value: app.profile.glow)
        .animation(.easeInOut(duration: 0.25), value: app.profile.fullTextGlow)
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

struct SettingsRowLabel: View {
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

struct StatTile: View {
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

struct SettingsRow: View {
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
                ForEach([2, 5, 10, 15, 20], id: \.self) { minutes in
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
        case ..<4: "~1 clip · an easy start"
        case 4..<8: "~1 clip · a quick taste"
        case 8..<13: "~2 clips · steady habit"
        case 13..<18: "~3 clips · real momentum"
        case 18..<25: "~4-5 clips · serious flow"
        default: "~6+ clips · deep immersion"
        }
    }

    /// Rough planning estimate: about one new word per minute watched, 30 days a month.
    static func wordsPerMonth(_ minutes: Int) -> Int {
        let raw = Double(max(1, minutes)) * 30
        return Int((raw / 10).rounded()) * 10
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

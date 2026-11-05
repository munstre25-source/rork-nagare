import SwiftUI

// MARK: - Shared

/// Square-ish grid tile for multi-select questions on the night surface.
struct ChoiceTile: View {
    let symbol: String
    let title: String
    var detail: String? = nil
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(alignment: .top) {
                Image(systemName: symbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(isSelected ? .white : Color.sakuraPink)
                    .frame(width: 42, height: 42)
                    .background(isSelected ? Color.white.opacity(0.22) : Color.sakuraPink.opacity(0.14),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                Spacer(minLength: 0)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? .white : Color.white.opacity(0.3))
            }
            Spacer(minLength: 0)
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
            if let detail {
                Text(detail)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.white.opacity(isSelected ? 0.85 : 0.6))
            }
        }
        .padding(Spacing.m)
        .frame(maxWidth: .infinity, minHeight: 122, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(isSelected
                      ? AnyShapeStyle(LinearGradient(colors: [Color.jojoOrange, Color.jojoVermilion], startPoint: .topLeading, endPoint: .bottomTrailing))
                      : AnyShapeStyle(Color.white.opacity(0.08)))
        }
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
            .strokeBorder(isSelected ? .clear : Color.white.opacity(0.12), lineWidth: 1))
        .shadow(color: Color.jojoVermilion.opacity(isSelected ? 0.35 : 0), radius: 14, y: 6)
        .contentShape(Rectangle())
        .animation(.snappy, value: isSelected)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Pink pill used to read a plan value back to the learner.
struct PlanChip: View {
    let text: String
    var symbol: String = "sparkles"

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, Spacing.m)
            .padding(.vertical, Spacing.s)
            .background(Color.jojoVermilion.opacity(0.85), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.18)))
    }
}

private let twoColumns = [GridItem(.flexible(), spacing: Spacing.m), GridItem(.flexible(), spacing: Spacing.m)]

/// Scroll body + pinned primary button, the shape every plan step shares.
private struct StepScaffold<Content: View>: View {
    let buttonTitle: String
    var isEnabled: Bool = true
    let action: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: Spacing.l) {
            ScrollView {
                VStack(spacing: Spacing.l) { content }
                    .padding(.horizontal, Spacing.l)
                    .padding(.top, Spacing.l)
                    .padding(.bottom, Spacing.m)
            }
            .scrollIndicators(.hidden)
            Button(buttonTitle, action: action)
                .buttonStyle(PrimaryButtonStyle(isEnabled: isEnabled))
                .disabled(!isEnabled)
                .padding(.horizontal, Spacing.l)
                .padding(.bottom, Spacing.m)
        }
    }
}

// MARK: - Challenges

struct ChallengesStepView: View {
    let onContinue: () -> Void
    @State private var selected: Set<String> = []

    var body: some View {
        StepScaffold(buttonTitle: "Continue", isEnabled: !selected.isEmpty, action: save) {
            MascotCoach(message: "Everyone gets stuck somewhere. Tell me where, and I'll work around it.")
            OnboardingTitle(title: "What makes Japanese hard for you?", subtitle: "Pick all that apply.", accent: "hard")
            LazyVGrid(columns: twoColumns, spacing: Spacing.m) {
                ForEach(LearningChallenge.allCases) { c in
                    Button {
                        Haptics.selection()
                        if selected.contains(c.rawValue) { selected.remove(c.rawValue) } else { selected.insert(c.rawValue) }
                    } label: {
                        ChoiceTile(symbol: c.symbol, title: c.title, isSelected: selected.contains(c.rawValue))
                    }
                    .buttonStyle(PressableStyle())
                }
            }
        }
        .onAppear { selected = Set(OnboardingPrefs.challenges.map(\.rawValue)) }
    }

    private func save() {
        Haptics.light()
        let values = LearningChallenge.allCases.map(\.rawValue).filter { selected.contains($0) }
        UserDefaults.standard.set(values, forKey: OnboardingPrefs.challengesKey)
        track("onboarding_challenges_selected", props: ["values": values.joined(separator: ",")])
        onContinue()
    }
}

// MARK: - Comparison

/// Drill lesson vs real clips. The Jojo figure is measured from the catalog; both are labelled estimates.
struct ComparisonStepView: View {
    let onContinue: () -> Void
    @Environment(AppModel.self) private var app
    @State private var grow = false

    private static let drillCardsPerMinute = 5

    /// Average spoken words per minute across clips the app actually has.
    private var wordsPerMinute: Int {
        var words = 0
        var seconds = 0.0
        for clip in app.clips where clip.hasSupportedDuration {
            words += clip.lines.reduce(0) { $0 + $1.tokens.filter { !$0.isPunctuation }.count }
            seconds += clip.durationSec
        }
        guard seconds > 60, words > 0 else { return 90 }
        return max(30, Int((Double(words) / seconds * 60).rounded()))
    }

    var body: some View {
        let jojo = wordsPerMinute * 10
        let drill = Self.drillCardsPerMinute * 10
        let ratio = max(2, Int((Double(jojo) / Double(drill)).rounded()))
        StepScaffold(buttonTitle: "Continue", action: onContinue) {
            OnboardingTitle(title: "Hear real Japanese, not just drills", accent: "real Japanese")
            VStack(spacing: Spacing.l) {
                Text("Japanese you hear in 10 minutes")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.75))
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(alignment: .bottom, spacing: Spacing.xl) {
                    bar(label: "Flashcard drill", value: "~\(drill)", fraction: Double(drill) / Double(max(jojo, drill)), highlighted: false)
                    bar(label: "Jojo clips", value: "~\(jojo)", fraction: 1, highlighted: true)
                }
                .frame(height: 230)
                PlanChip(text: "About \(ratio)x more real speech", symbol: "waveform")
            }
            .padding(Spacing.l)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: Radius.sheet, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.sheet, style: .continuous).strokeBorder(Color.white.opacity(0.12)))

            HStack(alignment: .top, spacing: Spacing.m) {
                JojoMascot(height: 86, floats: false, pose: .phone)
                Text("Native speakers, real situations, and every word tappable. Your ear learns the rhythm drills can't teach.")
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Estimate. The Jojo figure is the average speaking rate across clips in the app (~\(wordsPerMinute) words a minute). The drill figure assumes about \(Self.drillCardsPerMinute) cards a minute.")
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear {
            withAnimation(.spring(response: 0.9, dampingFraction: 0.8).delay(0.2)) { grow = true }
        }
    }

    private func bar(label: String, value: String, fraction: Double, highlighted: Bool) -> some View {
        VStack(spacing: Spacing.s) {
            Text(value)
                .font(.system(.title2, design: .rounded, weight: .heavy))
                .foregroundStyle(highlighted ? Color.sakuraPink : Color.white.opacity(0.7))
                .opacity(grow ? 1 : 0)
            GeometryReader { geo in
                VStack {
                    Spacer(minLength: 0)
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(highlighted
                              ? AnyShapeStyle(LinearGradient(colors: [Color.sakuraPink, Color.jojoVermilion], startPoint: .top, endPoint: .bottom))
                              : AnyShapeStyle(Color.white.opacity(0.18)))
                        .frame(height: grow ? max(18, geo.size.height * fraction) : 6)
                }
            }
            Text(label)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(highlighted ? .white : Color.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Acquisition

struct AcquisitionStepView: View {
    let onContinue: () -> Void
    @Environment(AppModel.self) private var app
    @State private var selected: AcquisitionSource?
    @State private var task: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.m) {
                OnboardingTitle(title: "Where did you hear about Jojo?", subtitle: "It helps us reach more learners like you.", accent: "Jojo")
                    .padding(.bottom, Spacing.s)
                ForEach(AcquisitionSource.allCases) { source in
                    Button { choose(source) } label: {
                        OptionCard(title: source.title, symbol: source.symbol, isSelected: selected == source)
                    }
                    .buttonStyle(PressableStyle())
                    .disabled(task != nil)
                }
                Button("Skip") {
                    track("onboarding_acquisition_skipped")
                    onContinue()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.7))
                .frame(minHeight: 44)
            }
            .padding(.horizontal, Spacing.l)
            .padding(.vertical, Spacing.l)
        }
        .onAppear { selected = AcquisitionSource(rawValue: app.profile.acquisitionSource) }
        .onDisappear { task?.cancel() }
    }

    private func choose(_ source: AcquisitionSource) {
        Haptics.medium()
        selected = source
        app.profile.acquisitionSource = source.rawValue
        app.save()
        UserDefaults.standard.set([
            "source": source.rawValue,
            "detail": "",
            "appUserId": app.purchases.appUserId
        ], forKey: InsightsService.pendingAcquisitionKey)
        track("onboarding_acquisition_selected", props: ["source": source.rawValue])
        Task { await InsightsService.shared.flushPendingAcquisition() }
        task = Task {
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            onContinue()
        }
    }
}

// MARK: - Fluency goal

struct FluencyGoalStepView: View {
    let onContinue: () -> Void
    @Environment(AppModel.self) private var app
    @State private var months: Double = 12

    private var target: String { OnboardingPrefs.monthYear(OnboardingPrefs.targetDate(months: Int(months))) }

    var body: some View {
        StepScaffold(buttonTitle: "Set my goal", action: save) {
            MascotCoach(message: app.profile.firstName.isEmpty
                        ? "Pick a finish line. We'll pace the plan to it."
                        : "Pick a finish line, \(app.profile.firstName). We'll pace the plan to it.")
            OnboardingTitle(title: "When do you want to understand shows without English?", accent: "without English")
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.1), lineWidth: 18)
                Circle()
                    .trim(from: 0, to: months / 36)
                    .stroke(
                        AngularGradient(colors: [Color.sakuraPink, Color.jojoOrange, Color.jojoVermilion, Color.sakuraPink], center: .center),
                        style: StrokeStyle(lineWidth: 18, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.snappy, value: months)
                VStack(spacing: 0) {
                    Text("\(Int(months))")
                        .font(.system(size: 64, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                        .animation(.snappy, value: Int(months))
                    Text(Int(months) == 1 ? "month" : "months")
                        .font(.headline)
                        .foregroundStyle(Color.white.opacity(0.7))
                }
            }
            .frame(width: 210, height: 210)
            .padding(.vertical, Spacing.s)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(Int(months)) months")

            VStack(spacing: Spacing.s) {
                Slider(value: $months, in: 3...36, step: 1)
                    .tint(Color.sakuraPink)
                    .onChange(of: Int(months)) { _, _ in Haptics.selection() }
                    .accessibilityLabel("Months to goal")
                    .accessibilityValue("\(Int(months)) months")
                HStack {
                    Text("Ambitious").font(.caption).foregroundStyle(Color.white.opacity(0.5))
                    Spacer()
                    Text("Relaxed").font(.caption).foregroundStyle(Color.white.opacity(0.5))
                }
            }
            PlanChip(text: "Your target: \(target)", symbol: "flag.checkered")
                .contentTransition(.numericText())
                .animation(.snappy, value: target)
        }
        .onAppear {
            let saved = UserDefaults.standard.integer(forKey: OnboardingPrefs.goalMonthsKey)
            if saved > 0 { months = Double(min(36, max(3, saved))) }
        }
    }

    private func save() {
        Haptics.light()
        UserDefaults.standard.set(Int(months), forKey: OnboardingPrefs.goalMonthsKey)
        track("onboarding_fluency_goal", props: ["months": String(Int(months))])
        onContinue()
    }
}

// MARK: - Study window

struct StudyWindowStepView: View {
    let onContinue: () -> Void
    @Environment(AppModel.self) private var app
    @AppStorage("jojo.reminderHour") private var reminderHour = 19
    @State private var window: StudyWindow = .evening
    @State private var isAsking = false

    var body: some View {
        VStack(spacing: Spacing.l) {
            ScrollView {
                VStack(spacing: Spacing.l) {
                    OnboardingTitle(title: "When do you want to watch?", subtitle: "One gentle nudge for your \(app.profile.dailyGoalMinutes) minutes. Never spammy.", accent: "watch")
                    LazyVGrid(columns: twoColumns, spacing: Spacing.m) {
                        ForEach(StudyWindow.allCases) { w in
                            Button {
                                Haptics.selection()
                                window = w
                            } label: {
                                ChoiceTile(symbol: w.symbol, title: w.title, detail: w.range, isSelected: window == w)
                            }
                            .buttonStyle(PressableStyle())
                        }
                    }
                    notificationPreview
                }
                .padding(.horizontal, Spacing.l)
                .padding(.top, Spacing.l)
            }
            VStack(spacing: Spacing.xs) {
                Button(isAsking ? "One moment…" : "Remind me \(window.plural)") { commit(enable: true) }
                    .buttonStyle(PrimaryButtonStyle(isEnabled: !isAsking))
                    .disabled(isAsking)
                Button("Not now") { commit(enable: false) }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.7))
                    .frame(minHeight: 44)
                    .disabled(isAsking)
            }
            .padding(.horizontal, Spacing.l)
            .padding(.bottom, Spacing.s)
        }
        .onAppear { window = StudyWindow(rawValue: reminderHour) ?? .evening }
    }

    private var notificationPreview: some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            Image("JojoMascotHead")
                .resizable()
                .scaledToFill()
                .frame(width: 40, height: 40)
                .background(Color.jojoCream)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("JOJO").font(.caption2.weight(.bold)).tracking(0.6).foregroundStyle(Color.white.opacity(0.6))
                    Spacer()
                    Text(window.timeLabel).font(.caption2).foregroundStyle(Color.white.opacity(0.5))
                        .contentTransition(.numericText())
                }
                Text(app.profile.firstName.isEmpty ? "Your daily flow is waiting" : "\(app.profile.firstName), your daily flow is waiting")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text("A couple of clips keeps your streak alive.")
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.7))
            }
        }
        .padding(Spacing.m)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .environment(\.colorScheme, .dark)
        .animation(.snappy, value: window)
        .accessibilityElement(children: .combine)
    }

    private func commit(enable: Bool) {
        Haptics.light()
        reminderHour = window.rawValue
        app.profile.notificationsAsked = true
        guard enable else {
            app.save()
            track("onboarding_notifications_answer", props: ["granted": "0", "skipped": "1", "hour": String(window.rawValue)])
            onContinue()
            return
        }
        isAsking = true
        Task {
            await app.setReminders(true)
            isAsking = false
            track("onboarding_notifications_answer", props: ["granted": app.profile.remindersEnabled ? "1" : "0", "hour": String(window.rawValue)])
            onContinue()
        }
    }
}

// MARK: - Streak commitment

struct StreakCommitStepView: View {
    let onContinue: () -> Void
    @State private var days: Int?

    private let options: [(days: Int, label: String)] = [(7, "Good"), (14, "Great"), (30, "Incredible"), (50, "Unstoppable")]

    var body: some View {
        StepScaffold(buttonTitle: "Build my plan", isEnabled: days != nil, action: save) {
            ZStack(alignment: .bottomTrailing) {
                JojoMascot(height: 150, pose: .cheer)
                Image(systemName: "flame.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(LinearGradient(colors: [Color.jojoOrangeLight, Color.jojoVermilion], startPoint: .top, endPoint: .bottom))
                    .symbolEffect(.bounce, value: days)
                    .offset(x: 30, y: -6)
            }
            .frame(maxWidth: .infinity)
            OnboardingTitle(title: "Commit to a streak", subtitle: "Learners who pick a goal tend to come back. Choose yours.", accent: "streak")
            LazyVGrid(columns: twoColumns, spacing: Spacing.m) {
                ForEach(options, id: \.days) { option in
                    Button {
                        Haptics.medium()
                        days = option.days
                    } label: {
                        VStack(spacing: 4) {
                            Text("\(option.days)")
                                .font(.system(size: 40, weight: .heavy, design: .rounded))
                                .foregroundStyle(.white)
                            Text("days")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.white.opacity(0.75))
                            Text(option.label.uppercased())
                                .font(.caption2.weight(.heavy))
                                .tracking(1)
                                .foregroundStyle(days == option.days ? .white : Color.sakuraPink)
                                .padding(.top, 2)
                        }
                        .frame(maxWidth: .infinity, minHeight: 128)
                        .background {
                            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                                .fill(days == option.days
                                      ? AnyShapeStyle(LinearGradient(colors: [Color.jojoOrange, Color.jojoVermilion], startPoint: .topLeading, endPoint: .bottomTrailing))
                                      : AnyShapeStyle(Color.white.opacity(0.08)))
                        }
                        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                            .strokeBorder(days == option.days ? .clear : Color.white.opacity(0.12)))
                        .animation(.snappy, value: days)
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(days == option.days ? .isSelected : [])
                    }
                    .buttonStyle(PressableStyle())
                }
            }
        }
        .onAppear {
            let saved = UserDefaults.standard.integer(forKey: OnboardingPrefs.streakGoalKey)
            if saved > 0 { days = saved }
        }
    }

    private func save() {
        guard let days else { return }
        Haptics.success()
        UserDefaults.standard.set(days, forKey: OnboardingPrefs.streakGoalKey)
        track("onboarding_streak_commit", props: ["days": String(days)])
        onContinue()
    }
}

// MARK: - Building plan

struct BuildingPlanStepView: View {
    let onContinue: () -> Void
    @State private var progress: Double = 0
    @State private var doneCount = 0
    @State private var spin = false

    private let steps = [
        "Matching clips to your level",
        "Tuning your feed to your interests",
        "Setting your daily goal",
        "Preparing your first review deck"
    ]

    var body: some View {
        VStack(spacing: Spacing.xl) {
            Spacer(minLength: 0)
            ZStack {
                Circle().stroke(Color.white.opacity(0.1), lineWidth: 12)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(LinearGradient(colors: [Color.sakuraPink, Color.jojoVermilion], startPoint: .top, endPoint: .bottom),
                            style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                JojoMascot(height: 120, floats: true, pose: .book)
            }
            .frame(width: 200, height: 200)
            VStack(spacing: Spacing.s) {
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 44, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                Text("Building your plan…")
                    .font(.headline)
                    .foregroundStyle(Color.white.opacity(0.75))
            }
            VStack(alignment: .leading, spacing: Spacing.m) {
                ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                    HStack(spacing: Spacing.m) {
                        ZStack {
                            if i < doneCount {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.sakuraPink)
                                    .transition(.scale.combined(with: .opacity))
                            } else if i == doneCount {
                                ProgressView().tint(.white).controlSize(.small)
                            } else {
                                Image(systemName: "circle").foregroundStyle(Color.white.opacity(0.25))
                            }
                        }
                        .font(.title3)
                        .frame(width: 26)
                        Text(step)
                            .font(.body.weight(.medium))
                            .foregroundStyle(i <= doneCount ? .white : Color.white.opacity(0.45))
                    }
                }
            }
            .padding(Spacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: Radius.sheet, style: .continuous))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.l)
        .task { await run() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Building your plan")
    }

    private func run() async {
        let ticks = 40
        for t in 1...ticks {
            do { try await Task.sleep(for: .milliseconds(70)) } catch { return }
            withAnimation(.linear(duration: 0.07)) { progress = Double(t) / Double(ticks) }
            let reached = min(steps.count, t * steps.count / ticks)
            if reached > doneCount {
                Haptics.light()
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { doneCount = reached }
            }
        }
        Haptics.success()
        do { try await Task.sleep(for: .milliseconds(450)) } catch { return }
        onContinue()
    }
}

// MARK: - Plan ready

struct PlanReadyStepView: View {
    let onContinue: () -> Void
    @Environment(AppModel.self) private var app
    @AppStorage("jojo.reminderHour") private var reminderHour = 19
    @State private var appeared = false

    private var months: Int {
        let saved = UserDefaults.standard.integer(forKey: OnboardingPrefs.goalMonthsKey)
        return saved > 0 ? saved : 12
    }
    private var streakGoal: Int {
        let saved = UserDefaults.standard.integer(forKey: OnboardingPrefs.streakGoalKey)
        return saved > 0 ? saved : 7
    }
    private var level: SelfLevel? {
        (UserDefaults.standard.object(forKey: OnboardingPrefs.selfLevelKey) as? Int).flatMap(SelfLevel.init(rawValue:))
    }
    private var focus: String {
        let liked = app.profile.tastesLiked.compactMap { Taste(rawValue: $0)?.title }
        if !liked.isEmpty { return liked.prefix(2).joined(separator: " & ") }
        let why = app.profile.motivations.compactMap { Motivation(rawValue: $0)?.shortTitle }
        return why.first ?? "A mix of everything"
    }
    private var challenges: [LearningChallenge] {
        let picked = OnboardingPrefs.challenges
        return picked.isEmpty ? [.listening, .vocab, .kanji] : Array(picked.prefix(4))
    }
    private var title: String {
        app.profile.firstName.isEmpty ? "Your plan is ready" : "\(app.profile.firstName), your plan is ready"
    }

    var body: some View {
        StepScaffold(buttonTitle: "Let's go", action: {
            Haptics.medium()
            track("onboarding_plan_ready_continue")
            onContinue()
        }) {
            VStack(spacing: Spacing.m) {
                ZStack {
                    ConfettiBurst(count: 18, radius: 90)
                    JojoMascot(height: 130, pose: .cheer)
                }
                OnboardingTitle(title: title, accent: "ready")
                PlanChip(text: "Understand shows by \(OnboardingPrefs.monthYear(OnboardingPrefs.targetDate(months: months)))", symbol: "flag.checkered")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 12)

            VStack(spacing: 0) {
                planRow(symbol: "timer", title: "\(app.profile.dailyGoalMinutes) min a day", detail: DailyGoalOption.caption(app.profile.dailyGoalMinutes))
                divider
                planRow(symbol: "bell.fill",
                        title: app.profile.remindersEnabled ? "Reminder at \(String(format: "%02d:00", reminderHour))" : "No reminders",
                        detail: app.profile.remindersEnabled ? "One nudge, skipped once you hit your goal" : "Turn them on anytime in Settings")
                divider
                planRow(symbol: "flame.fill", title: "\(streakGoal)-day streak goal", detail: "Your streak starts with the first clip")
                divider
                planRow(symbol: "chart.bar.fill", title: level.map { "\($0.jlpt.rawValue) · \($0.title)" } ?? app.profile.readingLevel.title, detail: "Clips adjust as you improve")
                divider
                planRow(symbol: "heart.fill", title: focus, detail: "First in your feed")
            }
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: Radius.sheet, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.sheet, style: .continuous).strokeBorder(Color.white.opacity(0.12)))

            VStack(alignment: .leading, spacing: Spacing.m) {
                Text("How Jojo tackles what's hard")
                    .font(.headline)
                    .foregroundStyle(.white)
                ForEach(challenges) { c in
                    HStack(alignment: .top, spacing: Spacing.m) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.goodBackground)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.white.opacity(0.65))
                            Text(c.answer)
                                .font(.body.weight(.medium))
                                .foregroundStyle(.white)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) { appeared = true }
        }
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1).padding(.leading, 64)
    }

    private func planRow(symbol: String, title: String, detail: String) -> some View {
        HStack(spacing: Spacing.m) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.sakuraPink)
                .frame(width: 36, height: 36)
                .background(Color.sakuraPink.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(Color.white.opacity(0.6))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Trial reminder

/// Honest about reminders: only promises a ping when notifications are actually on.
struct TrialReminderStepView: View {
    let onContinue: () -> Void
    @Environment(AppModel.self) private var app
    @State private var ring = false
    @State private var isAsking = false

    var body: some View {
        VStack(spacing: Spacing.l) {
            Spacer(minLength: 0)
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [Color.sakuraPink.opacity(0.35), .clear], center: .center, startRadius: 10, endRadius: 120))
                    .frame(width: 240, height: 240)
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 84))
                    .foregroundStyle(Color.jojoVermilion, Color.jojoOrangeLight)
                    .rotationEffect(.degrees(ring ? 14 : -14), anchor: .top)
                    .animation(.easeInOut(duration: 0.16).repeatCount(7, autoreverses: true), value: ring)
            }
            OnboardingTitle(
                title: "No surprises. We'll remind you before your trial ends.",
                subtitle: app.profile.remindersEnabled
                    ? "If you start the free trial, Jojo sends a notification the day before it ends. Cancel anytime in Settings."
                    : "Turn on notifications and Jojo will ping you the day before a free trial ends. Cancel anytime in Settings.",
                accent: "remind you"
            )
            HStack(spacing: 0) {
                milestone("Today", "Full access", active: true)
                connector
                milestone("Day 2", "Reminder", active: false)
                connector
                milestone("Day 3", "Trial ends", active: false)
            }
            .padding(.top, Spacing.s)
            Spacer(minLength: 0)
            VStack(spacing: Spacing.xs) {
                if app.profile.remindersEnabled {
                    Button("Continue") { finish() }
                        .buttonStyle(PrimaryButtonStyle())
                } else {
                    Button(isAsking ? "One moment…" : "Turn on reminders") {
                        isAsking = true
                        Task {
                            await app.setReminders(true)
                            isAsking = false
                            track("onboarding_trial_reminder_enable", props: ["granted": app.profile.remindersEnabled ? "1" : "0"])
                            finish()
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle(isEnabled: !isAsking))
                    .disabled(isAsking)
                    Button("Continue without") { finish() }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.7))
                        .frame(minHeight: 44)
                }
            }
        }
        .padding(.horizontal, Spacing.l)
        .padding(.bottom, Spacing.m)
        .onAppear { ring = true }
    }

    private func finish() {
        Haptics.light()
        onContinue()
    }

    private var connector: some View {
        Rectangle().fill(Color.sakuraPink.opacity(0.5)).frame(height: 3).frame(maxWidth: .infinity).offset(y: -14)
    }

    private func milestone(_ title: String, _ detail: String, active: Bool) -> some View {
        VStack(spacing: 6) {
            Circle()
                .fill(active ? AnyShapeStyle(Color.sakuraButton) : AnyShapeStyle(Color.white.opacity(0.14)))
                .frame(width: 22, height: 22)
                .overlay(Circle().strokeBorder(Color.white.opacity(active ? 0 : 0.25)))
            Text(title).font(.subheadline.weight(.bold)).foregroundStyle(.white)
            Text(detail).font(.caption).foregroundStyle(Color.white.opacity(0.6))
        }
        .fixedSize()
        .accessibilityElement(children: .combine)
    }
}

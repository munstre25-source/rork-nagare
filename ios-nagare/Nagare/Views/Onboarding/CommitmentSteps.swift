import SwiftUI
import Charts

/// Step 8: social proof (sample content).
struct SocialProofStepView: View {
    let onContinue: () -> Void
    @State private var page: Int = 0

    private let quotes: [(String, String, String)] = [
        ("I finally caught a joke in an anime before the subtitles did. I actually yelled.", "Maya, 3 months in", "sparkles"),
        ("It doesn't feel like studying. I scroll on the train and my deck just grows.", "Daniel, commuter", "tram.fill"),
        ("Talked to my grandma in Japanese for the first time in years.", "Kenji, heritage learner", "heart.fill")
    ]

    var body: some View {
        VStack(spacing: Spacing.l) {
            ScrollView {
                VStack(spacing: Spacing.xl) {
                    OnboardingTitle(title: "Learners are flowing.", subtitle: "Real Japanese, a few minutes at a time.")
                    VStack(spacing: Spacing.s) {
                        HStack(spacing: 4) {
                            ForEach(0..<5, id: \.self) { _ in
                                Image(systemName: "star.fill").foregroundStyle(Color.nagareOrange)
                            }
                        }
                        .font(.title2)
                        Text("4.8").font(.system(size: 54, weight: .bold, design: .rounded)).foregroundStyle(.white)
                        Text("12,400+ ratings").font(.subheadline).foregroundStyle(.white.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Rated 4.8 out of 5, 12,400 ratings")

                    TabView(selection: $page) {
                        ForEach(Array(quotes.enumerated()), id: \.offset) { i, quote in
                            VStack(alignment: .leading, spacing: Spacing.m) {
                                Image(systemName: quote.2).font(.title2).foregroundStyle(Color.nagareOrange)
                                Text("“\(quote.0)”").font(.title3.weight(.medium)).foregroundStyle(.white)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(quote.1).font(.subheadline).foregroundStyle(.white.opacity(0.55))
                                Spacer(minLength: 0)
                            }
                            .padding(Spacing.xl)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.bgElevatedDark, in: RoundedRectangle(cornerRadius: Radius.sheet, style: .continuous))
                            .padding(.horizontal, 2)
                            .tag(i)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .always))
                    .frame(height: 250)
                    Text("Sample reviews for preview purposes.")
                        .font(.caption).foregroundStyle(.white.opacity(0.35))
                }
                .padding(.horizontal, Spacing.l)
                .padding(.top, Spacing.l)
            }
            Button("Continue") {
                Haptics.light()
                onContinue()
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, Spacing.l)
            .padding(.bottom, Spacing.m)
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3.5))
                withAnimation(.easeInOut) { page = (page + 1) % quotes.count }
            }
        }
    }
}

/// Step 9: daily minutes. Tap highlights orange and auto-advances.
struct DailyGoalStepView: View {
    let onContinue: () -> Void
    @Environment(AppModel.self) private var app
    @State private var selected: Int?

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.m) {
                OnboardingTitle(title: "How many minutes a day?", subtitle: "This sets your daily goal timer. Change it anytime.")
                    .padding(.bottom, Spacing.s)
                ForEach([5, 10, 15, 20], id: \.self) { minutes in
                    Button {
                        Haptics.medium()
                        selected = minutes
                        app.setDailyGoal(minutes)
                        track("onboarding_dailygoal_selected", props: ["minutes": String(minutes)])
                        Task {
                            try? await Task.sleep(for: .milliseconds(380))
                            onContinue()
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(minutes) min").font(.title2.weight(.bold)).foregroundStyle(.white)
                                Text(DailyGoalOption.caption(minutes)).font(.subheadline).foregroundStyle(.white.opacity(0.7))
                            }
                            Spacer()
                            if minutes == 10 {
                                Text("Popular").font(.caption.weight(.bold)).foregroundStyle(selected == minutes ? .white : Color.nagareOrange)
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .background((selected == minutes ? Color.white : Color.nagareOrange).opacity(0.18), in: Capsule())
                            }
                        }
                        .padding(Spacing.l)
                        .frame(minHeight: 80)
                        .background(selected == minutes ? Color.nagareOrange : Color.bgElevatedDark, in: RoundedRectangle(cornerRadius: 40, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 40, style: .continuous).strokeBorder(Color.hairlineDark))
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            .padding(.horizontal, Spacing.l)
            .padding(.top, Spacing.l)
        }
    }
}

/// Step 10: 30-day projection of words known.
struct JourneyStepView: View {
    let onContinue: () -> Void
    @Environment(AppModel.self) private var app
    @State private var reveal: Bool = false

    private struct Point: Identifiable {
        let day: Int
        let words: Double
        var id: Int { day }
    }

    private var points: [Point] {
        let perDay = Double(app.profile.dailyGoalMinutes) * 1.1
        return (0...30).map { d in
            Point(day: d, words: perDay * Double(d) * (1 - 0.25 * Double(d) / 30))
        }
    }

    var body: some View {
        VStack(spacing: Spacing.l) {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    OnboardingTitle(title: "Your Japanese Journey", subtitle: "At \(app.profile.dailyGoalMinutes) minutes a day, here's where 30 days can take you.")
                    VStack(alignment: .leading, spacing: Spacing.m) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("~\(Int(points.last?.words ?? 0))")
                                .font(.system(size: 48, weight: .bold, design: .rounded)).foregroundStyle(.white)
                            Text("words known by day 30").font(.subheadline).foregroundStyle(.white.opacity(0.6))
                        }
                        Chart(points) { p in
                            AreaMark(x: .value("Day", p.day), y: .value("Words", reveal ? p.words : 0))
                                .foregroundStyle(LinearGradient(colors: [Color.nagareOrange.opacity(0.4), .clear], startPoint: .top, endPoint: .bottom))
                                .interpolationMethod(.catmullRom)
                            LineMark(x: .value("Day", p.day), y: .value("Words", reveal ? p.words : 0))
                                .foregroundStyle(Color.nagareOrange)
                                .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                                .interpolationMethod(.catmullRom)
                        }
                        .chartXAxis {
                            AxisMarks(values: [0, 7, 14, 21, 30]) { v in
                                AxisValueLabel { Text("Day \(v.as(Int.self) ?? 0)").foregroundStyle(.white.opacity(0.5)) }
                            }
                        }
                        .chartYAxis(.hidden)
                        .frame(height: 180)
                        calendarStrip
                    }
                    .padding(Spacing.l)
                    .background(Color.bgElevatedDark, in: RoundedRectangle(cornerRadius: Radius.sheet, style: .continuous))
                    HStack(spacing: Spacing.m) {
                        Image(systemName: "flame.fill").font(.largeTitle).foregroundStyle(Color.nagareOrange)
                            .symbolEffect(.pulse, options: .repeating)
                        VStack(alignment: .leading) {
                            Text("Day 1 streak starts today").font(.headline).foregroundStyle(.white)
                            Text("Watch one clip to light it up.").font(.subheadline).foregroundStyle(.white.opacity(0.6))
                        }
                    }
                }
                .padding(.horizontal, Spacing.l)
                .padding(.top, Spacing.l)
            }
            Button("Continue") { onContinue() }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, Spacing.l)
                .padding(.bottom, Spacing.m)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.1).delay(0.2)) { reveal = true }
        }
    }

    private var calendarStrip: some View {
        HStack(spacing: 3) {
            ForEach(0..<30, id: \.self) { d in
                RoundedRectangle(cornerRadius: 2)
                    .fill(d == 0 ? Color.nagareOrange : Color.white.opacity(reveal ? 0.08 + Double(d) / 60 : 0.08))
                    .frame(height: 16)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Step 11: notification soft-ask. Only "Turn on" triggers the system prompt.
struct NotificationStepView: View {
    let onContinue: () -> Void
    @Environment(AppModel.self) private var app
    @State private var bell: Bool = false

    var body: some View {
        VStack(spacing: Spacing.l) {
            Spacer()
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 76))
                .foregroundStyle(.white, Color.nagareOrange)
                .rotationEffect(.degrees(bell ? 12 : -12))
                .animation(.easeInOut(duration: 0.18).repeatCount(5, autoreverses: true), value: bell)
            OnboardingTitle(title: "Protect your streak with a daily nudge?", subtitle: "One gentle reminder in the evening. Never spammy.")
                .multilineTextAlignment(.leading)
            VStack(alignment: .leading, spacing: Spacing.s) {
                HStack(spacing: Spacing.s) {
                    Image(systemName: "app.fill").foregroundStyle(Color.nagareOrange)
                    Text("NAGARE · 19:00").font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.6))
                }
                Text("Your daily flow is waiting").font(.headline).foregroundStyle(.white)
                Text("A couple of clips keeps your streak alive.").font(.subheadline).foregroundStyle(.white.opacity(0.7))
            }
            .padding(Spacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.bgElevatedDark, in: RoundedRectangle(cornerRadius: Radius.sheet, style: .continuous))
            Spacer()
            VStack(spacing: Spacing.xs) {
                Button("Turn on reminders") {
                    Haptics.light()
                    app.profile.notificationsAsked = true
                    Task {
                        await app.setReminders(true)
                        track("onboarding_notifications_answer", props: ["granted": app.profile.remindersEnabled ? "1" : "0"])
                        onContinue()
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                Button("Not now") {
                    track("onboarding_notifications_answer", props: ["granted": "skipped"])
                    onContinue()
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.6))
                .frame(minHeight: 44)
            }
        }
        .padding(.horizontal, Spacing.l)
        .padding(.bottom, Spacing.m)
        .onAppear { bell = true }
    }
}

/// Step 12: trial timeline.
struct TrialTimelineStepView: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: Spacing.l) {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    OnboardingTitle(title: "How your free trial works", subtitle: "Cancel anytime, right up to Day 7.")
                    VStack(alignment: .leading, spacing: 0) {
                        timelineRow(symbol: "lock.open.fill", title: "Today", detail: "Full access starts. Every clip, every word.", isFirst: true)
                        timelineRow(symbol: "bell.fill", title: "Day 5", detail: "We'll remind you before your trial ends.")
                        timelineRow(symbol: "star.fill", title: "Day 7", detail: "Trial ends. Subscription begins unless cancelled.", isLast: true)
                    }
                    VStack(alignment: .leading, spacing: Spacing.m) {
                        ForEach(["Unlimited clips", "Tap-to-understand on every word", "Automatic flashcards", "Full progress tracking"], id: \.self) { item in
                            Label {
                                Text(item).font(.body.weight(.medium)).foregroundStyle(.white)
                            } icon: {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.goodBackground)
                            }
                        }
                    }
                    .padding(Spacing.l)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.bgElevatedDark, in: RoundedRectangle(cornerRadius: Radius.sheet, style: .continuous))
                }
                .padding(.horizontal, Spacing.l)
                .padding(.top, Spacing.l)
            }
            Button("Continue") { onContinue() }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, Spacing.l)
                .padding(.bottom, Spacing.m)
        }
    }

    private func timelineRow(symbol: String, title: String, detail: String, isFirst: Bool = false, isLast: Bool = false) -> some View {
        HStack(alignment: .top, spacing: Spacing.l) {
            VStack(spacing: 0) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(isFirst ? Color.nagareOrange : Color.bgElevatedDark, in: Circle())
                if !isLast {
                    Rectangle()
                        .fill(LinearGradient(colors: [Color.nagareOrange, Color.nagareOrange.opacity(0.2)], startPoint: .top, endPoint: .bottom))
                        .frame(width: 3, height: 44)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).foregroundStyle(.white)
                Text(detail).font(.subheadline).foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 10)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Step 15: welcome beat.
struct WelcomeStepView: View {
    let onFinish: () -> Void
    @State private var appeared: Bool = false

    var body: some View {
        VStack(spacing: Spacing.l) {
            Spacer()
            NagareLogo(drawProgress: appeared ? 1 : 0, size: 0.8)
            Text("You're in. Let's go.")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(.white)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 12)
            Text("Your first clip is ready.")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.6))
                .opacity(appeared ? 1 : 0)
            Spacer()
        }
        .task {
            Haptics.success()
            withAnimation(.easeOut(duration: 0.8)) { appeared = true }
            track("onboarding_welcome_view")
            try? await Task.sleep(for: .milliseconds(1800))
            onFinish()
        }
    }
}

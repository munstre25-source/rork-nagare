import SwiftUI
import Charts

/// Daily minutes. Tap highlights orange and auto-advances.
struct DailyGoalStepView: View {
    let onContinue: () -> Void
    @Environment(AppModel.self) private var app
    @State private var selected: Int?

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.m) {
                MascotCoach(message: "I'll keep the sessions this short. Promise.")
                    .padding(.bottom, Spacing.xs)
                OnboardingTitle(title: "How many minutes a day?", subtitle: "This sets your daily goal timer. Change it anytime.")
                    .padding(.bottom, Spacing.s)
                ForEach([5, 10, 15, 20], id: \.self) { minutes in
                    goalCard(minutes)
                }
            }
            .padding(.horizontal, Spacing.l)
            .padding(.top, Spacing.l)
        }
    }

    private func goalCard(_ minutes: Int) -> some View {
        let isSelected = selected == minutes
        return Button {
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
                    Text("\(minutes) min")
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .foregroundStyle(isSelected ? Color.white : Color.jojoInk)
                    Text(DailyGoalOption.caption(minutes))
                        .font(.subheadline)
                        .foregroundStyle(isSelected ? Color.white.opacity(0.85) : Color.jojoInkSoft)
                }
                Spacer()
                if minutes == 10 {
                    Text("Popular")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(isSelected ? .white : Color.jojoVermilion)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            isSelected ? Color.white.opacity(0.22) : Color.sakuraPinkSoft,
                            in: Capsule()
                        )
                }
            }
            .padding(Spacing.l)
            .frame(minHeight: 80)
            .background {
                RoundedRectangle(cornerRadius: 40, style: .continuous)
                    .fill(
                        isSelected
                        ? AnyShapeStyle(LinearGradient(colors: [Color.jojoOrange, Color.jojoVermilion], startPoint: .topLeading, endPoint: .bottomTrailing))
                        : AnyShapeStyle(Color.jojoPaper)
                    )
            }
            .overlay(
                RoundedRectangle(cornerRadius: 40, style: .continuous)
                    .strokeBorder(isSelected ? .clear : Color.jojoPaperStroke, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(isSelected ? 0.18 : 0.06), radius: 12, y: 5)
            .animation(.snappy, value: isSelected)
        }
        .buttonStyle(PressableStyle())
    }
}

/// 30-day projection of words known.
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

    private var title: String {
        app.profile.firstName.isEmpty ? "Your Japanese journey" : "\(app.profile.firstName)'s Japanese journey"
    }

    private var journeySubtitle: String {
        let focus = profileFocus
        if focus.isEmpty {
            return "At \(app.profile.dailyGoalMinutes) minutes a day, here's where 30 days can take you."
        }
        return "At \(app.profile.dailyGoalMinutes) minutes a day in \(focus), here's where 30 days can take you."
    }

    private var profileFocus: String {
        let liked = app.profile.tastesLiked.compactMap { Taste(rawValue: $0)?.title }
        if !liked.isEmpty { return liked.prefix(2).joined(separator: " & ") }
        let genres = app.profile.motivations
            .compactMap { Motivation(rawValue: $0)?.categories.first?.displayName }
        var seen: [String] = []
        for genre in genres where !seen.contains(genre) { seen.append(genre) }
        return seen.prefix(2).joined(separator: " & ")
    }

    var body: some View {
        VStack(spacing: Spacing.l) {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    OnboardingTitle(title: title, subtitle: journeySubtitle)
                    VStack(alignment: .leading, spacing: Spacing.m) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("~\(Int(points.last?.words ?? 0))")
                                .font(.system(size: 48, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.jojoInk)
                            Text("words known by day 30")
                                .font(.subheadline)
                                .foregroundStyle(Color.jojoInkSoft)
                        }
                        Chart(points) { p in
                            AreaMark(x: .value("Day", p.day), y: .value("Words", reveal ? p.words : 0))
                                .foregroundStyle(Color.sakuraPinkSoft)
                                .interpolationMethod(.catmullRom)
                            LineMark(x: .value("Day", p.day), y: .value("Words", reveal ? p.words : 0))
                                .foregroundStyle(Color.jojoVermilion)
                                .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                                .interpolationMethod(.catmullRom)
                        }
                        .chartXAxis {
                            AxisMarks(values: [0, 7, 14, 21, 30]) { v in
                                AxisValueLabel { Text("Day \(v.as(Int.self) ?? 0)").foregroundStyle(Color.jojoInkFaint) }
                            }
                        }
                        .chartYAxis(.hidden)
                        .frame(height: 180)
                        calendarStrip
                    }
                    .brandCard()
                    HStack(spacing: Spacing.m) {
                        Image(systemName: "flame.fill")
                            .font(.largeTitle)
                            .foregroundStyle(Color.jojoVermilion)
                            .symbolEffect(.pulse, options: .repeating)
                        VStack(alignment: .leading) {
                            Text("Your streak starts with the first clip")
                                .font(.headline)
                                .foregroundStyle(Color.jojoInk)
                            Text("One clip is enough to light it up.")
                                .font(.subheadline)
                                .foregroundStyle(Color.jojoInkSoft)
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
                    .fill(d == 0 ? Color.sakuraPink : Color.sakuraPinkSoft)
                    .frame(height: 16)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Notification soft-ask. Only "Turn on" triggers the system prompt.
struct NotificationStepView: View {
    let onContinue: () -> Void
    @Environment(AppModel.self) private var app
    @State private var bell: Bool = false

    var body: some View {
        VStack(spacing: Spacing.l) {
            Spacer()
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 68))
                .foregroundStyle(Color.jojoVermilion, Color.jojoOrangeLight)
                .rotationEffect(.degrees(bell ? 12 : -12))
                .animation(.easeInOut(duration: 0.18).repeatCount(5, autoreverses: true), value: bell)
            OnboardingTitle(
                title: "Want a reminder for those \(app.profile.dailyGoalMinutes) minutes?",
                subtitle: "One gentle nudge in the evening. Never spammy."
            )
            notificationPreview
            Spacer()
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
                Haptics.selection()
                app.profile.notificationsAsked = true
                app.save()
                track("onboarding_notifications_answer", props: ["granted": "0"])
                onContinue()
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.white.opacity(0.8))
            .frame(minHeight: 44)
        }
        .padding(.horizontal, Spacing.l)
        .padding(.bottom, Spacing.m)
        .onAppear { bell = true }
    }

    /// Mimics a real iOS notification so the ask is concrete rather than abstract.
    private var notificationPreview: some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            Image("JojoMascotHead")
                .resizable()
                .scaledToFill()
                .frame(width: 42, height: 42)
                .background(Color.jojoCream)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("JOJO")
                        .font(.caption2.weight(.bold))
                        .tracking(0.6)
                        .foregroundStyle(Color.jojoInkSoft)
                    Spacer()
                    Text("19:00")
                        .font(.caption2)
                        .foregroundStyle(Color.jojoInkFaint)
                }
                Text(previewTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.jojoInk)
                Text("A couple of clips keeps your streak alive.")
                    .font(.subheadline)
                    .foregroundStyle(Color.jojoInkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .brandCard(radius: Radius.card)
        .accessibilityElement(children: .combine)
    }

    private var previewTitle: String {
        app.profile.firstName.isEmpty ? "Your daily flow is waiting" : "\(app.profile.firstName), your daily flow is waiting"
    }
}

/// Trial timeline.
struct TrialTimelineStepView: View {
    let onContinue: () -> Void

    @Environment(\.brandSurface) private var surface

    private var palette: BrandPalette { BrandPalette.resolve(surface) }
    private var isNight: Bool { surface == .night || surface == .cinema }

    var body: some View {
        VStack(spacing: Spacing.l) {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    OnboardingTitle(title: "How your free trial works", subtitle: "7 days free on Yearly. Cancel anytime before Day 7.")
                    VStack(alignment: .leading, spacing: 0) {
                        timelineRow(symbol: "lock.open.fill", title: "Today", detail: "Full Jojo Pro access starts immediately.", isFirst: true)
                        timelineRow(symbol: "bell.fill", title: "Day 6", detail: "We'll remind you before your trial ends.")
                        timelineRow(symbol: "star.fill", title: "Day 7", detail: "Trial ends. Yearly subscription begins unless cancelled.", isLast: true)
                    }
                    VStack(alignment: .leading, spacing: Spacing.m) {
                        ForEach(["Unlimited clips", "Tap-to-understand on every word", "Automatic flashcards", "Full progress tracking"], id: \.self) { item in
                            Label {
                                Text(item)
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(Color.jojoInk)
                                    .fixedSize(horizontal: false, vertical: true)
                            } icon: {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.goodBackground)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .brandCard()
                }
                .padding(.horizontal, Spacing.l)
                .padding(.top, Spacing.l)
                .padding(.bottom, Spacing.m)
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
                    .foregroundStyle(isFirst ? Color.white : (isNight ? Color.sakuraPink : Color.jojoVermilion))
                    .frame(width: 44, height: 44)
                    .background {
                        Circle().fill(
                            isFirst
                            ? AnyShapeStyle(LinearGradient(colors: [Color.jojoOrange, Color.jojoVermilion], startPoint: .top, endPoint: .bottom))
                            : AnyShapeStyle(isNight ? Color.white.opacity(0.14) : Color.jojoPaper)
                        )
                    }
                    .overlay {
                        if !isFirst {
                            Circle().strokeBorder(isNight ? Color.white.opacity(0.2) : Color.jojoPaperStroke, lineWidth: 1)
                        }
                    }
                if !isLast {
                    Rectangle()
                        .fill(Color.sakuraPink)
                        .frame(width: 3, height: 52)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(palette.title)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(palette.subtle)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 10)
            .padding(.bottom, isLast ? 0 : Spacing.m)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Welcome beat.
struct WelcomeStepView: View {
    let onFinish: () -> Void
    @Environment(AppModel.self) private var app
    @State private var appeared: Bool = false

    var body: some View {
        VStack(spacing: Spacing.l) {
            Spacer()
            JojoMascot(height: 220)
                .scaleEffect(appeared ? 1 : 0.85)
                .opacity(appeared ? 1 : 0)
            JojoWordmark(size: 34)
                .opacity(appeared ? 1 : 0)
            Text(headline)
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .foregroundStyle(Color.jojoInk)
                .multilineTextAlignment(.center)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 12)
            Text(firstClipLine)
                .font(.headline)
                .foregroundStyle(Color.jojoInkSoft)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .opacity(appeared ? 1 : 0)
            Spacer()
        }
        .padding(.horizontal, Spacing.l)
        .task {
            Haptics.success()
            withAnimation(.spring(response: 0.7, dampingFraction: 0.72)) { appeared = true }
            track("onboarding_welcome_view", props: ["first_clip": app.profile.firstClipId ?? "none"])
            try? await Task.sleep(for: .milliseconds(2400))
            onFinish()
        }
    }

    private var headline: String {
        app.profile.firstName.isEmpty ? "You're in. Let's go." : "You're in, \(app.profile.firstName). Let's go."
    }

    private var firstClipLine: String {
        guard let clip = app.recommendedClip() else { return "Your first clip is ready." }
        return "First up: \(clip.title)"
    }
}

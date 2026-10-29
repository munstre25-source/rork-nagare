import SwiftUI

/// "How Jojo works": the tour steps, a replay button, FAQ, feedback links and analytics choice.
struct HelpView: View {
    var onGiveFeedback: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var tipsReset = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("How Jojo works")
                        .font(.system(size: 30, weight: .bold))
                    Text("Watch real Japanese, tap what you don't know, and let review bring it back.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                loopCard

                Button {
                    Haptics.selection()
                    track("guide_replay_tapped")
                    dismiss()
                    GuidanceCenter.shared.replayTour()
                } label: {
                    Label("Replay the tour", systemImage: "play.circle.fill")
                }
                .buttonStyle(PrimaryButtonStyle())

                Button {
                    GuidanceCenter.shared.resetTips()
                    Haptics.success()
                    withAnimation(.snappy) { tipsReset = true }
                } label: {
                    Text(tipsReset ? "Tips will show again" : "Show tips again")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .foregroundStyle(Color.designOrange)
                .disabled(tipsReset)

                section("Questions") { faq }
                section("Feedback") { feedbackRows }
                section("Privacy") { privacyBlock }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .scrollIndicators(.hidden)
        .background(Color.studyPage.ignoresSafeArea())
        .navigationTitle("Help")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { track("help_viewed") }
    }

    // MARK: Loop

    private var loopCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(TourStep.allCases.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 14) {
                    Text("\(index + 1)")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(Color.designOrange, in: Circle())
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(step.eyebrow)
                            .font(.subheadline.weight(.semibold))
                        Text(step.message)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 12)
                .accessibilityElement(children: .combine)
                if index < TourStep.allCases.count - 1 {
                    Divider().padding(.leading, 40)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.cardStroke))
    }

    // MARK: FAQ

    private static let questions: [(String, String)] = [
        ("Where do my words go?",
         "Every word you tap is saved automatically in Vocab, with the sentence and clip you found it in. There's no save button."),
        ("How does review work?",
         "Cards come back right before you'd forget them. Tap Good if you knew it, Again if you didn't. A word counts as known once it stays with you for three weeks."),
        ("What does the number on a word mean?",
         "It's how many times you've met that word in clips. Words you meet often stick faster."),
        ("Can I learn from my own videos?",
         "Yes. In Explore, tap From your own video and paste a YouTube link. Jojo turns it into a lesson with tappable captions."),
        ("Do I need an account?",
         "No. Your progress lives on this phone. If you reinstall, Restore Purchases in Profile brings back your subscription."),
        ("How do I cancel?",
         "Profile → Manage Subscription, or iPhone Settings → your name → Subscriptions."),
    ]

    private var faq: some View {
        VStack(spacing: 0) {
            ForEach(Array(Self.questions.enumerated()), id: \.offset) { index, item in
                DisclosureGroup {
                    Text(item.1)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 10)
                } label: {
                    Text(item.0)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .frame(minHeight: 44, alignment: .leading)
                }
                .tint(Color.designOrange)
                if index < Self.questions.count - 1 { Divider() }
            }
        }
    }

    // MARK: Feedback

    @ViewBuilder
    private var feedbackRows: some View {
        if let onGiveFeedback {
            Button {
                onGiveFeedback()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .foregroundStyle(Color.designOrange)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Feature board and messages")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text("Vote on ideas, report a bug, or write to the team.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .frame(minHeight: 54)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Privacy

    private var privacyBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            AnalyticsConsentToggle()
            Text("Jojo counts things like screens opened, clips watched, and how long a session lasts, tied to a random ID for this install. Usage stats never include your name, email, voice recordings, or anything you type. Feedback you choose to send is stored separately so we can read it. Usage data is kept for about 13 months. Turning this off stops collection and clears anything not yet sent.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.designOrange)
            VStack(alignment: .leading, spacing: 0) { content() }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(Color.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.cardStroke))
        }
    }
}

/// "Share usage analytics" switch. Turning it off stops collection and purges the unsent queue.
struct AnalyticsConsentToggle: View {
    @AppStorage(AnalyticsConsent.key) private var enabled = true

    var body: some View {
        Toggle(isOn: Binding(
            get: { enabled },
            set: { value in
                enabled = value
                AnalyticsConsent.set(value)
                SessionTracker.shared.consentChanged()
                if value { track("analytics_enabled") }
            }
        )) {
            Text("Share usage analytics")
                .font(.subheadline.weight(.semibold))
        }
        .tint(Color.designOrange)
        .frame(minHeight: 44)
    }
}

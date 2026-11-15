import SwiftUI
import StoreKit

/// One-time "How's your Jojo experience so far?" check-in.
/// Positive → thanks, with an optional App Store rating. Negative → a short private note.
/// It shows once, whatever the answer (closing it counts too).
struct FeedbackFlowSheet: View {
    let onFinished: () -> Void

    @Environment(AppModel.self) private var app
    @Environment(\.requestReview) private var requestReview
    @Environment(\.dismiss) private var dismiss

    @State private var phase: Phase = .ask
    @State private var category: Category?
    @State private var message: String = ""
    @State private var anonymous = false
    @State private var isSubmitting = false
    @State private var errorText: String?
    @State private var answered = false
    @State private var markedShown = false
    @State private var showBoard = false
    @FocusState private var editorFocused: Bool

    private enum Phase { case ask, positive, negative, sent }

    /// Display names map to the server's private-inbox categories.
    enum Category: String, CaseIterable, Identifiable {
        case bug, content, learning, feature, performance, general
        var id: String { rawValue }
        var title: String {
            switch self {
            case .bug: "Bugs"
            case .content: "Content quality"
            case .learning: "Learning experience"
            case .feature: "Missing features"
            case .performance: "Performance"
            case .general: "Other"
            }
        }
        var symbol: String {
            switch self {
            case .bug: "ladybug"
            case .content: "film.stack"
            case .learning: "graduationcap"
            case .feature: "sparkles"
            case .performance: "gauge.with.dots.needle.33percent"
            case .general: "ellipsis.bubble"
            }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .ask: askPage
                case .positive: positivePage
                case .negative: negativePage
                case .sent: sentPage
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.canvas.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(phase == .ask ? "Not now" : "Close") { close() }
                }
            }
        }
        .presentationDetents(phase == .negative ? [.large] : [.medium, .large])
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showBoard) { FeedbackBoardView() }
        .onAppear {
            guard !markedShown else { return }
            markedShown = true
            app.markExperiencePromptShown()
        }
        .onDisappear {
            if !answered { track("feedback_prompt_dismissed") }
        }
    }

    // MARK: Ask

    private var askPage: some View {
        VStack(spacing: Spacing.l) {
            Spacer(minLength: Spacing.m)
            JojoMascot(height: 64, floats: false, pose: .book)
                .accessibilityHidden(true)
            VStack(spacing: 8) {
                Text("How's your Jojo experience so far?")
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                Text("One tap. It helps us decide what to fix and build next.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, Spacing.m)
            Spacer(minLength: Spacing.m)
            VStack(spacing: 12) {
                Button {
                    Task { await answerPositive() }
                } label: {
                    Label("I'm enjoying it", systemImage: "hand.thumbsup.fill")
                }
                .buttonStyle(PrimaryButtonStyle(isEnabled: !isSubmitting))
                .disabled(isSubmitting)

                Button {
                    answered = true
                    track("feedback_prompt_negative")
                    withAnimation(.snappy) { phase = .negative }
                } label: {
                    Text("Not great yet")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .foregroundStyle(.primary)
                        .background(Color.fieldFill, in: RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
                }
                .buttonStyle(PressableStyle())
            }
            .padding(.bottom, Spacing.l)
        }
        .padding(.horizontal, Spacing.l)
    }

    // MARK: Positive

    private var positivePage: some View {
        VStack(spacing: Spacing.l) {
            Spacer(minLength: Spacing.m)
            Image(systemName: "heart.fill")
                .font(.system(size: 44))
                .foregroundStyle(Color.jojoOrange)
                .symbolEffect(.bounce, value: phase)
                .accessibilityHidden(true)
            VStack(spacing: 8) {
                Text("That means a lot. Thank you.")
                    .font(.title3.weight(.bold))
                    .multilineTextAlignment(.center)
                Text("If you have a moment, a rating on the App Store helps other learners find Jojo.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, Spacing.m)
            Spacer(minLength: Spacing.m)
            VStack(spacing: 12) {
                if app.shouldOfferAppReview {
                    Button {
                        app.markAppReviewRequested()
                        track("review_request_tapped")
                        requestReview()
                    } label: {
                        Label("Rate Jojo", systemImage: "star.fill")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }

                Button(app.shouldOfferAppReview ? "Maybe later" : "Done") { close() }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(minHeight: 44)
            }
            .padding(.bottom, Spacing.l)
        }
        .padding(.horizontal, Spacing.l)
    }

    // MARK: Negative

    private var trimmedMessage: String {
        message.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSend: Bool { category != nil && !isSubmitting }

    private var negativePage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Sorry it's not there yet")
                        .font(.title3.weight(.bold))
                    Text("What's getting in the way? Pick the closest one.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                    ForEach(Category.allCases) { cat in
                        categoryChip(cat)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Tell us more (optional)")
                        .font(.subheadline.weight(.semibold))
                    ZStack(alignment: .topLeading) {
                        if message.isEmpty {
                            Text("What happened, or what would make Jojo better for you?")
                                .font(.body)
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 8)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: $message)
                            .focused($editorFocused)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 110)
                            .onChange(of: message) { _, new in
                                if new.count > 2000 { message = String(new.prefix(2000)) }
                            }
                    }
                    .padding(10)
                    .background(Color.fieldFill, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                    Text("Please don't include personal details like your name or email.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Toggle(isOn: $anonymous) {
                        Text("Send without my app ID")
                            .font(.subheadline.weight(.semibold))
                    }
                    .tint(Color.jojoOrange)
                    Text(anonymous
                         ? "We'll store the note without your app ID, so we won't be able to reply. App version and iOS version are still included to help reproduce bugs."
                         : "Your note is private. It's linked to a random app ID, never your name, so we can reply in Messages with Jojo.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let errorText {
                    Text(errorText)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                Button {
                    Task { await submitNegative() }
                } label: {
                    Text(isSubmitting ? "Sending…" : "Send feedback")
                }
                .buttonStyle(PrimaryButtonStyle(isEnabled: canSend))
                .disabled(!canSend)

                Button {
                    editorFocused = false
                    showBoard = true
                } label: {
                    Label("Vote on ideas from other learners", systemImage: "arrow.up.right")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .foregroundStyle(Color.jojoOrange)

                rateButton
            }
            .padding(Spacing.l)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func categoryChip(_ cat: Category) -> some View {
        let selected = category == cat
        return Button {
            Haptics.selection()
            category = cat
        } label: {
            HStack(spacing: 8) {
                Image(systemName: cat.symbol)
                    .font(.subheadline)
                    .frame(width: 20)
                Text(cat.title)
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(selected ? Color.white : Color.primary)
            .background(
                selected ? Color.jojoOrange : Color.fieldFill,
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// The App Store rating is offered whatever the answer was (guideline 5.6.1).
    @ViewBuilder
    private var rateButton: some View {
        if app.shouldOfferAppReview {
            Button {
                app.markAppReviewRequested()
                track("review_request_tapped")
                requestReview()
            } label: {
                Label("Rate Jojo on the App Store", systemImage: "star")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .foregroundStyle(.secondary)
        }
    }

    // MARK: Sent

    private var sentPage: some View {
        VStack(spacing: Spacing.l) {
            Spacer(minLength: Spacing.m)
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.jojoOrange)
                .accessibilityHidden(true)
            VStack(spacing: 8) {
                Text("Thanks. We read every note.")
                    .font(.title3.weight(.bold))
                    .multilineTextAlignment(.center)
                Text(anonymous
                     ? "Your feedback went straight to the team."
                     : "If we have a question, we'll reply in Messages with Jojo (Profile → Feedback).")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Spacer(minLength: Spacing.m)
            VStack(spacing: 8) {
                Button("Done") { close() }
                    .buttonStyle(PrimaryButtonStyle())
                rateButton
            }
            .padding(.bottom, Spacing.l)
        }
        .padding(.horizontal, Spacing.l)
    }

    // MARK: Actions

    private func close() {
        dismiss()
        onFinished()
    }

    @MainActor
    private func answerPositive() async {
        answered = true
        isSubmitting = true
        app.markFeedbackSubmitted()
        track("feedback_prompt_positive")
        // The thanks screen doesn't wait on the network.
        withAnimation(.snappy) { phase = .positive }
        isSubmitting = false
        let appUserId = app.purchases.appUserId
        Task.detached {
            _ = await InsightsService.shared.submitFeedback(
                enjoyed: true,
                category: nil,
                message: "",
                appUserId: appUserId,
                source: "experience_prompt"
            )
        }
    }

    @MainActor
    private func submitNegative() async {
        guard let category else { return }
        editorFocused = false
        errorText = nil
        isSubmitting = true
        defer { isSubmitting = false }
        let ok = await InsightsService.shared.submitFeedback(
            enjoyed: false,
            category: category.rawValue,
            message: trimmedMessage,
            appUserId: app.purchases.appUserId,
            source: "experience_prompt",
            anonymous: anonymous
        )
        guard ok else {
            errorText = "Couldn't send. Check your connection and try again."
            return
        }
        app.markFeedbackSubmitted()
        track("feedback_submitted", props: ["category": category.rawValue, "anonymous": anonymous ? "1" : "0"])
        withAnimation(.snappy) { phase = .sent }
    }
}

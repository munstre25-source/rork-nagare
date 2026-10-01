import SwiftUI

/// Soft prompt after a user turns off trial auto-renew (or cancels during trial).
struct CancellationSurveySheet: View {
    let onFinished: () -> Void

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var selected: CancelReason?
    @State private var otherText = ""
    @State private var isSubmitting = false
    @State private var errorText: String?
    @State private var phase: Phase = .ask

    private enum Phase { case ask, thanks }

    private enum CancelReason: String, CaseIterable, Identifiable {
        case price = "cancel_price"
        case time = "cancel_time"
        case content = "cancel_content"
        case hard = "cancel_hard"
        case curious = "cancel_curious"
        case other = "cancel_other"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .price: "Too expensive"
            case .time: "Not enough time to try"
            case .content: "Content wasn’t for me"
            case .hard: "App felt confusing"
            case .curious: "Just exploring the free trial"
            case .other: "Something else"
            }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .ask: askPage
                case .thanks: thanksPage
                }
            }
            .background(Color.canvas.ignoresSafeArea())
            .navigationTitle("Quick question")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not now") {
                        app.markCancellationSurveyHandled()
                        app.purchases.clearCancellationSurvey()
                        dismiss()
                        onFinished()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isSubmitting)
    }

    private var askPage: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            Text("Sorry to see you cancel")
                .font(.title2.weight(.bold))
            Text("You’re still in the trial window. Mind telling us why you turned off renewal? It helps us improve Jojo.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(spacing: Spacing.s) {
                ForEach(CancelReason.allCases) { reason in
                    Button {
                        Haptics.selection()
                        selected = reason
                    } label: {
                        HStack {
                            Image(systemName: selected == reason ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selected == reason ? Color.nagareOrange : .secondary)
                            Text(reason.title)
                                .foregroundStyle(.primary)
                            Spacer()
                        }
                        .padding(.horizontal, Spacing.m)
                        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                        .background(Color.fieldFill, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                                .strokeBorder(selected == reason ? Color.nagareOrange : .clear, lineWidth: 1.5)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            if selected == .other {
                TextField("Anything you’d like us to know?", text: $otherText, axis: .vertical)
                    .lineLimit(3...6)
                    .padding(Spacing.m)
                    .background(Color.fieldFill, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            }

            if let errorText {
                Text(errorText).font(.footnote).foregroundStyle(.red)
            }

            Spacer(minLength: 0)

            Button {
                Task { await submit() }
            } label: {
                Text(isSubmitting ? "Sending…" : "Send")
            }
            .buttonStyle(PrimaryButtonStyle(isEnabled: selected != nil && !isSubmitting))
            .disabled(selected == nil || isSubmitting)
        }
        .padding(Spacing.l)
    }

    private var thanksPage: some View {
        VStack(spacing: Spacing.l) {
            Spacer()
            Image(systemName: "heart.fill")
                .font(.system(size: 40))
                .foregroundStyle(Color.nagareOrange)
            Text("Thanks — that helps a lot.")
                .font(.title3.weight(.bold))
                .multilineTextAlignment(.center)
            Text("You keep Jojo Pro until the trial ends. You can turn renewal back on anytime in Manage Subscription.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
            Button("Done") {
                dismiss()
                onFinished()
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.bottom, Spacing.l)
        }
        .padding(.horizontal, Spacing.l)
    }

    @MainActor
    private func submit() async {
        guard let selected else { return }
        isSubmitting = true
        defer { isSubmitting = false }

        let detail = otherText.trimmingCharacters(in: .whitespacesAndNewlines)
        let message: String
        if selected == .other {
            message = detail.isEmpty ? selected.title : detail
        } else if detail.isEmpty {
            message = selected.title
        } else {
            message = "\(selected.title) — \(detail)"
        }

        let ok = await InsightsService.shared.submitFeedback(
            enjoyed: false,
            category: selected.rawValue,
            message: message,
            appUserId: app.purchases.appUserId
        )
        if !ok {
            // Still mark handled so we don't loop if offline; local analytics still fire.
            errorText = "Couldn't reach the server, but we'll keep this in mind."
        }
        app.markCancellationSurveyHandled()
        app.purchases.clearCancellationSurvey()
        track("cancellation_survey_submitted", props: ["reason": selected.rawValue])
        withAnimation(.snappy) { phase = .thanks }
    }
}

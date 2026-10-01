import SwiftUI
import StoreKit

/// Soft "Are you enjoying Jojo?" → yes (continue / review) or no (bug / feature / general).
struct FeedbackFlowSheet: View {
    let onFinished: () -> Void

    @Environment(AppModel.self) private var app
    @Environment(\.requestReview) private var requestReview
    @Environment(\.dismiss) private var dismiss

    @State private var phase: Phase = .enjoy
    @State private var category: FeedbackCategory = .feature
    @State private var message: String = ""
    @State private var isSubmitting = false
    @State private var errorText: String?

    private enum Phase {
        case enjoy, details, thanks
    }

    private enum FeedbackCategory: String, CaseIterable, Identifiable {
        case bug, feature, general
        var id: String { rawValue }
        var title: String {
            switch self {
            case .bug: "Bug"
            case .feature: "Feature"
            case .general: "General"
            }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .enjoy: enjoyPage
                case .details: detailsPage
                case .thanks: thanksPage
                }
            }
            .background(Color.canvas.ignoresSafeArea())
            .navigationTitle("Feedback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not now") {
                        app.deferFeedbackPrompt(days: 7)
                        dismiss()
                        onFinished()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var enjoyPage: some View {
        VStack(spacing: Spacing.l) {
            Spacer(minLength: Spacing.l)
            Image(systemName: "face.smiling")
                .font(.system(size: 44))
                .foregroundStyle(Color.jojoOrange)
            Text("Are you enjoying Jojo?")
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
            Text("A quick check-in helps us make the feed better.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.l)
            Spacer()
            Button {
                Task { await submitEnjoyingYes() }
            } label: {
                Text(isSubmitting ? "…" : "Yes, loving it")
            }
            .buttonStyle(PrimaryButtonStyle(isEnabled: !isSubmitting))
            .disabled(isSubmitting)
            Button {
                withAnimation(.snappy) { phase = .details }
            } label: {
                Text("Not really")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .foregroundStyle(.primary)
                    .background(Color.fieldFill, in: RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
            }
            .padding(.bottom, Spacing.l)
        }
        .padding(.horizontal, Spacing.l)
    }

    private var detailsPage: some View {
        VStack(spacing: Spacing.l) {
            Text("What went wrong — or what should we build?")
                .font(.title3.weight(.bold))
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: Spacing.s) {
                ForEach(FeedbackCategory.allCases) { cat in
                    Button {
                        Haptics.selection()
                        category = cat
                    } label: {
                        Text(cat.title)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14)
                            .frame(minHeight: 36)
                            .foregroundStyle(category == cat ? Color.white : Color.primary)
                            .background(
                                category == cat ? Color.jojoOrange : Color.fieldFill,
                                in: Capsule()
                            )
                    }
                }
                Spacer(minLength: 0)
            }

            TextField(
                "It would be cool if… / I ran into a bug when…",
                text: $message,
                axis: .vertical
            )
            .lineLimit(4...8)
            .padding(Spacing.m)
            .background(Color.fieldFill, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))

            if let errorText {
                Text(errorText).font(.footnote).foregroundStyle(.red)
            }

            Spacer(minLength: 0)

            Button {
                Task { await submitDetails() }
            } label: {
                Text(isSubmitting ? "Sending…" : "Give Feedback!")
            }
            .buttonStyle(PrimaryButtonStyle(isEnabled: !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSubmitting))
            .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)
        }
        .padding(Spacing.l)
    }

    private var thanksPage: some View {
        VStack(spacing: Spacing.l) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.jojoOrange)
            Text("Thanks — we read every note.")
                .font(.title3.weight(.bold))
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
    private func submitEnjoyingYes() async {
        isSubmitting = true
        defer { isSubmitting = false }
        _ = await InsightsService.shared.submitFeedback(
            enjoyed: true,
            category: nil,
            message: "Enjoying the app",
            appUserId: app.purchases.appUserId
        )
        app.completeFeedbackPrompt()
        track("feedback_enjoyed_yes")
        requestReview()
        phase = .thanks
    }

    @MainActor
    private func submitDetails() async {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        let ok = await InsightsService.shared.submitFeedback(
            enjoyed: false,
            category: category.rawValue,
            message: trimmed,
            appUserId: app.purchases.appUserId
        )
        if !ok {
            errorText = "Couldn't send — try again in a moment."
            return
        }
        app.completeFeedbackPrompt()
        track("feedback_enjoyed_no", props: ["category": category.rawValue])
        withAnimation { phase = .thanks }
    }
}

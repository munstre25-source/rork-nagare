import SwiftUI

/// "How did you find Jojo?" — acquisition analytics for Meta / organic mix.
struct AcquisitionStepView: View {
    let onContinue: () -> Void
    @Environment(AppModel.self) private var app
    @State private var selected: AcquisitionSource?
    @State private var otherDetail: String = ""
    @State private var isSubmitting = false

    var body: some View {
        VStack(spacing: Spacing.l) {
            ScrollView {
                VStack(spacing: Spacing.m) {
                    OnboardingTitle(
                        title: "How did you find Jojo?",
                        subtitle: "Helps us know what's working. Pick one."
                    )
                    .padding(.bottom, Spacing.s)
                    ForEach(AcquisitionSource.allCases) { source in
                        Button {
                            Haptics.selection()
                            selected = source
                            track("onboarding_acquisition_selected", props: ["source": source.rawValue])
                        } label: {
                            OptionCard(
                                title: source.title,
                                symbol: source.symbol,
                                isSelected: selected == source
                            )
                        }
                        .buttonStyle(PressableStyle())
                    }
                    if selected == .other {
                        TextField("Optional: where?", text: $otherDetail)
                            .textInputAutocapitalization(.sentences)
                            .tint(Color.jojoOrange)
                            .foregroundStyle(Color.jojoInk)
                            .padding(Spacing.m)
                            .background(Color.jojoPaper, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                                    .strokeBorder(Color.jojoPaperStroke, lineWidth: 1)
                            )
                    }
                }
                .padding(.horizontal, Spacing.l)
                .padding(.top, Spacing.l)
            }
            VStack(spacing: Spacing.xs) {
                Button {
                    Task { await submit() }
                } label: {
                    Text(isSubmitting ? "Saving…" : "Continue")
                }
                .buttonStyle(PrimaryButtonStyle(isEnabled: selected != nil && !isSubmitting))
                .disabled(selected == nil || isSubmitting)
                Button("Prefer not to say") {
                    Haptics.light()
                    onContinue()
                }
                .font(.subheadline)
                .foregroundStyle(Color.jojoInkSoft)
                .frame(minHeight: 44)
            }
            .padding(.horizontal, Spacing.l)
        }
        .onAppear {
            if let existing = AcquisitionSource(rawValue: app.profile.acquisitionSource) {
                selected = existing
            }
        }
    }

    @MainActor
    private func submit() async {
        guard let selected else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        Haptics.light()
        app.profile.acquisitionSource = selected.rawValue
        app.save()
        await InsightsService.shared.submitAcquisition(
            source: selected.rawValue,
            detail: selected == .other ? otherDetail : nil,
            appUserId: app.purchases.appUserId
        )
        onContinue()
    }
}

import SwiftUI

/// First thing we collect: what to call them. It sits up front rather than near the paywall
/// because every later screen — goal, journey, welcome — reads better with a name in it.
struct NameStepView: View {
    let onContinue: () -> Void

    @Environment(AppModel.self) private var app
    @State private var name: String = ""
    @FocusState private var focused: Bool

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(spacing: Spacing.l) {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    MascotCoach(message: "はじめまして! I'm Jojo. I'll be learning right alongside you.")
                    OnboardingTitle(
                        title: "What should I call you?",
                        subtitle: "A first name or nickname is plenty. It never leaves your device."
                    )
                    TextField("Your name", text: $name)
                        .font(.system(.title2, design: .rounded, weight: .semibold))
                        .foregroundStyle(Color.jojoInk)
                        .tint(Color.jojoOrange)
                        .textInputAutocapitalization(.words)
                        .textContentType(.givenName)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .focused($focused)
                        .onSubmit { save(trimmed) }
                        .padding(.horizontal, Spacing.l)
                        .frame(minHeight: 64)
                        .background(Color.jojoPaper, in: RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                                .strokeBorder(
                                    trimmed.isEmpty ? Color.jojoPaperStroke : Color.jojoOrange,
                                    lineWidth: trimmed.isEmpty ? 1 : 2
                                )
                        )
                        .animation(.snappy, value: trimmed.isEmpty)
                    greeting
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: trimmed.isEmpty)
                }
                .padding(.horizontal, Spacing.l)
                .padding(.top, Spacing.l)
            }
            .scrollIndicators(.hidden)

            Button("Continue") { save(trimmed) }
                .buttonStyle(PrimaryButtonStyle(isEnabled: !trimmed.isEmpty))
                .disabled(trimmed.isEmpty)
                .padding(.horizontal, Spacing.l)
        }
        .onAppear {
            name = app.profile.firstName
            // Let the step's slide-in settle before the keyboard reflows the layout.
            Task {
                try? await Task.sleep(for: .milliseconds(450))
                focused = true
            }
        }
    }

    @ViewBuilder
    private var greeting: some View {
        if trimmed.isEmpty {
            Color.clear.frame(height: 1)
        } else {
            HStack(spacing: Spacing.s) {
                Blossom(size: 16)
                Text("よろしくね、\(trimmed)!")
                    .font(JojoFont.jp(18, bold: true, relativeTo: .title3))
                    .foregroundStyle(Color.jojoVermilion)
            }
            .transition(.opacity.combined(with: .move(edge: .leading)))
        }
    }

    private func save(_ value: String) {
        Haptics.light()
        focused = false
        app.setFirstName(value)
        track("onboarding_name_captured", props: ["provided": value.isEmpty ? "0" : "1"])
        onContinue()
    }
}

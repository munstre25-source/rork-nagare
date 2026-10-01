import SwiftUI

/// Step 7: the centerpiece. Reuses the real Feed components on one looping line, fully offline.
struct DemoStepView: View {
    let onContinue: () -> Void
    @Environment(AppModel.self) private var app
    @State private var coordinator = PlaybackCoordinator()
    @State private var lookup = WordLookupController()
    @State private var clip: Clip?
    @State private var pulse: Bool = false
    @State private var didTap: Bool = false

    private var targetIndex: Int? {
        guard let line = clip?.lines.first else { return nil }
        return line.tokens.firstIndex { $0.containsKanji && $0.tappable } ?? line.tokens.firstIndex { $0.tappable }
    }

    var body: some View {
        VStack(spacing: 0) {
            OnboardingTitle(
                title: didTap ? "That's it. That's the whole app." : "Try it. Tap the glowing word.",
                subtitle: didTap ? "It's saved to your flashcards already. No button needed." : "This is a real clip from your feed, looping one line."
            )
            .padding(.horizontal, Spacing.l)
            .padding(.vertical, Spacing.m)
            .animation(.snappy, value: didTap)

            if let clip {
                ClipStageView(
                    clip: clip,
                    videoAspect: 16 / 10,
                    onlyCurrentLine: true,
                    pulseTokenIndex: didTap ? nil : targetIndex,
                    isPulsing: pulse,
                    tooltip: didTap ? nil : "Tap this word 👆",
                    showsRail: false,
                    onActivate: { coordinator.activate(clip, startLine: 0, loopLine: true) }
                )
                .clipShape(.rect(cornerRadius: Radius.sheet, style: .continuous))
                .padding(.horizontal, Spacing.s)
            }
            Spacer(minLength: Spacing.m)
            if didTap {
                Button("Continue") {
                    lookup.dismiss()
                    coordinator.stop()
                    onContinue()
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, Spacing.l)
                .padding(.bottom, Spacing.m)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .environment(coordinator)
        .environment(lookup)
        .onAppear {
            lookup.offlineOnly = true
            let chosen = app.recommendedClip(preferShort: true) ?? app.clips.first
            clip = chosen
            if let chosen { coordinator.activate(chosen, startLine: 0, loopLine: true) }
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { pulse = true }
        }
        .onDisappear { coordinator.stop() }
        .onChange(of: lookup.tapPulse) { _, _ in
            guard !didTap else { return }
            track("onboarding_demo_word_tapped", props: ["word": lookup.selection?.token.surface ?? ""])
            Task {
                try? await Task.sleep(for: .milliseconds(500))
                withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { didTap = true }
            }
        }
    }
}

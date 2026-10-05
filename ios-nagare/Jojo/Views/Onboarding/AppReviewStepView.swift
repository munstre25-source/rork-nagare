import SwiftUI
import StoreKit

/// App Store review ask. Shown right after the live feed demo, once the learner
/// has scrolled a clip and opened the dictionary card.
struct AppReviewStepView: View {
    let onContinue: () -> Void

    @Environment(AppModel.self) private var app
    @Environment(\.brandSurface) private var surface
    @Environment(\.requestReview) private var requestReview
    @State private var appeared = false
    @State private var starsLit = 0
    /// True after we've asked the system for a review — stay on this screen so the
    /// sheet lands here, not on the next (acquisition) step. Apple's dialog is async
    /// and may take a second or two to appear; navigating away races it.
    @State private var didAskReview = false

    private var palette: BrandPalette { BrandPalette.resolve(surface) }
    private var isNight: Bool { surface == .night || surface == .cinema }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: Spacing.l) {
                    JojoWordmark(size: 42)
                        .padding(.top, Spacing.m)

                    VStack(spacing: Spacing.s) {
                        Text(headline)
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(palette.title)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Help us grow with a quick rating.\nJojo loves your feedback!")
                            .font(.body)
                            .foregroundStyle(palette.subtle)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, Spacing.l)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 8)

                    ratingRow
                        .padding(.top, Spacing.s)
                        .opacity(appeared ? 1 : 0)

                    JojoMascot(height: 280)
                        .scaleEffect(appeared ? 1 : 0.94)
                        .opacity(appeared ? 1 : 0)
                        .accessibilityLabel("Jojo the panda, learning Japanese with you")
                }
                .padding(.bottom, 140)
            }

            VStack(spacing: Spacing.m) {
                Button {
                    if didAskReview {
                        Haptics.light()
                        onContinue()
                    } else {
                        askForReview()
                    }
                } label: {
                    Text(didAskReview ? "Continue" : "Rate Jojo")
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            .padding(.horizontal, Spacing.l)
            .padding(.bottom, Spacing.l)
            .background(
                LinearGradient(
                    colors: isNight
                        ? [Color.nightIndigo.opacity(0), Color.nightIndigo.opacity(0.92)]
                        : [Color.jojoCreamDeep.opacity(0), Color.jojoCreamDeep],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 120)
                .allowsHitTesting(false),
                alignment: .top
            )
        }
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.86)) { appeared = true }
            animateStars()
        }
    }

    private var headline: String {
        app.profile.firstName.isEmpty
        ? "How is Jojo doing?"
        : "How is Jojo doing, \(app.profile.firstName)?"
    }

    private var ratingRow: some View {
        HStack(spacing: Spacing.m) {
            Image(systemName: "laurel.leading")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Color(hex: "#E8B84A"))
            HStack(spacing: 6) {
                ForEach(0..<5, id: \.self) { index in
                    Image(systemName: "star.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(index < starsLit ? Color.jojoGold : Color.white.opacity(isNight ? 0.28 : 0.35))
                        .scaleEffect(index < starsLit ? 1 : 0.86)
                        .animation(.spring(response: 0.35, dampingFraction: 0.65).delay(Double(index) * 0.05), value: starsLit)
                }
            }
            Image(systemName: "laurel.trailing")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Color(hex: "#E8B84A"))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Five star rating")
    }

    private func animateStars() {
        Task { @MainActor in
            for i in 1...5 {
                try? await Task.sleep(for: .milliseconds(90))
                starsLit = i
                Haptics.selection()
            }
        }
    }

    private func askForReview() {
        Haptics.medium()
        track("onboarding_appreview_rated")
        // Stay on this screen. `requestReview()` is fire-and-forget and the system
        // sheet often appears after a delay — advancing immediately dropped it onto
        // the acquisition questionnaire instead.
        requestReview()
        withAnimation(.snappy) { didAskReview = true }
    }
}

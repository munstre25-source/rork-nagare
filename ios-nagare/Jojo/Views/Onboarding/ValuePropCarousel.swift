import SwiftUI

/// Steps 1-3: value-prop carousel. Page one is a static feed preview (no live clip —
/// real video starts after the paywall); page two teaches the tap gesture; page three shows auto flashcards.
struct ValuePropCarousel: View {
    @Binding var step: OnboardingStep
    let onContinue: () -> Void
    @Environment(AppModel.self) private var app

    @State private var didTapWord: Bool = false

    private let pages: [OnboardingStep] = [.valueCaptions, .valueTap, .valueFlashcards]

    var body: some View {
        VStack(spacing: Spacing.l) {
            TabView(selection: Binding(get: { pages.contains(step) ? step : .valueCaptions }, set: { step = $0 })) {
                page(
                    title: "Learn Japanese by doomscrolling.",
                    accent: "doomscrolling",
                    subtitle: "Real clips from anime, streams, cafés and street interviews — in your feed."
                ) {
                    feedPreviewPoster
                }
                .tag(OnboardingStep.valueCaptions)

                page(
                    title: didTapWord ? "That's the whole gesture." : "Tap any word. Understand instantly.",
                    accent: didTapWord ? nil : "Tap any word",
                    subtitle: didTapWord
                    ? "Reading, meaning and grammar — and the clip never loses its place."
                    : "Go ahead: tap 天気 in the line below."
                ) {
                    tapIllustration
                }
                .tag(OnboardingStep.valueTap)

                page(
                    title: "Flashcards build themselves.",
                    accent: "Flashcards",
                    subtitle: "Every word you tap becomes a card with the real sentence and clip it came from."
                ) {
                    VStack(spacing: Spacing.m) {
                        MockReviewCard(clip: app.clip(id: "immersion-konbini-sayaka") ?? app.clips.first)
                        JojoMascot(height: 100, pose: .cheer)
                            .accessibilityHidden(true)
                    }
                }
                .tag(OnboardingStep.valueFlashcards)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            HStack(spacing: 8) {
                ForEach(pages, id: \.self) { p in
                    Capsule()
                        .fill(p == step ? Color.sakuraPink : Color.white.opacity(0.28))
                        .frame(width: p == step ? 22 : 8, height: 8)
                        .animation(.snappy, value: step)
                }
            }
            .accessibilityHidden(true)

            Button(step == .valueFlashcards ? "Continue" : "Next") {
                Haptics.light()
                if step == .valueFlashcards {
                    onContinue()
                } else if let index = pages.firstIndex(of: step), let next = pages[safe: index + 1] {
                    withAnimation(.snappy) { step = next }
                } else {
                    withAnimation(.snappy) { step = .valueTap }
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, Spacing.l)
            .padding(.bottom, Spacing.m)
        }
    }

    /// Static phone-frame poster — no interactive / looping clip before paywall.
    private var feedPreviewPoster: some View {
        let clip = app.recommendedClip() ?? app.clips.first
        return VStack(spacing: Spacing.m) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.black.opacity(0.55))
                if let clip {
                    GradientPoster(clip: clip)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .padding(10)
                    VStack(spacing: Spacing.s) {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(.white.opacity(0.92))
                        Text(clip.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .padding(.horizontal, Spacing.l)
                    }
                }
            }
            .frame(height: 280)
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
            )
            Text("Clips unlock when you start Jojo Pro.")
                .font(.footnote.weight(.medium))
                .foregroundStyle(Color.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Feed preview. Clips unlock when you start Jojo Pro.")
    }

    private func page<Content: View>(
        title: String,
        accent: String?,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                OnboardingTitle(title: title, subtitle: subtitle, accent: accent)
                    .animation(.snappy, value: didTapWord)
                content()
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, Spacing.l)
            .padding(.top, Spacing.l)
            .padding(.bottom, Spacing.m)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: Page 2 — hands-on tap

    private var tapIllustration: some View {
        VStack(spacing: Spacing.m) {
            VStack(alignment: .leading, spacing: Spacing.m) {
                StaticSentence(
                    words: [
                        .init(surface: "今日", furigana: "きょう", romaji: "kyou", tappable: false),
                        .init(surface: "は", romaji: "wa", tappable: false),
                        .init(surface: "天気", furigana: "てんき", romaji: "tenki", state: didTapWord ? .selected : .normal),
                        .init(surface: "が", romaji: "ga", tappable: false),
                        .init(surface: "いい", romaji: "ii", tappable: false),
                        .init(surface: "です", romaji: "desu", tappable: false),
                        .init(surface: "ね", romaji: "ne", tappable: false)
                    ],
                    size: 26,
                    onTapWord: { _ in tapWord() }
                )
                if !didTapWord {
                    TapHint()
                }
            }
            .padding(Spacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(hex: "#121212").opacity(0.85), in: RoundedRectangle(cornerRadius: Radius.sheet, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sheet, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.35), radius: 20, y: 10)

            if didTapWord {
                MockPopupCard()
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.9, anchor: .top).combined(with: .opacity).combined(with: .offset(y: -16)),
                        removal: .opacity
                    ))
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.78), value: didTapWord)
    }

    private func tapWord() {
        guard !didTapWord else { return }
        Haptics.medium()
        track("onboarding_valueprop_word_tapped")
        didTapWord = true
    }
}

/// Pulsing "tap here" affordance pointing at the underlined word.
private struct TapHint: View {
    @State private var pulse: Bool = false

    var body: some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: "hand.tap.fill")
                .font(.subheadline.weight(.bold))
                .scaleEffect(pulse ? 1.14 : 0.92)
            Text("Tap the underlined word")
                .font(.subheadline.weight(.semibold))
        }
        .foregroundStyle(Color.sakuraPink)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true)) { pulse = true }
        }
        .accessibilityHidden(true)
    }
}

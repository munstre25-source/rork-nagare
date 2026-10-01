import SwiftUI

/// Steps 1-3: value-prop carousel with progress dots. Page two is hands-on — the learner
/// taps a real word and the dictionary card springs in, so the core gesture is taught
/// before any question is asked.
struct ValuePropCarousel: View {
    @Binding var step: OnboardingStep
    let onContinue: () -> Void
    @Environment(AppModel.self) private var app

    @State private var didTapWord: Bool = false

    private let pages: [OnboardingStep] = [.valueCaptions, .valueTap, .valueFlashcards]

    var body: some View {
        VStack(spacing: Spacing.l) {
            TabView(selection: Binding(get: { pages.contains(step) ? step : .valueCaptions }, set: { step = $0 })) {
                page(title: "Real Japanese.\nNot textbook Japanese.",
                     subtitle: "Scroll short clips from anime, streams, cafés and street interviews.") {
                    captionsIllustration
                }
                .tag(OnboardingStep.valueCaptions)
                page(title: didTapWord ? "That's the whole gesture." : "Tap any word.\nUnderstand instantly.",
                     subtitle: didTapWord
                     ? "Reading, meaning and grammar — and the clip never loses its place."
                     : "Go ahead: tap 天気 in the line below.") {
                    tapIllustration
                }
                .tag(OnboardingStep.valueTap)
                page(title: "Flashcards\nbuild themselves.",
                     subtitle: "Every word you tap becomes a card with the real sentence and clip it came from.") {
                    MockReviewCard(clip: app.clip(id: "konbini-diaries-01"))
                }
                .tag(OnboardingStep.valueFlashcards)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            HStack(spacing: 8) {
                ForEach(pages, id: \.self) { p in
                    Capsule()
                        .fill(p == step ? Color.jojoOrange : Color.jojoInk.opacity(0.18))
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

    private func page<Content: View>(title: String, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                OnboardingTitle(title: title, subtitle: subtitle)
                    .animation(.snappy, value: didTapWord)
                content()
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, Spacing.l)
            .padding(.top, Spacing.l)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: Page 1 — captions

    private var captionsIllustration: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            if let clip = app.clip(id: "kissa-stories-01") {
                Color.bgElevatedDark
                    .frame(height: 150)
                    .overlay { GradientPoster(clip: clip, isAnimating: true).allowsHitTesting(false) }
                    .clipShape(.rect(cornerRadius: Radius.card, style: .continuous))
            }
            StaticSentence(words: [
                .init(surface: "今日", furigana: "きょう", romaji: "kyou"),
                .init(surface: "は", romaji: "wa"),
                .init(surface: "天気", furigana: "てんき", romaji: "tenki", state: .selected),
                .init(surface: "が", romaji: "ga"),
                .init(surface: "いい", romaji: "ii", state: .spoken),
                .init(surface: "です", romaji: "desu"),
                .init(surface: "ね", romaji: "ne")
            ], size: 24)
            Text("The weather's nice today, isn't it?")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.6))
            HStack(spacing: Spacing.l) {
                legend(color: .tappableBlue, text: "Tap to learn")
                legend(color: .spokenGreen, text: "Being spoken")
                legend(color: .jojoOrange, text: "Just tapped")
            }
        }
        .padding(Spacing.l)
        .background(Color.bgSurfaceDark, in: RoundedRectangle(cornerRadius: Radius.sheet, style: .continuous))
        .shadow(color: .black.opacity(0.22), radius: 20, y: 10)
    }

    private func legend(color: Color, text: String) -> some View {
        HStack(spacing: 6) {
            Capsule().fill(color).frame(width: 14, height: 4)
            Text(text).font(.caption).foregroundStyle(.white.opacity(0.6))
        }
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
            .background(Color.bgSurfaceDark, in: RoundedRectangle(cornerRadius: Radius.sheet, style: .continuous))
            .shadow(color: .black.opacity(0.22), radius: 20, y: 10)

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
        .foregroundStyle(Color.jojoOrangeLight)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true)) { pulse = true }
        }
        .accessibilityHidden(true)
    }
}

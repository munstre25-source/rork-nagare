import SwiftUI

/// Steps 1-3: value-prop carousel with progress dots.
struct ValuePropCarousel: View {
    @Binding var step: OnboardingStep
    let onContinue: () -> Void
    @Environment(AppModel.self) private var app

    private let pages: [OnboardingStep] = [.valueCaptions, .valueTap, .valueFlashcards]

    var body: some View {
        VStack(spacing: Spacing.l) {
            TabView(selection: Binding(get: { pages.contains(step) ? step : .valueCaptions }, set: { step = $0 })) {
                page(title: "Real Japanese.\nNot textbook Japanese.",
                     subtitle: "Scroll short clips from anime, streams, cafés and street interviews.") {
                    captionsIllustration
                }
                .tag(OnboardingStep.valueCaptions)
                page(title: "Tap any word.\nUnderstand instantly.",
                     subtitle: "Reading, meaning and grammar in one tap, without pausing the vibe.") {
                    MockPopupCard()
                        .scaleEffect(0.96)
                        .rotationEffect(.degrees(-1.5))
                        .padding(.horizontal, Spacing.s)
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
                        .fill(p == step ? Color.nagareOrange : Color.white.opacity(0.25))
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
                content()
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, Spacing.l)
            .padding(.top, Spacing.l)
        }
        .scrollIndicators(.hidden)
    }

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
                legend(color: .nagareOrange, text: "Just tapped")
            }
        }
        .padding(Spacing.l)
        .background(Color.bgSurfaceDark, in: RoundedRectangle(cornerRadius: Radius.sheet, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.sheet, style: .continuous).strokeBorder(Color.hairlineDark))
    }

    private func legend(color: Color, text: String) -> some View {
        HStack(spacing: 6) {
            Capsule().fill(color).frame(width: 14, height: 4)
            Text(text).font(.caption).foregroundStyle(.white.opacity(0.6))
        }
    }
}

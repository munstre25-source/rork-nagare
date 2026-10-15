import SwiftUI
import SwiftData

/// Hands-on flashcard: flip a sample card and rate it, so the review buttons are familiar
/// before the feed unlocks. No clip plays on this screen.
struct FlashcardTryStepView: View {
    let onContinue: () -> Void

    @Environment(AppModel.self) private var app
    @Query private var words: [SavedWord]

    @State private var revealed: Bool = false
    @State private var answeredGood: Bool?
    @State private var nextDue: String = ""
    /// A display-only card for a truly fresh install. It is never inserted into SwiftData.
    @State private var practiceCard: SavedWord?

    private var card: SavedWord? {
        let key = app.profile.firstTappedWordKey
        if !key.isEmpty, let match = words.first(where: { $0.key == key }) { return match }
        return words.max { $0.addedAt < $1.addedAt } ?? practiceCard
    }

    var body: some View {
        VStack(spacing: Spacing.l) {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    MascotCoach(message: coachMessage)
                    if answeredGood == nil {
                        OnboardingTitle(
                            title: revealed ? "Now be honest with me." : "Try one card.",
                            subtitle: revealed
                            ? "Tap how it went. Jojo schedules the next showing for you."
                            : "Same card you'll get after you tap a word in a clip. Flip it, then rate it."
                        )
                    } else {
                        OnboardingTitle(
                            title: "That's the review loop.",
                            subtitle: "After you start, tap a word while you watch and it comes back as a card like this."
                        )
                    }
                    if let card {
                        flashcard(card)
                    } else {
                        placeholder
                    }
                    if answeredGood != nil {
                        scheduledNote
                    }
                }
                .padding(.horizontal, Spacing.l)
                .padding(.top, Spacing.l)
                .padding(.bottom, Spacing.l)
            }
            .scrollIndicators(.hidden)

            footer
                .padding(.horizontal, Spacing.l)
                .padding(.bottom, Spacing.m)
        }
        .onAppear { preparePracticeCardIfNeeded() }
    }

    private var coachMessage: String {
        if answeredGood == nil {
            return "One practice card, \(app.displayName), so the buttons feel familiar."
        }
        return answeredGood == true
        ? "Nice. I'll bring it back later, when you're about to forget it."
        : "No problem — I'll show it again in a minute instead."
    }

    // MARK: Card

    @ViewBuilder
    private func flashcard(_ word: SavedWord) -> some View {
        ZStack {
            FlashcardHero(
                surface: word.surface,
                reading: app.profile.showFurigana ? word.primaryReading : "",
                romaji: app.profile.showRomaji ? word.romaji : "",
                pos: word.pos,
                jlpt: word.jlpt,
                hint: "Tap to reveal"
            )
            .opacity(revealed ? 0 : 1)
            KikuFlashcardBack(word: word, playsClip: false) { _ in }
                .opacity(revealed ? 1 : 0)
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
        }
        .modifier(CardTurnModifier(angle: revealed ? 180 : 0))
        .animation(Motion.cardFlip, value: revealed)
        .contentShape(Rectangle())
        .onTapGesture { reveal() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(revealed ? "Card: \(word.surface), meaning \(word.gloss)" : "Card: \(word.surface). Double tap to reveal the meaning.")
        .accessibilityAddTraits(.isButton)
    }

    private var placeholder: some View {
        VStack(spacing: Spacing.m) {
            ProgressView().tint(Color.jojoOrange)
            Text("Building your first card…")
                .font(.subheadline)
                .foregroundStyle(Color.jojoInkSoft)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .brandCard()
    }

    private var scheduledNote: some View {
        HStack(spacing: Spacing.m) {
            Image(systemName: "calendar.badge.clock")
                .font(.title2)
                .foregroundStyle(Color.jojoVermilion)
            VStack(alignment: .leading, spacing: 2) {
                Text("Next showing: \(nextDue)")
                    .font(.headline)
                    .foregroundStyle(Color.jojoInk)
                Text("Spaced so you review right before forgetting.")
                    .font(.subheadline)
                    .foregroundStyle(Color.jojoInkSoft)
            }
            Spacer(minLength: 0)
        }
        .brandCard()
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    // MARK: Footer

    @ViewBuilder
    private var footer: some View {
        if answeredGood != nil {
            Button("Continue") {
                Haptics.light()
                onContinue()
            }
            .buttonStyle(PrimaryButtonStyle())
        } else if revealed, let card {
            HStack(spacing: 12) {
                Button { answer(card, good: false) } label: {
                    ReviewGradeButton(title: "Again", interval: SRS.againLabel, good: false)
                }
                Button { answer(card, good: true) } label: {
                    ReviewGradeButton(
                        title: "Good",
                        interval: SRS.label(SRS.goodInterval(fromStep: card.intervalStepIndex)),
                        good: true
                    )
                }
            }
            .buttonStyle(PressableStyle())
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else {
            Button("Show me the meaning") { reveal() }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(card == nil)
        }
    }

    // MARK: Actions

    private func reveal() {
        guard !revealed, answeredGood == nil, card != nil else { return }
        Haptics.soft()
        track("onboarding_flashcard_revealed")
        withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) { revealed = true }
    }

    private func answer(_ word: SavedWord, good: Bool) {
        good ? Haptics.success() : Haptics.soft()
        nextDue = good ? SRS.label(SRS.goodInterval(fromStep: word.intervalStepIndex)) : SRS.againLabel
        // The first-run card only teaches the interaction. It is intentionally not a saved
        // word, review, or notification until the learner saves a word from the real feed.
        let isOnboardingPreview = practiceCard.map { $0 === word } ?? false
        if !isOnboardingPreview {
            app.answer(word, good: good)
        }
        app.markFlashcardTried()
        track("onboarding_flashcard_answered", props: ["good": good ? "1" : "0"])
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { answeredGood = good }
    }

    /// Build a card in memory so onboarding stays hands-on without pre-populating vocabulary.
    private func preparePracticeCardIfNeeded() {
        guard practiceCard == nil, words.isEmpty, let clip = app.recommendedClip(preferShort: true) else { return }
        for (lineIndex, line) in clip.lines.enumerated() {
            let token = line.tokens.first { $0.tappable && $0.containsKanji }
                ?? line.tokens.first { $0.tappable }
            guard let token else { continue }
            let explanation = app.lexicon.instantExplanation(for: token)
            let preview = SavedWord(
                key: "onboarding-preview-\(token.dictionaryForm)",
                surface: token.dictionaryForm,
                readings: token.baseForm != nil ? [token.baseReading].compactMap { $0 } : token.allReadings,
                romaji: token.dictionaryRomaji,
                pos: token.pos,
                conjugationClass: token.conjugationClass,
                jlpt: token.jlpt,
                definitions: explanation?.definitions ?? token.definitions,
                jaDefinitions: explanation?.jaDefinitions ?? token.jaDefinitions
            )
            preview.contextSentence = line.text
            preview.contextSurface = token.surface
            preview.contextClipId = clip.id
            preview.contextLineIndex = lineIndex
            practiceCard = preview
            return
        }
    }
}

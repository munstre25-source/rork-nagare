import SwiftUI
import SwiftData

/// Hands-on flashcard: flip a real card and rate it with Again / Good so the learner
/// has used the review loop before we ask for an App Store rating.
struct FlashcardTryStepView: View {
    let onContinue: () -> Void

    @Environment(AppModel.self) private var app
    @Query private var words: [SavedWord]

    @State private var revealed: Bool = false
    @State private var answeredGood: Bool?
    @State private var nextDue: String = ""

    private var card: SavedWord? {
        let key = app.profile.firstTappedWordKey
        if !key.isEmpty, let match = words.first(where: { $0.key == key }) { return match }
        return words.max { $0.addedAt < $1.addedAt }
    }

    var body: some View {
        VStack(spacing: Spacing.l) {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    MascotCoach(message: coachMessage)
                    if answeredGood == nil {
                        OnboardingTitle(
                            title: revealed ? "Now be honest with me." : "Your first flashcard.",
                            subtitle: revealed
                            ? "Tap how it went. Jojo schedules the next showing for you."
                            : "Flip it, then rate it — same buttons you'll use every day."
                        )
                    } else {
                        OnboardingTitle(
                            title: "That's the review loop.",
                            subtitle: "Tap words while you watch, then rate them here. Your deck builds itself."
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
        .onAppear { seedFallbackIfNeeded() }
    }

    private var coachMessage: String {
        if answeredGood == nil {
            return "This is your deck now, \(app.displayName). One card, zero setup."
        }
        return answeredGood == true
        ? "Nice. I'll bring it back later, when you're about to forget it."
        : "No problem — I'll show it again in a minute instead."
    }

    // MARK: Card

    @ViewBuilder
    private func flashcard(_ word: SavedWord) -> some View {
        let defs = word.displayDefinitions(mode: app.profile.dictionary)
        ZStack {
            cardFront(word).opacity(revealed ? 0 : 1)
            cardBack(word, defs: defs)
                .opacity(revealed ? 1 : 0)
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
        }
        .rotation3DEffect(.degrees(revealed ? 180 : 0), axis: (x: 0, y: 1, z: 0), perspective: 0.45)
        .animation(.spring(response: 0.55, dampingFraction: 0.82), value: revealed)
        .contentShape(Rectangle())
        .onTapGesture { reveal() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(revealed ? "Card: \(word.surface), meaning \(word.gloss)" : "Card: \(word.surface). Double tap to reveal the meaning.")
        .accessibilityAddTraits(.isButton)
    }

    private func cardFront(_ word: SavedWord) -> some View {
        VStack(spacing: Spacing.m) {
            cardLabel("YOUR FIRST CARD")
            Text(word.primaryReading)
                .font(JojoFont.jp(15, relativeTo: .footnote))
                .foregroundStyle(Color.jojoInkSoft)
                .opacity(app.profile.showFurigana ? 1 : 0)
            Text(word.surface)
                .font(JojoFont.jp(52, bold: true, relativeTo: .largeTitle))
                .foregroundStyle(Color.jojoInk)
            if app.profile.showRomaji, !word.romaji.isEmpty {
                Text(word.romaji)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Color.jojoInkFaint)
            }
            Label("Tap to flip", systemImage: "hand.tap.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.jojoVermilion)
                .padding(.top, Spacing.s)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xl)
        .brandCard(padding: Spacing.l)
    }

    private func cardBack(_ word: SavedWord, defs: [String]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            cardLabel("MEANING")
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                Text(word.surface)
                    .font(JojoFont.jp(30, bold: true, relativeTo: .title))
                    .foregroundStyle(Color.jojoInk)
                WordPills(pos: word.pos, conjugationClass: word.conjugationClass, jlpt: word.jlpt)
            }
            ForEach(Array(defs.prefix(2).enumerated()), id: \.offset) { index, def in
                DefinitionRow(number: index + 1, tag: word.conjugationClass ?? word.pos, text: def)
            }
            if !word.contextSentence.isEmpty {
                Divider().overlay(Color.jojoPaperStroke)
                Text("From a real clip")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.jojoInkFaint)
                HighlightedSentence(
                    sentence: word.contextSentence,
                    target: word.contextSurface.isEmpty ? word.surface : word.contextSurface,
                    size: 18,
                    baseColor: .jojoInk
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .brandCard(padding: Spacing.l)
    }

    private func cardLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.heavy))
            .tracking(1.6)
            .foregroundStyle(Color.jojoOrange)
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
            HStack(spacing: Spacing.m) {
                Button { answer(card, good: false) } label: {
                    TryAnswerLabel(title: "Again", interval: SRS.againLabel, symbol: "arrow.counterclockwise", fg: .againText, bg: .againBackground)
                }
                Button { answer(card, good: true) } label: {
                    TryAnswerLabel(title: "Good", interval: SRS.label(SRS.goodInterval(fromStep: card.intervalStepIndex)), symbol: "checkmark", fg: .goodText, bg: .goodBackground)
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
        app.answer(word, good: good)
        app.markFlashcardTried()
        track("onboarding_flashcard_answered", props: ["good": good ? "1" : "0"])
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { answeredGood = good }
    }

    /// Seed one saved word from a recommended clip so this screen is never empty.
    private func seedFallbackIfNeeded() {
        guard words.isEmpty, let clip = app.recommendedClip(preferShort: true) else { return }
        for (lineIndex, line) in clip.lines.enumerated() {
            let token = line.tokens.first { $0.tappable && $0.containsKanji }
                ?? line.tokens.first { $0.tappable }
            guard let token else { continue }
            app.recordTap(
                token: token,
                explanation: app.lexicon.instantExplanation(for: token),
                clip: clip,
                lineIndex: lineIndex
            )
            app.noteFirstTappedWord(token)
            return
        }
    }
}

/// Again / Good button face, sized for the cream onboarding surface.
private struct TryAnswerLabel: View {
    let title: String
    let interval: String
    let symbol: String
    let fg: Color
    let bg: Color

    var body: some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .bold))
                .frame(width: 30, height: 30)
                .background(fg.opacity(0.18), in: Circle())
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.headline.weight(.bold))
                Text(interval).font(.footnote.weight(.medium)).opacity(0.85)
            }
        }
        .foregroundStyle(fg)
        .frame(maxWidth: .infinity, minHeight: 64)
        .background(bg, in: RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), next review in \(interval)")
    }
}

import SwiftUI

/// The floating tap-to-understand card. Follows the light or dark page and the selected accent.
struct TapPopupCard: View {
    /// Feed / Kiku-style: smaller card so the video stays visible around it.
    var compact: Bool = false
    /// Feed mode: the middle of the card (sentence meaning, tabs) scrolls inside this
    /// height cap while the word header and the "How well do you know it?" footer stay
    /// pinned and always visible.
    var scrollableMiddleHeight: CGFloat? = nil
    var onOpenClip: ((Clip, Int) -> Void)?

    @Environment(AppModel.self) private var app
    @Environment(WordLookupController.self) private var lookup
    @Environment(\.colorScheme) private var colorScheme
    @State private var showAllDefinitions: Bool = false
    @State private var badgeBump: Bool = false
    /// Natural height of the scrollable middle, so the card hugs short content and only
    /// scrolls when it exceeds the cap.
    @State private var middleNaturalHeight: CGFloat?

    private var onDark: Bool { colorScheme == .dark }
    private var ink: Color { onDark ? .white : Color.primary }
    private var inkSoft: Color { onDark ? Color.white.opacity(0.72) : Color.secondary }
    private var chip: Color { onDark ? Color.white.opacity(0.1) : Color.fieldFill }

    var body: some View {
        if let selection = lookup.selection, let explanation = lookup.explanation {
            Group {
                if compact {
                    compactBody(selection: selection, explanation: explanation)
                } else {
                    fullBody(selection: selection, explanation: explanation)
                }
            }
            .padding(compact ? Spacing.m : Spacing.l)
            .background(cardBackground)
            .onChange(of: lookup.tapPulse) { _, _ in
                showAllDefinitions = false
                badgeBump = true
                Task {
                    try? await Task.sleep(for: .milliseconds(180))
                    badgeBump = false
                }
            }
            .gesture(swipeTabs)
        }
    }

    /// Feed card: word → reading → one gloss first. Paint and tabs stay secondary.
    private func compactBody(selection: WordLookupController.Selection, explanation: WordExplanation) -> some View {
        let gloss = explanation.displayDefinitions(mode: app.profile.dictionary).first
            ?? explanation.definitions.first
            ?? explanation.jaDefinitions.first
            ?? ""
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    // Says exactly what the tap did: the word is a flashcard now, no save step.
                    Label(
                        lookup.previewOnly
                            ? "Preview · not saved"
                            : lookup.occurrenceCount <= 1
                                ? "New · saved to Vocab"
                                : "In your Vocab · seen \(lookup.occurrenceCount)×",
                        systemImage: lookup.occurrenceCount <= 1 ? "sparkles" : "bookmark.fill"
                    )
                    .font(.caption2.weight(.bold))
                    .textCase(.uppercase)
                    .foregroundStyle(LearningInk.selected)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .accessibilityLabel(
                        lookup.occurrenceCount <= 1
                            ? "New word, saved to Vocab as a flashcard"
                            : "Already in your Vocab, seen \(lookup.occurrenceCount) times"
                    )
                    Text(explanation.word)
                        .font(JojoFont.jp(30, bold: true, relativeTo: .title))
                        .foregroundStyle(ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                        .textGlow(LearningInk.selected, level: app.profile.glow)
                    if !explanation.readings.isEmpty {
                        Text(explanation.readings.joined(separator: ", "))
                            .font(JojoFont.jp(14, relativeTo: .subheadline))
                            .foregroundStyle(inkSoft)
                            .lineLimit(1)
                    }
                    if app.profile.showRomaji, !explanation.romaji.isEmpty {
                        Text(explanation.romaji)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(inkSoft.opacity(0.85))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                VStack(spacing: 8) {
                    closeButton(size: 28)
                    OccurrenceBadge(count: lookup.occurrenceCount, size: 28)
                        .scaleEffect(badgeBump ? 1.2 : 1)
                        .animation(.spring(response: 0.25, dampingFraction: 0.5), value: badgeBump)
                    Button {
                        SpeechService.shared.speak(selection.token.surface)
                        app.noteFirstSessionHeard()
                    } label: {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(inkSoft)
                            .frame(width: 36, height: 36)
                    }
                    .accessibilityLabel("Play pronunciation")
                    .coachTarget(.popupSpeaker, active: GuidanceCenter.shared.tourStep == .practice)
                }
            }

            if !gloss.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("1")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(onDark ? Color.black : Color.white)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(LearningInk.selected))
                    if !explanation.pos.isEmpty {
                        Text(explanation.pos)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(inkSoft)
                    }
                    Text(gloss)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(3)
                }
            }

            // The middle scrolls inside its cap; the mastery chips below never leave the card.
            let middle = VStack(alignment: .leading, spacing: 10) {
                pitchChip(for: selection.token)
                conjugationStrip(for: selection.token)

                // Contextual “in this sentence” only — skip the fallback line that repeats the gloss.
                if lookup.context != nil || lookup.isLoadingContext {
                    sentenceMeaning(fallbackGloss: gloss)
                }

                quietTabRow
                if lookup.tab == .flashcard {
                    flashcardTab(selection: selection, explanation: explanation)
                        .transition(.opacity)
                } else if lookup.tab == .examples {
                    examplesTab
                        .transition(.opacity)
                }
            }

            if let cap = scrollableMiddleHeight {
                ScrollView(.vertical, showsIndicators: false) {
                    middle
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { middleNaturalHeight = $0 }
                }
                .frame(height: middleNaturalHeight.map { min($0, cap) })
            } else {
                middle
            }

            paintRow(selection: selection)
            if let line = selection.clip.lines[safe: selection.lineIndex] {
                UnderstoodLineShareButton(line: line, clip: selection.clip, surface: selection.token.surface, compact: true)
            }
            pageDots
        }
    }

    private func fullBody(selection: WordLookupController.Selection, explanation: WordExplanation) -> some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            header(selection: selection, explanation: explanation)
            HStack(spacing: Spacing.s) {
                WordPills(pos: explanation.pos, conjugationClass: explanation.conjugationClass, jlpt: explanation.jlpt, dark: onDark)
                Spacer(minLength: 0)
                Button {
                    SpeechService.shared.speak(selection.token.surface)
                    app.noteFirstSessionHeard()
                } label: {
                    Image(systemName: "speaker.wave.2")
                        .font(.title3)
                        .foregroundStyle(LearningInk.dictionaryReading)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Play pronunciation")
                    .coachTarget(.popupSpeaker, active: GuidanceCenter.shared.tourStep == .practice)
            }
            pitchChip(for: selection.token)
            conjugationStrip(for: selection.token)
            tabRow
            paintRow(selection: selection)
            Group {
                switch lookup.tab {
                case .dictionary: dictionaryTab(explanation, limit: showAllDefinitions ? 99 : 2)
                case .flashcard: flashcardTab(selection: selection, explanation: explanation)
                case .examples: examplesTab
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .transition(.opacity)
            pageDots
            Capsule()
                .fill(onDark ? Color.white.opacity(0.35) : Color.primary.opacity(0.2))
                .frame(width: 36, height: 4)
                .frame(maxWidth: .infinity)
                .padding(.top, 2)
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: Radius.sheet, style: .continuous)
            .fill(onDark && compact ? Color.black : LearningInk.dictionaryPlate)
            .shadow(
                color: LearningInk.selected.opacity(0.35 * app.profile.glow.intensity),
                radius: 8 + app.profile.glow.radius * 0.6,
                y: 8
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sheet, style: .continuous)
                    .strokeBorder(
                        LearningInk.selected.opacity(app.profile.glow == .off ? 0.28 : 0.65),
                        lineWidth: compact ? 1.2 : 1.5
                    )
            )
            .chromeGlow(LearningInk.selected, level: compact ? (app.profile.glow == .liquid ? .glow : app.profile.glow) : app.profile.glow, radius: compact ? 10 : 14)
            .overlay(alignment: .top) {
                if app.profile.glow == .liquid, !compact {
                    RoundedRectangle(cornerRadius: Radius.sheet, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.28), Color.white.opacity(0.06), .clear],
                                startPoint: .top,
                                endPoint: .init(x: 0.5, y: 0.22)
                            )
                        )
                        .frame(height: 28)
                        .allowsHitTesting(false)
                }
            }
    }

    private var swipeTabs: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                let tabs = PopupTab.allCases
                guard let idx = tabs.firstIndex(of: lookup.tab) else { return }
                if value.translation.width < -40, idx + 1 < tabs.count {
                    Haptics.selection()
                    withAnimation(.snappy) {
                        lookup.tab = tabs[idx + 1]
                        if tabs[idx + 1] == .examples { lookup.loadContextIfNeeded(app: app) }
                    }
                } else if value.translation.width > 40, idx > 0 {
                    Haptics.selection()
                    withAnimation(.snappy) { lookup.tab = tabs[idx - 1] }
                }
            }
    }

    private func header(selection: WordLookupController.Selection, explanation: WordExplanation) -> some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            VStack(alignment: .leading, spacing: 4) {
                if lookup.occurrenceCount <= 1 {
                    Text("NEW")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.sakuraPink)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Color.sakuraPink.opacity(0.85), lineWidth: 1)
                        )
                        .accessibilityLabel("New flashcard")
                }
                HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                    Text(explanation.word)
                        .font(JojoFont.jp(38, bold: true, relativeTo: .largeTitle))
                        .foregroundStyle(LearningInk.dictionaryWord)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .textGlow(LearningInk.selected, level: app.profile.glow)
                    if app.profile.showFurigana, !explanation.readings.isEmpty {
                        Text(explanation.readings.joined(separator: ", "))
                            .font(JojoFont.jp(15, relativeTo: .subheadline))
                            .foregroundStyle(LearningInk.dictionaryReading)
                            .lineLimit(1)
                    }
                }
                if app.profile.showRomaji, !explanation.romaji.isEmpty {
                    Text(explanation.romaji)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(LearningInk.dictionaryReading)
                }
                if let base = selection.token.baseForm {
                    Text("from \(base)")
                        .font(JojoFont.jp(13, relativeTo: .footnote))
                        .foregroundStyle(inkSoft)
                }
                Label("Saved to vocab", systemImage: "bookmark.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.jojoOrange)
                    .padding(.top, 2)
                    .accessibilityLabel("Saved to Vocab as a flashcard")
                if let line = selection.clip.lines[safe: selection.lineIndex] {
                    UnderstoodLineShareButton(line: line, clip: selection.clip, surface: selection.token.surface, compact: true)
                        .padding(.top, 4)
                }
            }
            Spacer(minLength: 0)
            HStack(alignment: .top, spacing: Spacing.s) {
                closeButton(size: 32)
                OccurrenceBadge(count: lookup.occurrenceCount, size: 38)
                    .scaleEffect(badgeBump ? 1.25 : 1)
                    .animation(.spring(response: 0.25, dampingFraction: 0.5), value: badgeBump)
                    .animation(.snappy, value: lookup.occurrenceCount)
            }
        }
    }

    /// Explicit way out: the card also closes on an outside tap, but learners asked for a
    /// visible control so they never have to guess the dismiss gesture.
    private func closeButton(size: CGFloat) -> some View {
        Button {
            Haptics.selection()
            withAnimation(.snappy) { lookup.dismiss() }
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: size * 0.4, weight: .bold))
                .foregroundStyle(inkSoft)
                .frame(width: size, height: size)
                .background(chip, in: Circle())
        }
        .accessibilityLabel("Close")
    }

    /// Compact feed tabs — icons only, no heavy selected fill.
    private var quietTabRow: some View {
        HStack(spacing: 4) {
            ForEach(PopupTab.allCases, id: \.self) { tab in
                Button {
                    Haptics.selection()
                    withAnimation(.snappy) { lookup.tab = tab }
                    if tab == .examples { lookup.loadContextIfNeeded(app: app) }
                } label: {
                    Image(systemName: tab.symbol)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(lookup.tab == tab ? LearningInk.selected : inkSoft.opacity(0.7))
                        .frame(width: 36, height: 32)
                }
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(lookup.tab == tab ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
    }

    private func paintRow(selection: WordLookupController.Selection) -> some View {
        let current = app.wordState(for: selection.token)
        return VStack(alignment: .leading, spacing: 6) {
            Text("How well do you know it?")
                .font(.caption2.weight(.bold))
                .foregroundStyle(inkSoft)
                .textCase(.uppercase)
            HStack(spacing: 5) {
                ForEach(SRSState.paintMarks, id: \.self) { mark in
                    paintButton(mark.title, mark: mark, current: current, selection: selection)
                }
            }
        }
    }

    @ViewBuilder
    private func pitchChip(for token: Token) -> some View {
        let reading = token.reading ?? token.baseReading ?? token.surface
        if let accent = PitchAccent.resolve(explicit: token.pitchAccent, reading: reading, surface: token.surface) {
            Text(PitchAccent.chip(accent))
                .font(.caption2.weight(.bold))
                .foregroundStyle(inkSoft)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(chip, in: Capsule())
                .accessibilityLabel(PitchAccent.label(accent, moraCount: JapaneseText.hiragana(reading).count))
        }
    }

    @ViewBuilder
    private func conjugationStrip(for token: Token) -> some View {
        let rows = ConjugationForms.rows(for: token)
        if !rows.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(rows) { row in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.label)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(inkSoft)
                            Text(row.surface)
                                .font(JojoFont.jp(14, bold: true, relativeTo: .subheadline))
                                .foregroundStyle(ink)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(chip, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Conjugation forms")
        }
    }

    private func paintButton(_ title: String, mark: SRSState, current: SRSState?, selection: WordLookupController.Selection) -> some View {
        let selected = current == mark || (mark == .learning && current == .new)
        let tint = LearningInk.mastery(mark)
        return Button {
            Haptics.selection()
            app.paint(token: selection.token, explanation: lookup.explanation, clip: selection.clip, lineIndex: selection.lineIndex, mark: mark)
        } label: {
            Text(title)
                .font(.caption2.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .foregroundStyle(selected ? Color.black.opacity(0.85) : inkSoft)
                .frame(maxWidth: .infinity, minHeight: compact ? 28 : 32)
                .background {
                    if selected { Capsule().fill(tint) }
                    else { Capsule().fill(chip) }
                }
                .overlay {
                    Capsule().strokeBorder(selected ? tint : Color.clear, lineWidth: 1)
                }
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var tabRow: some View {
        HStack(spacing: Spacing.s) {
            ForEach(PopupTab.allCases, id: \.self) { tab in
                Button {
                    Haptics.selection()
                    withAnimation(.snappy) { lookup.tab = tab }
                    if tab == .examples { lookup.loadContextIfNeeded(app: app) }
                } label: {
                    Image(systemName: tab.symbol)
                        .font(.system(size: compact ? 15 : 17, weight: .semibold))
                        .foregroundStyle(lookup.tab == tab ? Color.jojoOrange : inkSoft)
                        .frame(width: compact ? 44 : 52, height: 40)
                        .background(
                            lookup.tab == tab ? Color.sakuraPinkSoft : Color.clear,
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                }
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(lookup.tab == tab ? .isSelected : [])
            }
            Spacer()
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(onDark ? Color.white.opacity(0.08) : Color.primary.opacity(0.08)).frame(height: 1).offset(y: 4)
        }
    }

    private var pageDots: some View {
        HStack(spacing: 5) {
            ForEach(PopupTab.allCases, id: \.self) { tab in
                Circle()
                    .fill(lookup.tab == tab ? LearningInk.selected : (onDark ? Color.white.opacity(0.28) : Color.primary.opacity(0.2)))
                    .frame(width: compact ? 5 : 6, height: compact ? 5 : 6)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, compact ? 2 : 4)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func sentenceMeaning(fallbackGloss: String) -> some View {
        if let context = lookup.context, !context.contextualExplanation.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("In this sentence")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(inkSoft)
                    if lookup.isLoadingContext {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(inkSoft)
                    }
                }
                Text(context.contextualExplanation)
                    .font(.footnote)
                    .foregroundStyle(ink)
                    .fixedSize(horizontal: false, vertical: true)
                if !compact, let example = context.examples.first, !example.isEmpty {
                    Text(example)
                        .font(JojoFont.jp(14, relativeTo: .footnote))
                        .foregroundStyle(ink)
                        .lineLimit(3)
                }
            }
        } else if let selection = lookup.selection, !fallbackGloss.isEmpty {
            Text(lineMeaning(surface: selection.token.surface, gloss: fallbackGloss))
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func lineMeaning(surface: String, gloss: String) -> AttributedString {
        var result = AttributedString("In this line, \(surface) means “\(gloss)”.")
        result.foregroundColor = onDark ? Color.white.opacity(0.78) : Color.translationText
        if let range = result.range(of: surface) {
            result[range].foregroundColor = LearningInk.dictionaryWord
            result[range].font = .footnote.weight(.bold)
        }
        if let range = result.range(of: gloss) {
            result[range].foregroundColor = LearningInk.dictionaryGloss
            result[range].font = .footnote.weight(.semibold)
        }
        return result
    }

    private func dictionaryTab(_ explanation: WordExplanation, limit: Int = 2) -> some View {
        let defs = explanation.displayDefinitions(mode: app.profile.dictionary)
        let capped = Array(defs.prefix(max(1, limit)))
        let visible = showAllDefinitions ? defs : capped
        return VStack(alignment: .leading, spacing: Spacing.s) {
            ForEach(Array(visible.enumerated()), id: \.offset) { index, definition in
                DefinitionRow(number: index + 1, tag: explanation.pos, text: definition, dark: onDark)
            }
            if compact, defs.count > capped.count, !showAllDefinitions {
                Text("+\(defs.count - capped.count) more")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(LearningInk.dictionaryReading)
            }
            sentenceMeaning(fallbackGloss: explanation.definitions.first ?? explanation.jaDefinitions.first ?? "")
            if !compact {
                HStack {
                    if defs.count > capped.count, !showAllDefinitions {
                        Button {
                            withAnimation(.snappy) { showAllDefinitions = true }
                        } label: {
                            Label("\(defs.count - capped.count) more", systemImage: "plus")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(LearningInk.dictionaryReading)
                                .frame(minHeight: 44)
                        }
                    }
                    Spacer()
                }
                if let note = explanation.formalityNote {
                    Label(note.capitalized + " register", systemImage: "quote.bubble")
                        .font(.footnote)
                        .foregroundStyle(inkSoft)
                }
                relatedClipsRail(for: explanation.word)
            }
        }
    }

    @ViewBuilder
    private func relatedClipsRail(for surface: String) -> some View {
        let hits = app.clipsMentioning(surface, limit: 4)
        if hits.count > 1 {
            VStack(alignment: .leading, spacing: Spacing.s) {
                Text("Also in")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(inkSoft)
                    .textCase(.uppercase)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.s) {
                        ForEach(Array(hits), id: \.id) { clip in
                            Button {
                                Haptics.selection()
                                app.pendingFeedClipId = clip.id
                                lookup.dismiss()
                            } label: {
                                Text(clip.channelName)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(ink)
                                    .padding(.horizontal, 12)
                                    .frame(minHeight: 36)
                                    .background(chip, in: Capsule())
                            }
                        }
                    }
                }
            }
            .padding(.top, Spacing.s)
        }
    }

    private func flashcardTab(selection: WordLookupController.Selection, explanation: WordExplanation) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text("Added to your deck")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.jojoOrange)
                .textCase(.uppercase)
            HighlightedSentence(sentence: selection.sentence, target: selection.token.surface, size: 17, baseColor: ink)
            Text(selection.translation)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ink)
            HStack(spacing: Spacing.s) {
                Image(systemName: "clock.arrow.circlepath")
                Text("First review in 10 minutes · \(selection.clip.channelName)")
            }
            .font(.footnote)
            .foregroundStyle(inkSoft)
        }
        .padding(Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.definitionTints[0], in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private var examplesTab: some View {
        if let context = lookup.context {
            VStack(alignment: .leading, spacing: Spacing.s) {
                Text(context.contextualExplanation)
                    .font(.subheadline)
                    .foregroundStyle(ink)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(Array(context.examples.prefix(2).enumerated()), id: \.offset) { index, example in
                    Text(example)
                        .font(JojoFont.jp(14, relativeTo: .subheadline))
                        .foregroundStyle(ink)
                        .padding(Spacing.m)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.definitionTints[(index + 1) % 3], in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                if !context.relatedWords.isEmpty {
                    Text("Related: " + context.relatedWords.joined(separator: " · "))
                        .font(JojoFont.jp(13, relativeTo: .footnote))
                        .foregroundStyle(inkSoft)
                }
            }
        } else {
            HStack(spacing: Spacing.s) {
                ProgressView().tint(ink)
                Text("Finding examples…").font(.subheadline).foregroundStyle(inkSoft)
            }
            .frame(minHeight: 60)
            .onAppear { lookup.loadContextIfNeeded(app: app) }
        }
    }
}

/// Numbered definition entry on a soft pastel card.
struct DefinitionRow: View {
    let number: Int
    let tag: String?
    let text: String
    var dark: Bool = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
            Text("\(number)")
                .font(.footnote.weight(.bold))
                .foregroundStyle(dark ? Color.black : Color.translationText)
                .frame(width: 24, height: 24)
                .background(Circle().fill(dark ? LearningInk.selected : Color.primary.opacity(0.08)))
            if let tag {
                PillView(text: tag, style: dark ? .neutralDark : .pos)
            }
            Text(text)
                .font(.body.weight(.semibold))
                .foregroundStyle(dark ? LearningInk.dictionaryGloss : Color.translationText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, 10)
        .background(tint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var tint: Color {
        let tints: [Color] = dark
            ? [Color(hex: "#1E2733"), Color(hex: "#23252B"), Color(hex: "#2A2230")]
            : Color.definitionTints
        return tints[(number - 1) % tints.count]
    }
}

/// A sentence with the target word highlighted in orange.
struct HighlightedSentence: View {
    let sentence: String
    let target: String
    var size: CGFloat = 18
    var baseColor: Color = .primary
    var lineLimit: Int? = nil

    var body: some View {
        Text(attributed)
            .font(JojoFont.jp(size, relativeTo: .body))
            .lineSpacing(4)
            .lineLimit(lineLimit)
            .fixedSize(horizontal: false, vertical: lineLimit == nil)
    }

    private var attributed: AttributedString {
        var result = AttributedString(sentence)
        result.foregroundColor = baseColor
        if !target.isEmpty, let range = result.range(of: target) {
            result[range].foregroundColor = LearningInk.dictionaryWord
            result[range].font = JojoFont.jp(size, bold: true, relativeTo: .body)
        }
        return result
    }
}

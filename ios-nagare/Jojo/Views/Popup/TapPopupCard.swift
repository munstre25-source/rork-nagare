import SwiftUI

/// The floating tap-to-understand card. Follows the light or dark page and the selected accent.
struct TapPopupCard: View {
    /// Feed / Kiku-style: a substantial overlay card with its detail tabs kept in view.
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
    @State private var askDraft = ""
    @State private var showsWordJourney = false
    @FocusState private var askFocused: Bool

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
            .sheet(isPresented: $showsWordJourney) {
                wordJourney
            }
        }
    }

    @ViewBuilder
    private var wordJourney: some View {
        if let selection = lookup.selection {
            WordJourneySheet(
                word: selection.token.surface,
                encounterCount: max(lookup.occurrenceCount, 1),
                current: app.wordState(for: selection.token) ?? .new,
                onSelect: { mark in
                    app.paint(
                        token: selection.token,
                        explanation: lookup.explanation,
                        clip: selection.clip,
                        lineIndex: selection.lineIndex,
                        mark: mark
                    )
                },
                onOpenWords: openYourWords
            )
        }
    }

    /// Feed card: large word header, definition panel and persistent tab content.
    private func compactBody(selection: WordLookupController.Selection, explanation: WordExplanation) -> some View {
        let gloss = explanation.displayDefinitions(mode: app.profile.dictionary).first
            ?? explanation.definitions.first
            ?? explanation.jaDefinitions.first
            ?? ""
        let grammarLine = GrammarFormNotes.line(for: selection.token)
        let statusLabel: String = {
            if lookup.previewOnly || lookup.deferredSave { return "Preview · not saved" }
            if lookup.occurrenceCount <= 1 { return "New · saved to Vocab" }
            return "In your Vocab · seen \(lookup.occurrenceCount)×"
        }()
        let statusA11y: String = {
            if lookup.previewOnly || lookup.deferredSave { return "Preview, not saved to Vocab" }
            if lookup.occurrenceCount <= 1 { return "New word, saved to Vocab as a flashcard" }
            return "Already in your Vocab, seen \(lookup.occurrenceCount) times"
        }()

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(statusLabel)
                        .font(.caption2.weight(.bold))
                        .textCase(.uppercase)
                        .foregroundStyle(LearningInk.selected)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .accessibilityLabel(statusA11y)

                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(explanation.word)
                            .font(JojoFont.jp(30, bold: true, relativeTo: .title))
                            .foregroundStyle(ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.55)
                            .textGlow(LearningInk.selected, level: app.profile.glow)
                        if app.profile.furiganaMode.showsAny, !explanation.readings.isEmpty {
                            Text(explanation.readings.joined(separator: ", "))
                                .font(JojoFont.jp(15, relativeTo: .subheadline))
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

                    if let grammarLine {
                        Text(grammarLine)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(inkSoft)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                HStack(spacing: 2) {
                    if !lookup.deferredSave && !lookup.previewOnly {
                        journeyButton(selection: selection, size: 36)
                    }
                    Button {
                        SpeechService.shared.speak(selection.token.surface)
                        app.noteFirstSessionHeard()
                    } label: {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(inkSoft)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Play pronunciation")
                    .coachTarget(.popupSpeaker, active: GuidanceCenter.shared.tourStep == .practice)
                }
            }

            if !gloss.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if !explanation.pos.isEmpty {
                        Text(explanation.pos)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(inkSoft)
                    }
                    if let level = explanation.jlpt, !level.isEmpty {
                        Text(level.uppercased())
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(onDark ? Color(hex: "#4ADE80") : Color(hex: "#047857"))
                    }
                    Text(gloss)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ink)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(chip, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                missingDefinitionStatus
            }

            if lookup.deferredSave {
                Button {
                    Haptics.selection()
                    lookup.saveDeferred(app: app)
                } label: {
                    Label("Save to Vocab", systemImage: "bookmark")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                        .background(LearningInk.selected.opacity(0.14), in: Capsule())
                }
                .buttonStyle(.plain)
            }

            compactTabRail

            let middle = VStack(alignment: .leading, spacing: 8) {
                if lookup.tab != .dictionary {
                    detailReturnRow
                }
                pitchChip(for: selection.token)
                conjugationStrip(for: selection.token)
                switch lookup.tab {
                case .dictionary:
                    compactDictionaryTab(explanation, primaryGloss: gloss)
                case .ai:
                    aiTab(selection: selection, explanation: explanation)
                case .flashcard:
                    flashcardTab(selection: selection, explanation: explanation)
                    paintRow(selection: selection)
                case .examples:
                    examplesTab
                }
            }
            if let cap = scrollableMiddleHeight {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 0) {
                            middle
                            Color.clear
                                .frame(height: 1)
                                .id("popup-middle-bottom")
                        }
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { middleNaturalHeight = $0 }
                    }
                    .frame(height: middleNaturalHeight.map { min($0, cap) } ?? min(180, cap))
                    .onChange(of: lookup.askThread.count) { _, _ in
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo("popup-middle-bottom", anchor: .bottom)
                        }
                    }
                }
            } else {
                middle
            }
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
                case .ai: aiTab(selection: selection, explanation: explanation)
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
                        if tabs[idx + 1] == .examples || tabs[idx + 1] == .ai { lookup.loadContextIfNeeded(app: app) }
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
                    if app.profile.furiganaMode.showsAny, !explanation.readings.isEmpty {
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
                if let note = GrammarFormNotes.line(for: selection.token) {
                    Text(note)
                        .font(JojoFont.jp(13, relativeTo: .footnote))
                        .foregroundStyle(inkSoft)
                } else if let base = selection.token.baseForm {
                    Text("from \(base)")
                        .font(JojoFont.jp(13, relativeTo: .footnote))
                        .foregroundStyle(inkSoft)
                }
                Label(
                    lookup.previewOnly || lookup.deferredSave ? "Preview · not saved" : "Saved to vocab",
                    systemImage: lookup.previewOnly || lookup.deferredSave ? "eye" : "bookmark.fill"
                )
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.jojoOrange)
                    .padding(.top, 2)
                    .accessibilityLabel(
                        lookup.previewOnly || lookup.deferredSave
                            ? "Preview, not saved to Vocab"
                            : "Saved to Vocab as a flashcard"
                    )
                if let line = selection.clip.lines[safe: selection.lineIndex] {
                    UnderstoodLineShareButton(line: line, clip: selection.clip, surface: selection.token.surface, compact: true)
                        .padding(.top, 4)
                }
            }
            Spacer(minLength: 0)
            if !lookup.deferredSave && !lookup.previewOnly {
                journeyButton(selection: selection, size: 42)
            }
        }
    }

    private func journeyButton(selection: WordLookupController.Selection, size: CGFloat) -> some View {
        Button {
            Haptics.selection()
            showsWordJourney = true
        } label: {
            OccurrenceBadge(count: max(lookup.occurrenceCount, 1), size: size)
                .scaleEffect(badgeBump ? 1.15 : 1)
                .animation(.spring(response: 0.25, dampingFraction: 0.5), value: badgeBump)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "map.fill")
                        .font(.system(size: max(8, size * 0.22), weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: max(15, size * 0.36), height: max(15, size * 0.36))
                        .background(Color.black.opacity(0.72), in: Circle())
                        .offset(x: 3, y: 3)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "Word journey for \(selection.token.surface), encountered \(max(lookup.occurrenceCount, 1)) times"
        )
        .accessibilityHint("Change how well you know this word or open Your Words")
    }

    private var compactTabRail: some View {
        HStack(spacing: 5) {
            ForEach(PopupTab.allCases, id: \.self) { tab in
                Button {
                    select(tab)
                } label: {
                    VStack(spacing: 3) {
                        if tab == .ai {
                            JojoMascotAvatar(size: 19)
                        } else {
                            Image(systemName: tab.symbol)
                                .font(.system(size: 15, weight: .semibold))
                                .frame(height: 19)
                        }
                        Text(tab.compactTitle)
                            .font(.system(size: 9, weight: .bold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(lookup.tab == tab ? LearningInk.selected : inkSoft)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(
                        lookup.tab == tab ? LearningInk.selected.opacity(0.14) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(lookup.tab == tab ? LearningInk.selected.opacity(0.55) : Color.clear)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(lookup.tab == tab ? .isSelected : [])
            }
        }
    }

    private var detailReturnRow: some View {
        HStack(spacing: 8) {
            Button {
                select(.dictionary)
            } label: {
                Label("Back to word", systemImage: "chevron.left")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(LearningInk.selected)
                    .frame(minHeight: 32)
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
            Text(lookup.tab.title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(inkSoft)
                .textCase(.uppercase)
        }
    }

    private func select(_ tab: PopupTab) {
        Haptics.selection()
        withAnimation(.snappy) { lookup.tab = tab }
        if tab == .examples || tab == .ai { lookup.loadContextIfNeeded(app: app) }
        if tab == .dictionary { showAllDefinitions = true }
    }

    private func openYourWords() {
        showsWordJourney = false
        app.pendingVocabWordKey = lookup.selection.map { AppModel.wordKey(for: $0.token) }
        lookup.dismiss()
        app.pendingDeepLink = .vocab
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
                    if tab == .examples || tab == .ai { lookup.loadContextIfNeeded(app: app) }
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
        var result = AttributedString("Saved meaning of \(surface): \(gloss).")
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

    /// Keep saved clip context visible while AI enrichment runs silently.
    private var missingDefinitionStatus: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let selection = lookup.selection {
                let translation = selection.translation.trimmingCharacters(in: .whitespacesAndNewlines)
                Text(translation.isEmpty ? "From this clip" : "Sentence meaning")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(inkSoft)
                Text(translation.isEmpty ? selection.sentence : translation)
                    .font(.footnote)
                    .foregroundStyle(ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func dictionaryTab(_ explanation: WordExplanation, limit: Int = 2) -> some View {
        let defs = explanation.displayDefinitions(mode: app.profile.dictionary)
        let capped = Array(defs.prefix(max(1, limit)))
        let visible = showAllDefinitions ? defs : capped
        return VStack(alignment: .leading, spacing: Spacing.s) {
            if defs.isEmpty { missingDefinitionStatus }
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

    private func compactDictionaryTab(_ explanation: WordExplanation, primaryGloss: String) -> some View {
        let otherDefinitions = explanation.displayDefinitions(mode: app.profile.dictionary)
            .filter { $0.compare(primaryGloss, options: [.caseInsensitive, .diacriticInsensitive]) != .orderedSame }
        return VStack(alignment: .leading, spacing: Spacing.s) {
            if !otherDefinitions.isEmpty {
                Text("Other meanings")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(inkSoft)
                    .textCase(.uppercase)
                ForEach(Array(otherDefinitions.prefix(2).enumerated()), id: \.offset) { index, definition in
                    DefinitionRow(number: index + 2, tag: explanation.pos, text: definition, dark: onDark)
                }
            }
            if lookup.context != nil || lookup.isLoadingContext {
                sentenceMeaning(fallbackGloss: primaryGloss)
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
            let currentSentence = lookup.selection?.sentence ?? ""
            let examples = uniqueNonEmpty(context.examples)
                .filter { example in
                    let japaneseText = example.components(separatedBy: " — ").first?
                        .components(separatedBy: .newlines).first ?? example
                    return japaneseText.trimmingCharacters(in: .whitespacesAndNewlines) != currentSentence
                }
            let relatedWords = uniqueNonEmpty(context.relatedWords)
            VStack(alignment: .leading, spacing: Spacing.s) {
                Text("More examples")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(inkSoft)
                    .textCase(.uppercase)
                ForEach(Array(examples.prefix(2).enumerated()), id: \.offset) { index, example in
                    Text(example)
                        .font(JojoFont.jp(14, relativeTo: .subheadline))
                        .foregroundStyle(ink)
                        .padding(Spacing.m)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.definitionTints[(index + 1) % 3], in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                if examples.isEmpty {
                    if lookup.isLoadingContext {
                        HStack(spacing: Spacing.s) {
                            ProgressView().tint(ink)
                            Text("Finding more examples…")
                                .font(.footnote)
                                .foregroundStyle(inkSoft)
                        }
                    } else {
                        Text("No other example sentences are available right now.")
                            .font(.footnote)
                            .foregroundStyle(inkSoft)
                        if !lookup.offlineOnly && !lookup.previewOnly {
                            Button("Try again") { lookup.retryContext(app: app) }
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(LearningInk.selected)
                        }
                    }
                }
                if !relatedWords.isEmpty {
                    Text("Related: " + relatedWords.joined(separator: " · "))
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

    // MARK: AI tab

    /// Meaning in this sentence, an example and the grammar note, then a tiny Ask Jojo thread.
    private func aiTab(selection: WordLookupController.Selection, explanation: WordExplanation) -> some View {
        let context = lookup.context
        let live = context?.isFallback == false
        let example = context.flatMap { ctx in
            uniqueNonEmpty(ctx.examples).first { $0.components(separatedBy: " — ").first?
                .trimmingCharacters(in: .whitespacesAndNewlines) != selection.sentence }
        }
        let grammar = GrammarFormNotes.line(for: selection.token)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                JojoMascotAvatar(size: 24)
                Text(live ? "Jojo Sensei" : "Jojo")
                    .font(.caption.weight(.heavy))
                    .textCase(.uppercase)
                    .foregroundStyle(Color.jojoOrange)
                if lookup.isLoadingContext {
                    ProgressView().controlSize(.mini).tint(inkSoft)
                }
                Spacer(minLength: 0)
            }
            aiSection("Meaning here", body: context?.contextualExplanation
                      ?? explanation.definitions.first ?? selection.translation)
            if let example, !example.isEmpty {
                aiSection("Example", body: example, japanese: true)
            }
            if let grammar {
                aiSection("Grammar", body: grammar)
            } else if let note = explanation.formalityNote {
                aiSection("Register", body: note.capitalized)
            }

            Divider().overlay(onDark ? Color.white.opacity(0.1) : Color.primary.opacity(0.08))

            ForEach(lookup.askThread) { message in
                askBubble(message)
            }
            if lookup.isAsking {
                HStack(spacing: 6) {
                    JojoMascotAvatar(size: 22)
                    ProgressView().controlSize(.small).tint(inkSoft)
                    Text("Jojo is thinking…").font(.caption).foregroundStyle(inkSoft)
                }
            }
            if lookup.askThread.isEmpty && !lookup.isAsking {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(askSuggestions(for: selection.token), id: \.self) { suggestion in
                            Button {
                                Haptics.selection()
                                lookup.ask(suggestion, app: app)
                            } label: {
                                Text(suggestion)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(ink)
                                    .padding(.horizontal, 11)
                                    .frame(minHeight: 32)
                                    .background(chip, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            HStack(spacing: 8) {
                TextField("Ask Jojo about \(selection.token.surface)…", text: $askDraft)
                    .font(.subheadline)
                    .foregroundStyle(ink)
                    .focused($askFocused)
                    .submitLabel(.send)
                    .onSubmit(sendAsk)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 40)
                    .background(chip, in: Capsule())
                Button(action: sendAsk) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(askDraft.trimmingCharacters(in: .whitespaces).isEmpty || lookup.isAsking
                                    ? Color.accentDisabled : Color.sakuraButton, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(askDraft.trimmingCharacters(in: .whitespaces).isEmpty || lookup.isAsking)
                .accessibilityLabel("Send question")
            }
        }
    }

    private func sendAsk() {
        let text = askDraft
        askDraft = ""
        lookup.ask(text, app: app)
    }

    private func askSuggestions(for token: Token) -> [String] {
        var list = ["Why this form here?", "Is it casual or polite?", "Give me another example"]
        if token.baseForm != nil { list.insert("What's the dictionary form?", at: 1) }
        list.append("Similar words?")
        return list
    }

    private func aiSection(_ title: String, body: String, japanese: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2.weight(.bold))
                .textCase(.uppercase)
                .foregroundStyle(inkSoft)
            Text(body)
                .font(japanese ? JojoFont.jp(14, relativeTo: .footnote) : .footnote)
                .foregroundStyle(ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func askBubble(_ message: WordLookupController.AskMessage) -> some View {
        HStack(alignment: .bottom, spacing: 6) {
            if message.fromLearner { Spacer(minLength: 40) } else { JojoMascotAvatar(size: 22) }
            Text(message.text)
                .font(.footnote)
                .foregroundStyle(message.fromLearner ? Color.white : (message.failed ? inkSoft : ink))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(message.fromLearner ? Color.sakuraButton : chip,
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            if !message.fromLearner { Spacer(minLength: 24) }
        }
        .frame(maxWidth: .infinity, alignment: message.fromLearner ? .trailing : .leading)
    }
}

/// Jojo's original mastery picker: a small learning map rather than a copied status list.
/// The encounter badge opens it, turning the count into a useful control and a path to Vocab.
private struct WordJourneySheet: View {
    let word: String
    let encounterCount: Int
    let current: SRSState
    let onSelect: (SRSState) -> Void
    let onOpenWords: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var localSelection: SRSState?

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    private var selected: SRSState { localSelection ?? current }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top, spacing: 14) {
                        ZStack {
                            Circle().fill(Color.jojoOrange.opacity(0.16))
                            Image(systemName: "map.fill")
                                .font(.title2.weight(.bold))
                                .foregroundStyle(Color.jojoOrange)
                        }
                        .frame(width: 52, height: 52)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Word Journey")
                                .font(.title2.weight(.bold))
                            Text(word)
                                .font(JojoFont.jp(22, bold: true, relativeTo: .title3))
                            Text("Met \(encounterCount) time\(encounterCount == 1 ? "" : "s") · choose the pace that feels honest")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(SRSState.allCases, id: \.self) { state in
                            journeyStop(state)
                        }
                    }

                    Button {
                        dismiss()
                        onOpenWords()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "books.vertical.fill")
                                .font(.headline)
                                .foregroundStyle(Color.jojoOrange)
                                .frame(width: 38, height: 38)
                                .background(Color.jojoOrange.opacity(0.14), in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Your Words")
                                    .font(.headline)
                                Text("Review this word with everything you have collected")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.right")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(14)
                        .background(Color.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(Color.cardStroke, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(20)
            }
            .background(Color.canvas.ignoresSafeArea())
            .navigationTitle("Learning map")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func journeyStop(_ state: SRSState) -> some View {
        let isSelected = selected == state
        return Button {
            Haptics.selection()
            localSelection = state
            onSelect(state)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: symbol(for: state))
                        .font(.subheadline.weight(.bold))
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                    }
                }
                Text(state.title)
                    .font(.subheadline.weight(.bold))
                Text(detail(for: state))
                    .font(.caption2)
                    .foregroundStyle(isSelected ? Color.primary.opacity(0.75) : .secondary)
                    .lineLimit(2)
            }
            .foregroundStyle(isSelected ? Color.primary : .secondary)
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
            .background(
                isSelected ? LearningInk.mastery(state).opacity(0.22) : Color.card,
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isSelected ? LearningInk.mastery(state) : Color.cardStroke, lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func symbol(for state: SRSState) -> String {
        switch state {
        case .new: "circle.dashed"
        case .learning: "leaf.fill"
        case .familiar: "circle.hexagongrid.fill"
        case .easy: "wind"
        case .known: "checkmark.seal.fill"
        }
    }

    private func detail(for state: SRSState) -> String {
        switch state {
        case .new: "Just met · review soon"
        case .learning: "Still taking root"
        case .familiar: "Recognise it most times"
        case .easy: "Feels natural now"
        case .known: "Keep it in long-term memory"
        }
    }
}

private func uniqueNonEmpty(_ values: [String]) -> [String] {
    var seen = Set<String>()
    return values.compactMap { value in
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = trimmed.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        guard !trimmed.isEmpty, seen.insert(key).inserted else { return nil }
        return trimmed
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

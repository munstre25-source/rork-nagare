import SwiftUI

/// The floating tap-to-understand card. Always dark (lives over the player/transcript).
struct TapPopupCard: View {
    /// Feed / Kiku-style: smaller card so the video stays visible around it.
    var compact: Bool = false
    var onOpenClip: ((Clip, Int) -> Void)?

    @Environment(AppModel.self) private var app
    @Environment(WordLookupController.self) private var lookup
    @State private var showAllDefinitions: Bool = false
    @State private var badgeBump: Bool = false

    var body: some View {
        if let selection = lookup.selection, let explanation = lookup.explanation {
            VStack(alignment: .leading, spacing: compact ? Spacing.s : Spacing.m) {
                header(selection: selection, explanation: explanation)
                HStack(spacing: Spacing.s) {
                    WordPills(pos: explanation.pos, conjugationClass: explanation.conjugationClass, jlpt: explanation.jlpt, dark: true)
                    Spacer(minLength: 0)
                    Button {
                        SpeechService.shared.speak(selection.token.surface)
                    } label: {
                        Image(systemName: "speaker.wave.2")
                            .font(compact ? .body : .title3)
                            .foregroundStyle(LearningInk.dictionaryReading)
                            .frame(width: compact ? 36 : 44, height: compact ? 36 : 44)
                    }
                    .accessibilityLabel("Play pronunciation")
                }
                tabRow
                paintRow(selection: selection)
                Group {
                    switch lookup.tab {
                    case .dictionary: dictionaryTab(explanation, limit: compact ? 2 : (showAllDefinitions ? 99 : 2))
                    case .flashcard: flashcardTab(selection: selection, explanation: explanation)
                    case .examples: examplesTab
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity)
                pageDots
                Capsule()
                    .fill(Color.white.opacity(0.35))
                    .frame(width: 36, height: 4)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 2)
            }
            .padding(compact ? Spacing.m : Spacing.l)
            .background(
                RoundedRectangle(cornerRadius: Radius.sheet, style: .continuous)
                    .fill(LearningInk.dictionaryPlate)
                    .shadow(color: LearningInk.dictionaryWord.opacity(0.45), radius: 24, y: 10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sheet, style: .continuous)
                    .strokeBorder(LearningInk.dictionaryWord.opacity(0.7), lineWidth: 1.5)
            )
            .environment(\.colorScheme, .dark)
            .onChange(of: lookup.tapPulse) { _, _ in
                showAllDefinitions = false
                badgeBump = true
                Task {
                    try? await Task.sleep(for: .milliseconds(180))
                    badgeBump = false
                }
            }
            .gesture(
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
            )
        }
    }

    private func header(selection: WordLookupController.Selection, explanation: WordExplanation) -> some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                    Text(explanation.word)
                        .font(JojoFont.jp(compact ? 28 : 38, bold: true, relativeTo: .largeTitle))
                        .foregroundStyle(LearningInk.dictionaryWord)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .shadow(color: LearningInk.dictionaryWord.opacity(0.45), radius: 8)
                    if app.profile.showFurigana, !explanation.readings.isEmpty {
                        Text(explanation.readings.joined(separator: ", "))
                            .font(JojoFont.jp(compact ? 13 : 15, relativeTo: .subheadline))
                            .foregroundStyle(LearningInk.dictionaryReading)
                            .lineLimit(1)
                    }
                }
                if app.profile.showRomaji, !explanation.romaji.isEmpty {
                    Text(explanation.romaji)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(LearningInk.dictionaryGloss)
                }
                if !compact, let base = selection.token.baseForm {
                    Text("from \(base)")
                        .font(JojoFont.jp(13, relativeTo: .footnote))
                        .foregroundStyle(.white.opacity(0.5))
                }
                if !compact {
                    Label("In Vocab", systemImage: "bookmark.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.jojoOrange)
                        .padding(.top, 2)
                        .accessibilityLabel("Saved to Vocab as a flashcard")
                }
            }
            Spacer(minLength: 0)
            OccurrenceBadge(count: lookup.occurrenceCount, size: compact ? 30 : 38)
                .scaleEffect(badgeBump ? 1.25 : 1)
                .animation(.spring(response: 0.25, dampingFraction: 0.5), value: badgeBump)
                .animation(.snappy, value: lookup.occurrenceCount)
        }
    }

    private func paintRow(selection: WordLookupController.Selection) -> some View {
        let current = app.wordState(for: selection.token)
        return HStack(spacing: 6) {
            paintButton("Learning", mark: .learning, current: current, selection: selection)
            paintButton("Familiar", mark: .familiar, current: current, selection: selection)
            paintButton("Known", mark: .known, current: current, selection: selection)
        }
    }

    private func paintButton(_ title: String, mark: SRSState, current: SRSState?, selection: WordLookupController.Selection) -> some View {
        let selected = current == mark || (mark == .learning && current == .new)
        return Button {
            Haptics.selection()
            app.paint(token: selection.token, explanation: lookup.explanation, clip: selection.clip, lineIndex: selection.lineIndex, mark: mark)
        } label: {
            Text(title)
                .font(.caption.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(selected ? .white : .white.opacity(0.75))
                .frame(maxWidth: .infinity, minHeight: 32)
                .background {
                    if selected { Capsule().fill(Color.sakuraFill) }
                    else { Capsule().fill(Color.white.opacity(0.08)) }
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
                        .foregroundStyle(lookup.tab == tab ? Color.jojoOrange : .white.opacity(0.82))
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
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1).offset(y: 4)
        }
    }

    private var pageDots: some View {
        HStack(spacing: 5) {
            ForEach(PopupTab.allCases, id: \.self) { tab in
                Circle()
                    .fill(lookup.tab == tab ? Color.jojoOrange : Color.white.opacity(0.3))
                    .frame(width: 6, height: 6)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
        .accessibilityHidden(true)
    }

    private func lineMeaning(surface: String, gloss: String) -> AttributedString {
        var result = AttributedString("In this line, \(surface) means “\(gloss)”.")
        result.foregroundColor = Color.white.opacity(0.78)
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
                DefinitionRow(number: index + 1, tag: explanation.pos, text: definition, dark: true)
            }
            if let selection = lookup.selection {
                let gloss = explanation.definitions.first ?? explanation.jaDefinitions.first ?? ""
                if !gloss.isEmpty {
                    Text(lineMeaning(surface: selection.token.surface, gloss: gloss))
                        .font(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(3)
                }
            }
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
                        .foregroundStyle(.white.opacity(0.55))
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
                    .foregroundStyle(.white.opacity(0.5))
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
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 12)
                                    .frame(minHeight: 36)
                                    .background(Color.white.opacity(0.12), in: Capsule())
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
            HighlightedSentence(sentence: selection.sentence, target: selection.token.surface, size: 17, baseColor: .white)
            Text(selection.translation)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
            HStack(spacing: Spacing.s) {
                Image(systemName: "clock.arrow.circlepath")
                Text("First review in 10 minutes · \(selection.clip.channelName)")
            }
            .font(.footnote)
            .foregroundStyle(.white.opacity(0.5))
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
                    .foregroundStyle(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(Array(context.examples.prefix(2).enumerated()), id: \.offset) { index, example in
                    Text(example)
                        .font(JojoFont.jp(14, relativeTo: .subheadline))
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(Spacing.m)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.definitionTints[(index + 1) % 3], in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                if !context.relatedWords.isEmpty {
                    Text("Related: " + context.relatedWords.joined(separator: " · "))
                        .font(JojoFont.jp(13, relativeTo: .footnote))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
        } else {
            HStack(spacing: Spacing.s) {
                ProgressView().tint(.white)
                Text("Finding examples…").font(.subheadline).foregroundStyle(.white.opacity(0.6))
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
                .foregroundStyle(dark ? LearningInk.dictionaryPlate : Color.translationText)
                .frame(width: 24, height: 24)
                .background(Circle().fill(dark ? LearningInk.dictionaryWord : Color.primary.opacity(0.08)))
            if let tag {
                PillView(text: tag, style: dark ? .neutralDark : .pos)
            }
            Text(text)
                .font(.body.weight(.semibold))
                .foregroundStyle(dark ? Color.white : Color.translationText)
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

    var body: some View {
        Text(attributed)
            .font(JojoFont.jp(size, relativeTo: .body))
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
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

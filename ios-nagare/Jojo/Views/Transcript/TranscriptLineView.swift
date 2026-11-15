import SwiftUI

/// One Japanese line in a wrapping flow of three-tier words, with its English translation beneath.
struct TranscriptLineView: View {
    let clip: Clip
    let lineIndex: Int
    let spokenTokenIndex: Int?
    var highlightSurface: String?
    var pulseTokenIndex: Int?
    var isPulsing: Bool = false
    var tooltip: String?
    var showsTranslation: Bool = true
    var isActive: Bool = true
    /// Compact styling; legacy callers can force JP/EN, furigana, and romaji on.
    var forceDenseAids: Bool = false
    /// Keep the feed's compact styling but use the learner's subtitle and reading settings.
    var respectsProfileDisplay: Bool = false
    /// Kiku raised card behind the current karaoke line.
    var raisedCard: Bool = false
    /// Time range and a speaker, the way the feed lines are labeled.
    var showsLineTools: Bool = false
    /// The playhead is inside this line (live transcript only).
    var isSpokenLine: Bool = false
    var onReport: (() -> Void)?
    var sentenceMenuPlayer: (any ClipPlayer)? = nil
    var karaokeTime: Double? = nil
    var lightPaper: Bool = false
    var measuresKaraokeRows = false
    /// Stable feed window: keep each sentence on one horizontal rail and move its words.
    var singleLineKaraoke = false

    @Environment(AppModel.self) private var app
    @Environment(WordLookupController.self) private var lookup
    @Environment(\.karaokeOnPicture) private var onPicture
    @Environment(\.amberImmersionKaraoke) private var amberImmersionKaraoke

    @State private var translationRevealed = false

    private var display: SubtitleDisplaySettings {
        if forceDenseAids && !respectsProfileDisplay { return LearningMode.beginner.display }
        return app.profile.subtitleDisplay
    }

    private func sentenceMenu(line: Line, player: any ClipPlayer) -> some View {
        let start = max(0, line.start)
        let end = min(player.duration, line.end)
        let range = start.isFinite && end.isFinite && end > start ? start...end : nil
        let isLooping = range != nil && player.loopRange == range

        return Menu {
            if line.tokens.contains(where: \.tappable) {
                Button("Save words from this sentence", systemImage: "rectangle.stack.badge.plus") {
                    if app.saveLine(clip: clip, lineIndex: lineIndex) > 0 { Haptics.success() }
                }
            }
            Section("Karaoke display") {
                Toggle("Furigana", isOn: Binding(
                    get: { app.profile.furiganaMode != .off },
                    set: { app.setFuriganaMode($0 ? .on : .off) }
                ))
                Toggle("Romaji", isOn: Binding(
                    get: { app.profile.showRomaji },
                    set: { app.setShowRomaji($0) }
                ))
                Toggle("English translation", isOn: Binding(
                    get: { app.profile.subtitleDisplay.english != .hidden },
                    set: { app.setEnglishVisibility($0 ? .shown : .hidden) }
                ))
            }
            if let range {
                Button(isLooping ? "Stop looping sentence" : "Loop sentence", systemImage: "repeat") {
                    Haptics.selection()
                    if player.loopRange == range {
                        player.setLoop(nil)
                    } else {
                        player.setLoop(range)
                        player.seek(to: range.lowerBound)
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .rotationEffect(.degrees(90))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(onPicture ? Color.white : Color.primary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Sentence options")
        .accessibilityHint(line.text)
    }

    var body: some View {
        if let line = clip.lines[safe: lineIndex] {
            let wordTiming = amberImmersionKaraoke && karaokeTime != nil && line.hasWordTiming
            HStack(alignment: .top, spacing: 2) {
            VStack(alignment: .leading, spacing: forceDenseAids ? Spacing.s : Spacing.m) {
                if display.japanese {
                    if singleLineKaraoke {
                        ScrollViewReader { proxy in
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(alignment: .bottom, spacing: forceDenseAids ? 6 : 4) {
                                    ForEach(Array(line.tokens.enumerated()), id: \.offset) { index, token in
                                        karaokeTokenCell(token, index: index, wordTiming: wordTiming)
                                            .id(index)
                                    }
                                }
                                .padding(.horizontal, 2)
                                .fixedSize(horizontal: true, vertical: false)
                            }
                            .scrollDisabled(true)
                            .onChange(of: spokenTokenIndex) { _, tokenIndex in
                                guard let tokenIndex else { return }
                                if respectsProfileDisplay {
                                    withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.24)) {
                                        proxy.scrollTo(tokenIndex, anchor: .center)
                                    }
                                } else {
                                    proxy.scrollTo(tokenIndex, anchor: .center)
                                }
                            }
                            .onAppear {
                                if let spokenTokenIndex { proxy.scrollTo(spokenTokenIndex, anchor: .center) }
                            }
                        }
                        .coordinateSpace(name: KaraokeRowsSpace(index: lineIndex))
                    } else {
                        // Non-feed transcripts can still wrap naturally for reading and lookup.
                        FlowLayout(spacing: forceDenseAids ? 6 : 4, lineSpacing: forceDenseAids ? 14 : 12) {
                            ForEach(Array(line.tokens.enumerated()), id: \.offset) { index, token in
                                karaokeTokenCell(token, index: index, wordTiming: wordTiming)
                            }
                        }
                        .coordinateSpace(name: KaraokeRowsSpace(index: lineIndex))
                    }
                }
                if showsTranslation && !line.translation.isEmpty && display.english != .hidden {
                    if display.english == .shown || translationRevealed {
                        Text(line.translation)
                            .font(forceDenseAids || raisedCard ? Font.footnote : Font.subheadline)
                            .fontWeight(.regular)
                            .foregroundStyle((lightPaper ? Color(hex: "#454545") : LearningInk.english(onPicture: onPicture)).opacity(onPicture ? 0.92 : 1))
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .lineLimit(singleLineKaraoke ? 1 : nil)
                            .fixedSize(horizontal: false, vertical: true)
                            .shadow(color: onPicture ? .black.opacity(0.5) : .clear, radius: 2, y: 1)
                            .textGlow(
                                onPicture ? Color.white : LearningInk.glow,
                                level: app.profile.fullTextGlow ? app.profile.glow : .off
                            )
                    }
                    if display.english == .onTap {
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) { translationRevealed.toggle() }
                        } label: {
                            Label(translationRevealed ? "Hide English" : "Show English",
                                  systemImage: translationRevealed ? "eye.slash" : "eye")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .frame(minHeight: 44)
                                .background(Color.primary.opacity(0.07), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Reveals the stored translation for this sentence")
                    }
                }
                if showsLineTools {
                    HStack(spacing: 8) {
                        Text("\(formatClock(line.start)) – \(formatClock(line.end))")
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        if !line.hasWordTiming {
                            Text("Sentence sync")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .accessibilityLabel("Highlighting follows the sentence, not each word")
                        }
                        Spacer(minLength: 8)
                        Button {
                            Haptics.selection()
                            SpeechService.shared.speak(line.text)
                        } label: {
                            Image(systemName: "speaker.wave.2")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(LearningInk.spoken)
                                .frame(width: 36, height: 36)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Hear this line")
                        if let onReport {
                            Button {
                                Haptics.selection()
                                onReport()
                            } label: {
                                Image(systemName: "flag")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 36, height: 36)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Report an issue with this transcript line")
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let player = sentenceMenuPlayer,
               line.tokens.contains(where: { !$0.isPunctuation && !$0.surface.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                sentenceMenu(line: line, player: player)
            }
            }
            .padding(raisedCard ? Spacing.m : 0)
            .padding(.leading, showsLineTools || !line.hasWordTiming ? 10 : 0)
            .overlay(alignment: .leading) {
                // Sentence-timed lines: the whole line is the karaoke cursor.
                if sentenceSynced(line) {
                    Capsule()
                        .fill(LearningInk.spoken)
                        .frame(width: 3)
                        .padding(.vertical, raisedCard ? Spacing.m : 2)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay {
                if sentenceSynced(line) {
                    sentenceCursor
                        .allowsHitTesting(false)
                }
            }
            .background {
                if raisedCard {
                    // Quiet plate — words and the green cursor carry the hierarchy, not the chrome.
                    // Light themes get a white plate so their dark ink (translation, times) stays readable.
                    let lightPlate = JojoPalette.scheme == .light
                    RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                        .fill(lightPlate ? Color.white : Color.black.opacity(0.88))
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                                .strokeBorder(lightPlate ? Color.black.opacity(0.08) : Color.white.opacity(0.1), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(lightPlate ? 0.06 : 0), radius: 10, y: 3)
                }
            }
            .opacity(isActive ? 1 : (onPicture ? 0.42 : 0.72))
            .animation(respectsProfileDisplay ? nil : .easeOut(duration: 0.2), value: isActive)
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: KaraokeLineHeightPreference.self,
                        value: [lineIndex: geometry.size.height]
                    )
                }
            }
            .onChange(of: isActive) { _, _ in translationRevealed = false }
            .onChange(of: display.english) { _, _ in translationRevealed = false }
            .onChange(of: line) { _, _ in translationRevealed = false }
            .onChange(of: "\(clip.id):\(lineIndex)") { _, _ in translationRevealed = false }
        }
    }

    @ViewBuilder
    private var sentenceCursor: some View {
        let outline = RoundedRectangle(cornerRadius: raisedCard ? Radius.card : 10, style: .continuous)
            .strokeBorder(LearningInk.spoken, lineWidth: 1.8)
        outline.modifier(KaraokeCursorPulse(glowEnabled: app.profile.glow != .off))
    }

    private func sentenceSynced(_ line: Line) -> Bool {
        isSpokenLine && !line.hasWordTiming
    }

    private func state(for index: Int) -> TokenVisualState {
        if lookup.isSelected(clipId: clip.id, lineIndex: lineIndex, tokenIndex: index) { return .selected }
        if spokenTokenIndex == index { return .spoken }
        return .normal
    }

    private func karaokeTokenCell(_ token: Token, index: Int, wordTiming: Bool) -> some View {
        KaraokeTokenCell(
            token: token,
            state: state(for: index),
            isLookedUp: app.isLookedUp(token),
            familiarity: app.wordState(for: token),
            highlight: highlightSurface.map { matches(token, $0) } ?? false,
            pulse: isPulsing && pulseTokenIndex == index,
            tooltip: pulseTokenIndex == index ? tooltip : nil,
            showFurigana: display.furiganaMode.shows(for: app.wordState(for: token)),
            showRomaji: display.romaji,
            tapEnabled: display.tapWords,
            forceWordTaps: display.tapWords,
            minimalStyling: display.minimalJapanese,
            stablePlaybackHighlight: respectsProfileDisplay,
            lightPaper: lightPaper,
            playbackCompleted: wordTiming && token.end <= (karaokeTime ?? 0),
            gloss: showsInlineGloss ? inlineGloss(for: token, index: index) : nil,
            anchor: KaraokeWordAnchor(clipID: clip.id, lineIndex: lineIndex, tokenIndex: index),
            measuresRowFrames: measuresKaraokeRows,
            rowLineIndex: lineIndex,
            tracksWordFrame: !singleLineKaraoke && respectsProfileDisplay && spokenTokenIndex == index,
            anchorClipID: clip.id,
            onTap: {
                withAnimation(Motion.popupSpring) {
                    lookup.select(token: token, tokenIndex: index, lineIndex: lineIndex, clip: clip, app: app)
                }
            }
        )
    }

    private func matches(_ token: Token, _ query: String) -> Bool {
        SearchMatcher.tokenMatches(token, query: query)
    }

    /// Inline glosses only in Beginner (or when every reading aid is on).
    private var showsInlineGloss: Bool {
        // The feed already shows the sentence translation. Inserting a different
        // gloss under each spoken word changes wrapping and makes the card jump.
        !respectsProfileDisplay && (display.learningMode == .beginner
            || (display.furigana && display.romaji && display.english == .shown))
    }

    private func inlineGloss(for token: Token, index: Int) -> String? {
        guard token.tappable else { return nil }
        let active = spokenTokenIndex == index
            || lookup.isSelected(clipId: clip.id, lineIndex: lineIndex, tokenIndex: index)
        guard active else { return nil }
        if let grammar = GrammarFormNotes.note(for: token) {
            return grammar.meaning
        }
        return token.definitions.first
    }
}

/// Reports one karaoke row's frame through the `KaraokeRowFrames` preference.
/// Its own small view type so the enclosing line body type-checks quickly.
private struct KaraokeRowFrameReader: View {
    let lineIndex: Int

    var body: some View {
        GeometryReader { geometry in
            let rowFrame = geometry.frame(in: .named(KaraokeRowsSpace(index: lineIndex)))
            Color.clear.preference(
                key: KaraokeRowFrames.self,
                value: [lineIndex: [rowFrame]]
            )
        }
    }
}

/// One karaoke token plus its optional inline gloss and frame reporting.
/// A dedicated view type with explicit properties keeps the transcript line's
/// body inside the compiler's type-checking budget.
private struct KaraokeTokenCell: View {
    let token: Token
    let state: TokenVisualState
    let isLookedUp: Bool
    let familiarity: SRSState?
    let highlight: Bool
    let pulse: Bool
    let tooltip: String?
    let showFurigana: Bool
    let showRomaji: Bool
    let tapEnabled: Bool
    let forceWordTaps: Bool
    let minimalStyling: Bool
    let stablePlaybackHighlight: Bool
    let lightPaper: Bool
    let playbackCompleted: Bool
    /// Beginner-only gloss under the spoken or selected word; nil reserves no space.
    let gloss: String?
    let anchor: KaraokeWordAnchor
    let measuresRowFrames: Bool
    let rowLineIndex: Int
    let tracksWordFrame: Bool
    let anchorClipID: String
    let onTap: () -> Void

    @Environment(AppModel.self) private var app
    @Environment(\.karaokeOnPicture) private var onPicture

    var body: some View {
        VStack(spacing: 1) {
            TokenView(
                token: token,
                state: state,
                isLookedUp: isLookedUp,
                familiarity: familiarity,
                highlight: highlight,
                pulse: pulse,
                tooltip: tooltip,
                showFurigana: showFurigana,
                showRomaji: showRomaji,
                tapEnabled: tapEnabled,
                forceWordTaps: forceWordTaps,
                minimalStyling: minimalStyling,
                stablePlaybackHighlight: stablePlaybackHighlight,
                playbackCompleted: playbackCompleted,
                lightPaper: lightPaper,
                onTap: onTap
            )
            if let gloss {
                Text(gloss)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(LearningInk.english)
                    .textGlow(
                        onPicture ? Color.white : LearningInk.glow,
                        level: app.profile.fullTextGlow ? app.profile.glow : .off
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: 120)
            }
        }
        .id(anchor)
        .background {
            if measuresRowFrames {
                KaraokeRowFrameReader(lineIndex: rowLineIndex)
            }
            if tracksWordFrame {
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: KaraokeWordGeometryPreference.self,
                        value: KaraokeWordGeometry(
                            anchor: anchor,
                            frame: geometry.frame(in: .named(KaraokeWordAnchor.spaceName(for: anchorClipID)))
                        )
                    )
                }
            }
        }
    }
}

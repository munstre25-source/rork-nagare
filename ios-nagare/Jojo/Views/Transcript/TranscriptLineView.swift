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
    /// Feed immersive: always furigana + romaji + JP/EN regardless of profile toggles.
    var forceDenseAids: Bool = false
    /// Kiku raised card behind the current karaoke line.
    var raisedCard: Bool = false
    /// Time range and a speaker, the way the feed lines are labeled.
    var showsLineTools: Bool = false

    @Environment(AppModel.self) private var app
    @Environment(WordLookupController.self) private var lookup

    private var subtitleMode: SubtitleMode {
        forceDenseAids ? .both : app.profile.subtitles
    }
    private var showFurigana: Bool { forceDenseAids || app.profile.showFurigana }
    private var showRomaji: Bool { forceDenseAids || app.profile.showRomaji }

    var body: some View {
        if let line = clip.lines[safe: lineIndex] {
            VStack(alignment: .leading, spacing: forceDenseAids ? Spacing.s : Spacing.m) {
                if subtitleMode.showsJapanese {
                    FlowLayout(spacing: 2, lineSpacing: forceDenseAids ? 10 : 12) {
                        ForEach(Array(line.tokens.enumerated()), id: \.offset) { index, token in
                            TokenView(
                                token: token,
                                state: state(for: index),
                                isLookedUp: app.isLookedUp(token),
                                familiarity: app.wordState(for: token),
                                highlight: highlightSurface.map { matches(token, $0) } ?? false,
                                pulse: isPulsing && pulseTokenIndex == index,
                                tooltip: pulseTokenIndex == index ? tooltip : nil,
                                showFurigana: showFurigana,
                                showRomaji: showRomaji,
                                onTap: {
                                    withAnimation(Motion.popupSpring) {
                                        lookup.select(token: token, tokenIndex: index, lineIndex: lineIndex, clip: clip, app: app)
                                    }
                                }
                            )
                        }
                    }
                }
                if showsTranslation && subtitleMode.showsEnglish {
                    Text(line.translation)
                        .font(forceDenseAids || raisedCard ? Font.footnote : Font.body)
                        .fontWeight(raisedCard ? .regular : .semibold)
                        .foregroundStyle(LearningInk.english.opacity(raisedCard ? 0.78 : 1))
                        .lineLimit(4)
                        .minimumScaleFactor(0.85)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if showsLineTools {
                    HStack(spacing: 8) {
                        Text("\(formatClock(line.start)) – \(formatClock(line.end))")
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
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
                    }
                }
            }
            .padding(raisedCard ? Spacing.m : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if raisedCard {
                    // Quiet dark plate — words and the green cursor carry the hierarchy, not the chrome.
                    RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                        .fill(Color.black.opacity(0.88))
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                        )
                }
            }
            .opacity(isActive ? 1 : 0.82)
            .animation(.easeOut(duration: 0.2), value: isActive)
        }
    }

    private func state(for index: Int) -> TokenVisualState {
        if lookup.isSelected(clipId: clip.id, lineIndex: lineIndex, tokenIndex: index) { return .selected }
        if spokenTokenIndex == index { return .spoken }
        return .normal
    }

    private func matches(_ token: Token, _ query: String) -> Bool {
        SearchMatcher.tokenMatches(token, query: query)
    }
}

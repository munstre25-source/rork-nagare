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
                                highlight: highlightSurface.map { matches(token, $0) } ?? false,
                                pulse: isPulsing && pulseTokenIndex == index,
                                tooltip: pulseTokenIndex == index ? tooltip : nil,
                                showFurigana: showFurigana,
                                showRomaji: showRomaji,
                                onTap: {
                                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                                        lookup.select(token: token, tokenIndex: index, lineIndex: lineIndex, clip: clip, app: app)
                                    }
                                }
                            )
                        }
                    }
                }
                if showsTranslation && subtitleMode.showsEnglish {
                    Text(line.translation)
                        .font(forceDenseAids ? .subheadline : .body)
                        .foregroundStyle(Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .opacity(isActive ? 1 : 0.4)
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

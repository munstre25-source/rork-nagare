import SwiftUI

/// Persistent transcript under the video. Auto-follows the current line; the green cursor tracks each spoken word.
struct LiveTranscriptPanel: View {
    let clip: Clip
    let currentLine: Int
    let spokenToken: Int?
    var pulseTokenIndex: Int?
    var isPulsing: Bool = false
    var tooltip: String?
    var onlyCurrentLine: Bool = false
    /// Feed immersive mode: always show furigana + romaji + JP/EN.
    var forceDenseAids: Bool = false

    @Environment(WordLookupController.self) private var lookup

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    ForEach(visibleLines, id: \.self) { index in
                        TranscriptLineView(
                            clip: clip,
                            lineIndex: index,
                            spokenTokenIndex: index == currentLine ? spokenToken : nil,
                            pulseTokenIndex: index == currentLine ? pulseTokenIndex : nil,
                            isPulsing: isPulsing,
                            tooltip: index == currentLine ? tooltip : nil,
                            isActive: index == currentLine || lookup.selection?.lineIndex == index,
                            forceDenseAids: forceDenseAids
                        )
                        .id(index)
                    }
                }
                .padding(.horizontal, Spacing.l)
                .padding(.top, tooltip == nil ? (forceDenseAids ? Spacing.m : Spacing.l) : 48)
                .padding(.bottom, Spacing.l)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDisabled(onlyCurrentLine)
            .onChange(of: currentLine) { _, newValue in
                guard lookup.selection == nil else { return }
                withAnimation(.easeInOut(duration: 0.35)) {
                    proxy.scrollTo(newValue, anchor: .top)
                }
            }
            .onAppear { proxy.scrollTo(currentLine, anchor: .top) }
        }
        .background(Color.bgSurfaceDark)
    }

    private var visibleLines: [Int] {
        onlyCurrentLine ? [currentLine] : Array(clip.lines.indices)
    }
}

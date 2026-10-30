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
    /// Kiku window: current line plus the lines after it, no nested scroll.
    var windowMode: Bool = false
    /// How many lines after the current one stay on screen.
    var followingLines: Int = 1

    @Environment(WordLookupController.self) private var lookup
    @Namespace private var spokenNamespace

    var body: some View {
        Group {
            if windowMode {
                // Only whole lines are ever shown: drop following lines until everything fits,
                // and if even the current line is too tall (large text), let it scroll.
                // Nothing gets sliced off at the bottom edge.
                ViewThatFits(in: .vertical) {
                    ForEach(Array(stride(from: max(0, followingLines), through: 0, by: -1)), id: \.self) { extra in
                        paddedWindow(following: extra)
                    }
                    ScrollView(.vertical, showsIndicators: false) {
                        paddedWindow(following: 0)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else if onlyCurrentLine {
                lineStack
                    .padding(.horizontal, Spacing.l)
                    .padding(.top, tooltip == nil ? Spacing.m : 48)
                    .padding(.bottom, Spacing.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        lineStack
                            .padding(.horizontal, Spacing.l)
                            .padding(.top, tooltip == nil ? Spacing.l : 48)
                            .padding(.bottom, Spacing.l)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .onChange(of: currentLine) { _, newValue in
                        guard lookup.selection == nil else { return }
                        withAnimation(Motion.lineAdvance) {
                            proxy.scrollTo(newValue, anchor: .top)
                        }
                    }
                    .onAppear { proxy.scrollTo(currentLine, anchor: .top) }
                }
            }
        }
        .background(windowMode ? Color.clear : Color.bgSurfaceDark)
        .environment(\.spokenTokenNamespace, spokenNamespace)
    }

    private func paddedWindow(following: Int) -> some View {
        windowStack(following: following)
            .padding(.top, tooltip == nil ? Spacing.s : 40)
            .padding(.bottom, Spacing.m)
            .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var windowStack: some View { windowStack(following: followingLines) }

    private func windowStack(following: Int) -> some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            ForEach(windowLines(following: following), id: \.self) { index in
                TranscriptLineView(
                    clip: clip,
                    lineIndex: index,
                    spokenTokenIndex: index == currentLine ? spokenToken : nil,
                    pulseTokenIndex: index == currentLine ? pulseTokenIndex : nil,
                    isPulsing: isPulsing,
                    tooltip: index == currentLine ? tooltip : nil,
                    isActive: index == currentLine || lookup.selection?.lineIndex == index,
                    forceDenseAids: forceDenseAids,
                    // The active line keeps its plate so it stays distinct inside the panel.
                    raisedCard: index == currentLine,
                    showsLineTools: true,
                    isSpokenLine: index == currentLine
                )
                .id(index)
                .padding(.horizontal, index == currentLine ? 0 : Spacing.m)
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .move(edge: .top).combined(with: .opacity)
                ))
            }
        }
        .animation(Motion.lineAdvance, value: currentLine)
    }

    private var lineStack: some View {
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
                    forceDenseAids: forceDenseAids,
                    isSpokenLine: index == currentLine
                )
                .id(index)
            }
        }
    }

    private var visibleLines: [Int] {
        onlyCurrentLine ? [currentLine] : Array(clip.lines.indices)
    }

    /// Current line plus the following lines. The card stays in the centered column.
    private func windowLines(following: Int) -> [Int] {
        guard !clip.lines.isEmpty else { return [] }
        let start = min(max(0, currentLine), clip.lines.count - 1)
        let end = min(clip.lines.count - 1, start + max(0, following))
        return Array(start...end)
    }
}

/// Shared namespace so the spoken green outline can slide between tokens.
private struct SpokenTokenNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    var spokenTokenNamespace: Namespace.ID? {
        get { self[SpokenTokenNamespaceKey.self] }
        set { self[SpokenTokenNamespaceKey.self] = newValue }
    }
}

import SwiftUI

/// Persistent transcript under the video. Auto-follows the current line; the green cursor tracks each spoken word.
struct LiveTranscriptPanel: View {
    let clip: Clip
    let currentLine: Int
    let spokenToken: Int?
    var isPlaying: Bool = false
    var currentTime: Double = 0
    var pulseTokenIndex: Int?
    var isPulsing: Bool = false
    var tooltip: String?
    var onlyCurrentLine: Bool = false
    /// Keep feed typography compact; legacy callers can also force every aid on.
    var forceDenseAids: Bool = false
    /// The immersive feed keeps compact typography while honoring Profile display choices.
    var respectsProfileDisplay: Bool = false
    var onReportLine: ((Int) -> Void)?
    /// Kiku window: current line plus the lines after it, no nested scroll.
    var windowMode: Bool = false
    /// How many lines after the current one stay on screen.
    var followingLines: Int = 1
    var showsLineTools: Bool = true

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
                    // The reset id must live inside a wrapper: an explicit id directly on a
                    // ViewThatFits child collides with the ForEach ids (0...n) and SwiftUI traps.
                    VStack(spacing: 0) {
                        ScrollView(.vertical, showsIndicators: true) {
                            paddedWindow(following: 0)
                        }
                        .scrollBounceBehavior(.basedOnSize)
                        .id(currentLine) // New sentences start at the top after a long-line scroll.
                    }
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
        // ViewThatFits builds several candidates. Sharing a moving outline between
        // them causes competing geometry updates while karaoke advances.
        .environment(\.spokenTokenNamespace, windowMode ? nil : spokenNamespace)
        .transaction { transaction in
            if windowMode {
                // Stop inherited layout/spring animations. Word highlights below
                // supply their own short color fade without moving any text.
                transaction.animation = nil
            }
        }
    }

    private func paddedWindow(following: Int) -> some View {
        windowStack(following: following)
            .padding(.top, tooltip == nil ? Spacing.s : 40)
            .padding(.bottom, Spacing.m)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .fixedSize(horizontal: false, vertical: true)
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
                    // Preview the next Japanese phrase without revealing its English
                    // before the playhead reaches it. The active phrase owns its translation.
                    showsTranslation: index == currentLine,
                    isActive: index == currentLine || lookup.selection?.lineIndex == index,
                    forceDenseAids: forceDenseAids,
                    respectsProfileDisplay: respectsProfileDisplay,
                    // The active line keeps its plate so it stays distinct inside the panel.
                    raisedCard: index == currentLine,
                    showsLineTools: showsLineTools,
                    isSpokenLine: isPlayingLine(index),
                    onReport: { onReportLine?(index) }
                )
                .id(index)
                .padding(.horizontal, index == currentLine ? 0 : Spacing.m)
            }
        }
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
                    respectsProfileDisplay: respectsProfileDisplay,
                    isSpokenLine: isPlayingLine(index),
                    onReport: { onReportLine?(index) }
                )
                .id(index)
            }
        }
    }

    private func isPlayingLine(_ index: Int) -> Bool {
        guard isPlaying, index == currentLine, let line = clip.lines[safe: index] else { return false }
        return currentTime >= line.start && currentTime < line.end
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

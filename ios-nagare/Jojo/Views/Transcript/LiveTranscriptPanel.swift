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
    /// Kiku window: previous + current + up to 3 following lines, no nested ScrollView.
    var windowMode: Bool = false

    @Environment(WordLookupController.self) private var lookup
    @Namespace private var spokenNamespace

    var body: some View {
        Group {
            if windowMode {
                windowStack
                    .padding(.horizontal, Spacing.l)
                    .padding(.top, tooltip == nil ? Spacing.s : 40)
                    .padding(.bottom, Spacing.m)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
        .background(Color.bgSurfaceDark)
        .environment(\.spokenTokenNamespace, spokenNamespace)
    }

    private var windowStack: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            ForEach(windowLines, id: \.self) { index in
                TranscriptLineView(
                    clip: clip,
                    lineIndex: index,
                    spokenTokenIndex: index == currentLine ? spokenToken : nil,
                    pulseTokenIndex: index == currentLine ? pulseTokenIndex : nil,
                    isPulsing: isPulsing,
                    tooltip: index == currentLine ? tooltip : nil,
                    isActive: index == currentLine || lookup.selection?.lineIndex == index,
                    forceDenseAids: forceDenseAids,
                    raisedCard: index == currentLine
                )
                .id(index)
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
                    forceDenseAids: forceDenseAids
                )
                .id(index)
            }
        }
    }

    private var visibleLines: [Int] {
        onlyCurrentLine ? [currentLine] : Array(clip.lines.indices)
    }

    /// Previous (if any) + current + up to 3 following lines.
    private var windowLines: [Int] {
        guard !clip.lines.isEmpty else { return [] }
        let start = max(0, currentLine - 1)
        let end = min(clip.lines.count - 1, currentLine + 3)
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

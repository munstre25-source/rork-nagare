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
    /// Bounded feed viewport with a persistent, smoothly following transcript.
    var windowMode: Bool = false
    var showsLineTools: Bool = true

    @Environment(WordLookupController.self) private var lookup
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var spokenNamespace

    var body: some View {
        Group {
            if windowMode {
                feedTranscript
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
        .environment(\.spokenTokenNamespace, windowMode ? nil : spokenNamespace)
    }

    /// Keep every sentence's identity and size stable. Only the scroll offset moves;
    /// the video, panel and word wrapping never participate in a line transition.
    private var feedTranscript: some View {
        GeometryReader { viewport in
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    // Exact row positions avoid estimated-height corrections during a swipe.
                    VStack(alignment: .leading, spacing: Spacing.m) {
                        ForEach(clip.lines.indices, id: \.self) { index in
                            TranscriptLineView(
                                clip: clip,
                                lineIndex: index,
                                spokenTokenIndex: index == currentLine ? spokenToken : nil,
                                pulseTokenIndex: index == currentLine ? pulseTokenIndex : nil,
                                isPulsing: isPulsing,
                                tooltip: index == currentLine ? tooltip : nil,
                                showsTranslation: true,
                                translationIsVisible: index <= currentLine,
                                isActive: true,
                                forceDenseAids: forceDenseAids,
                                respectsProfileDisplay: respectsProfileDisplay,
                                raisedCard: false,
                                showsLineTools: showsLineTools,
                                isSpokenLine: isPlayingLine(index),
                                onReport: { onReportLine?(index) }
                            )
                            .padding(.horizontal, Spacing.m)
                            .id(index)
                        }
                    }
                    .padding(.top, tooltip == nil ? Spacing.s : 40)
                    // The last sentence can still settle at the top of the viewport.
                    .padding(.bottom, max(0, viewport.size.height - 44))
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollDisabled(lookup.isPresented)
                .onChange(of: currentLine) { _, index in
                    guard !lookup.isPresented else { return }
                    follow(index, proxy: proxy)
                }
                .onChange(of: lookup.isPresented) { _, presented in
                    if !presented { follow(currentLine, proxy: proxy) }
                }
                .onChange(of: viewport.size) { _, _ in proxy.scrollTo(currentLine, anchor: .top) }
                .onChange(of: clip.id) { _, _ in proxy.scrollTo(currentLine, anchor: .top) }
                .onAppear { proxy.scrollTo(currentLine, anchor: .top) }
            }
        }
        .background(Color.bgSurfaceDark, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    private func follow(_ index: Int, proxy: ScrollViewProxy) {
        guard clip.lines.indices.contains(index) else { return }
        if reduceMotion {
            proxy.scrollTo(index, anchor: .top)
        } else {
            withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.45)) {
                proxy.scrollTo(index, anchor: .top)
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

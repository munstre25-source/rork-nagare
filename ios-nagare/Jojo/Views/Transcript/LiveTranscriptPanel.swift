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
    @State private var lastEvaluatedWord: KaraokeWordAnchor?
    @State private var sentenceScrollUntil: Date = .distantPast

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
                .coordinateSpace(name: KaraokeWordAnchor.spaceName(for: clip.id))
                .scrollBounceBehavior(.basedOnSize)
                .scrollDisabled(lookup.isPresented)
                .onPreferenceChange(KaraokeWordGeometryPreference.self) { geometry in
                    guard !lookup.isPresented, let geometry,
                          geometry.anchor.clipID == clip.id,
                          geometry.anchor.lineIndex == currentLine,
                          geometry.anchor.tokenIndex == spokenToken,
                          geometry.anchor != lastEvaluatedWord else { return }
                    // Evaluate once per word, not once per animation frame.
                    lastEvaluatedWord = geometry.anchor
                    guard Date.now >= sentenceScrollUntil,
                          let edge = geometry.followEdge(viewportHeight: viewport.size.height) else { return }
                    let alignment: UnitPoint = edge == .top ? .top : .bottom
                    if reduceMotion {
                        proxy.scrollTo(geometry.anchor, anchor: alignment)
                    } else {
                        withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.25)) {
                            proxy.scrollTo(geometry.anchor, anchor: alignment)
                        }
                    }
                }
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
        lastEvaluatedWord = nil
        sentenceScrollUntil = Date.now.addingTimeInterval(reduceMotion ? 0 : 0.45)
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

/// Stable identities let the scroll view reveal wrapped words without replacing the sentence.
nonisolated struct KaraokeWordAnchor: Hashable, Sendable {
    let clipID: String
    let lineIndex: Int
    let tokenIndex: Int

    static func spaceName(for clipID: String) -> String { "karaoke-viewport-" + clipID }
}

nonisolated struct KaraokeWordGeometry: Equatable, Sendable {
    enum Edge: Equatable { case top, bottom }
    let anchor: KaraokeWordAnchor
    let frame: CGRect

    func followEdge(viewportHeight: CGFloat) -> Edge? {
        guard viewportHeight > 16, !frame.isEmpty,
              frame.minY.isFinite, frame.maxY.isFinite else { return nil }
        if frame.minY < 8 || frame.height > viewportHeight - 16 { return .top }
        if frame.maxY > viewportHeight - 8 { return .bottom }
        return nil
    }
}

nonisolated struct KaraokeWordGeometryPreference: PreferenceKey {
    static let defaultValue: KaraokeWordGeometry? = nil
    static func reduce(value: inout KaraokeWordGeometry?, nextValue: () -> KaraokeWordGeometry?) {
        if let next = nextValue() { value = next }
    }
}

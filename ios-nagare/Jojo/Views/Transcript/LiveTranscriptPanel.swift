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
    /// Portrait shorts: clear plate so a bottom gradient can show through the words.
    var onPicture: Bool = false

    @Environment(WordLookupController.self) private var lookup
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var spokenNamespace
    @State private var lastEvaluatedWord: KaraokeWordAnchor?
    @State private var sentenceScrollUntil: Date = .distantPast
    @State private var measuredHeights: [Int: CGFloat] = [:]

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
        .background(windowMode || onPicture ? Color.clear : Color.bgSurfaceDark)
        .environment(\.spokenTokenNamespace, windowMode ? nil : spokenNamespace)
        .environment(\.karaokeOnPicture, onPicture)
    }

    /// At most three complete lines that fit the reading well. Scroll only when the current
    /// line alone is taller than the viewport so a spoken word can stay fully visible.
    private var feedTranscript: some View {
        GeometryReader { viewport in
            let spacing = Spacing.m
            let window = KaraokeReadingWindow.indices(
                current: currentLine,
                lineCount: clip.lines.count,
                heights: measuredHeights,
                spacing: spacing,
                viewportHeight: max(0, viewport.size.height - topPad - 8)
            )
            let currentAlone = window == [clampedCurrentLine]
            let currentHeight = measuredHeights[clampedCurrentLine] ?? 0
            let needsWordScroll = currentAlone && currentHeight > viewport.size.height + 0.5

            Group {
                if needsWordScroll {
                    scrollingCurrentLine(in: viewport.size)
                } else {
                    staticWindow(window, spacing: spacing)
                }
            }
            // Portrait band sits on the lower edge of the picture; the wide well keeps lines at the top.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: onPicture ? .bottom : .top)
            .onPreferenceChange(KaraokeLineHeightPreference.self) { heights in
                guard !heights.isEmpty else { return }
                var next = measuredHeights
                for (index, height) in heights where abs((next[index] ?? 0) - height) > 0.5 {
                    next[index] = height
                }
                if next != measuredHeights { measuredHeights = next }
            }
            .onChange(of: clip.id) { _, _ in
                measuredHeights = [:]
                lastEvaluatedWord = nil
            }
        }
        .background {
            if !onPicture {
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .fill(Color.bgSurfaceDark)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: onPicture ? 0 : Radius.card, style: .continuous))
        .clipped()
    }

    private var topPad: CGFloat { tooltip == nil ? Spacing.s : 40 }

    private var clampedCurrentLine: Int {
        guard !clip.lines.isEmpty else { return 0 }
        return min(max(0, currentLine), clip.lines.count - 1)
    }

    private func staticWindow(_ indices: [Int], spacing: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(indices, id: \.self) { index in
                windowLine(index)
                    .padding(.horizontal, Spacing.m)
            }
        }
        .padding(.top, topPad)
        .padding(.bottom, Spacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Keep the next/previous candidates mounted offscreen so heights stay warm for
        // the window calculator without painting into the next feed page.
        .background(alignment: .top) {
            measureNeighbors(of: indices)
        }
    }

    private func scrollingCurrentLine(in size: CGSize) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                windowLine(clampedCurrentLine)
                    .padding(.horizontal, Spacing.m)
                    .padding(.top, topPad)
                    .padding(.bottom, Spacing.s)
                    .id(clampedCurrentLine)
            }
            .clipped()
            .coordinateSpace(name: KaraokeWordAnchor.spaceName(for: clip.id))
            .scrollBounceBehavior(.basedOnSize)
            .scrollDisabled(lookup.isPresented)
            .onPreferenceChange(KaraokeWordGeometryPreference.self) { geometry in
                guard !lookup.isPresented, let geometry,
                      geometry.anchor.clipID == clip.id,
                      geometry.anchor.lineIndex == clampedCurrentLine,
                      geometry.anchor.tokenIndex == spokenToken,
                      geometry.anchor != lastEvaluatedWord else { return }
                lastEvaluatedWord = geometry.anchor
                guard Date.now >= sentenceScrollUntil,
                      let edge = geometry.followEdge(viewportHeight: size.height) else { return }
                let alignment: UnitPoint = edge == .top ? .top : .bottom
                if reduceMotion {
                    proxy.scrollTo(geometry.anchor, anchor: alignment)
                } else {
                    withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.25)) {
                        proxy.scrollTo(geometry.anchor, anchor: alignment)
                    }
                }
            }
            .onChange(of: currentLine) { _, _ in
                guard !lookup.isPresented else { return }
                follow(clampedCurrentLine, proxy: proxy)
            }
            .onChange(of: lookup.isPresented) { _, presented in
                if !presented { follow(clampedCurrentLine, proxy: proxy) }
            }
            .onChange(of: size.height) { _, _ in proxy.scrollTo(clampedCurrentLine, anchor: .top) }
            .onAppear { proxy.scrollTo(clampedCurrentLine, anchor: .top) }
        }
    }

    /// Measure previous/next at the real panel width so the window can grow when they fit.
    @ViewBuilder
    private func measureNeighbors(of visible: [Int]) -> some View {
        let neighbors = [clampedCurrentLine - 1, clampedCurrentLine + 1]
            .filter { clip.lines.indices.contains($0) && !visible.contains($0) }
        if !neighbors.isEmpty {
            VStack(spacing: 0) {
                ForEach(neighbors, id: \.self) { index in
                    windowLine(index)
                        .padding(.horizontal, Spacing.m)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .opacity(0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .frame(maxWidth: .infinity, maxHeight: 0, alignment: .top)
            .clipped()
        }
    }

    private func windowLine(_ index: Int) -> some View {
        TranscriptLineView(
            clip: clip,
            lineIndex: index,
            spokenTokenIndex: index == clampedCurrentLine ? spokenToken : nil,
            pulseTokenIndex: index == clampedCurrentLine ? pulseTokenIndex : nil,
            isPulsing: isPulsing,
            tooltip: index == clampedCurrentLine ? tooltip : nil,
            showsTranslation: true,
            isActive: index == clampedCurrentLine || lookup.selection?.lineIndex == index,
            forceDenseAids: forceDenseAids,
            respectsProfileDisplay: respectsProfileDisplay,
            raisedCard: false,
            showsLineTools: showsLineTools,
            isSpokenLine: isPlayingLine(index),
            onReport: { onReportLine?(index) }
        )
        .id(index)
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

private struct KaraokeOnPictureKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var spokenTokenNamespace: Namespace.ID? {
        get { self[SpokenTokenNamespaceKey.self] }
        set { self[SpokenTokenNamespaceKey.self] = newValue }
    }

    /// Portrait karaoke band: force white ink regardless of light/dark paper theme.
    var karaokeOnPicture: Bool {
        get { self[KaraokeOnPictureKey.self] }
        set { self[KaraokeOnPictureKey.self] = newValue }
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

nonisolated struct KaraokeLineHeightPreference: PreferenceKey {
    static let defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

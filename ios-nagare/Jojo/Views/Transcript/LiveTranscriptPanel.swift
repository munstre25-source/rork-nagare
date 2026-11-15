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
    var sentenceMenuPlayer: (any ClipPlayer)? = nil
    var landscapeReadingWindow = false
    var portraitReadingPlate = false
    var fadesTopLines = false

    private var usesReadingPlate: Bool { landscapeReadingWindow || portraitReadingPlate }
    private var karaokeFadeStops: [Gradient.Stop] {
        if fadesTopLines {
            return [
                .init(color: .clear, location: 0),
                .init(color: .black.opacity(0.35), location: 0.08),
                .init(color: .black, location: 0.2),
                .init(color: .black, location: 0.68),
                .init(color: .clear, location: 1)
            ]
        }
        return [
            .init(color: .black, location: 0),
            .init(color: .black, location: 0.68),
            .init(color: .clear, location: 1)
        ]
    }

    @Environment(WordLookupController.self) private var lookup
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var spokenNamespace
    @State private var lastEvaluatedWord: KaraokeWordAnchor?
    @State private var sentenceScrollUntil: Date = .distantPast
    @State private var transcriptBrowseUntil: Date = .distantPast
    @State private var measuredHeights: [Int: CGFloat] = [:]
    @State private var rowMetrics: [Int: KaraokeRowMetrics] = [:]

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

    /// Feed karaoke keeps three persistent slots. The active sentence is always the middle row.
    private var feedTranscript: some View {
        GeometryReader { viewport in
            let spacing = Spacing.m
            let availableHeight = max(0, viewport.size.height - topPad - 8)
            let window = KaraokeReadingWindow.indices(
                current: currentLine,
                lineCount: clip.lines.count,
                heights: measuredHeights,
                spacing: spacing,
                viewportHeight: availableHeight,
                visualRows: landscapeReadingWindow ? rowMetrics.mapValues(\.count) : nil
            )
            staticWindow(window, spacing: spacing)
            // Three equal slots keep the timed sentence fixed in the middle.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            // Let the last karaoke line dissolve into the dock / video scrim instead of
            // ending at a hard clipped edge. The panel background remains fully painted.
            .mask {
                LinearGradient(
                    stops: karaokeFadeStops,
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .onChange(of: clip.id) { _, _ in
                measuredHeights = [:]
                rowMetrics = [:]
                lastEvaluatedWord = nil
                transcriptBrowseUntil = .distantPast
            }
        }
        .background {
            if !onPicture {
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .fill(usesReadingPlate ? Color.karaokePaper : Color.bgSurfaceDark)
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
            ForEach(Array(indices.enumerated()), id: \.offset) { _, index in
                Group {
                    if clip.lines.indices.contains(index) {
                        windowLine(index)
                    } else {
                        Color.clear
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .accessibilityHidden(true)
                    }
                }
                .padding(.horizontal, Spacing.m)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
            }
        }
        .padding(.top, topPad)
        .padding(.bottom, Spacing.s)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func scrollingCurrentLine(in size: CGSize) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: landscapeReadingWindow) {
                LazyVStack(alignment: .leading, spacing: Spacing.m) {
                    ForEach(landscapeReadingWindow ? Array(clip.lines.indices) : [clampedCurrentLine], id: \.self) { index in
                        windowLine(index, fadesUpcoming: false)
                            .padding(.horizontal, Spacing.m)
                            .id(index)
                    }
                }
                .padding(.top, topPad)
                .padding(.bottom, Spacing.s)
            }
            .clipped()
            .coordinateSpace(name: KaraokeWordAnchor.spaceName(for: clip.id))
            .scrollBounceBehavior(.basedOnSize)
            .scrollDisabled(lookup.isPresented)
            .simultaneousGesture(
                DragGesture(minimumDistance: 6).onChanged { value in
                    guard landscapeReadingWindow,
                          abs(value.translation.height) > abs(value.translation.width) else { return }
                    transcriptBrowseUntil = isPlaying ? .now.addingTimeInterval(4) : .distantFuture
                }
            )
            .onPreferenceChange(KaraokeWordGeometryPreference.self) { geometry in
                guard !lookup.isPresented, let geometry,
                      Date.now >= transcriptBrowseUntil,
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
                guard !lookup.isPresented, Date.now >= transcriptBrowseUntil else { return }
                follow(clampedCurrentLine, proxy: proxy)
            }
            .onChange(of: isPlaying) { _, playing in
                guard landscapeReadingWindow, playing, !lookup.isPresented,
                      transcriptBrowseUntil == .distantFuture else { return }
                transcriptBrowseUntil = .distantPast
                follow(clampedCurrentLine, proxy: proxy)
            }
            .onChange(of: lookup.isPresented) { _, presented in
                if !presented, Date.now >= transcriptBrowseUntil { follow(clampedCurrentLine, proxy: proxy) }
            }
            .onChange(of: size.height) { _, _ in
                if Date.now >= transcriptBrowseUntil { proxy.scrollTo(clampedCurrentLine, anchor: .top) }
            }
            .onAppear { proxy.scrollTo(clampedCurrentLine, anchor: .top) }
        }
    }

    /// Measure adjacent lines at the real panel width so the centered window can grow when they fit.
    @ViewBuilder
    private func measureNeighbors(of visible: [Int]) -> some View {
        let neighbors = (-1..<KaraokeReadingWindow.maxLines).map { clampedCurrentLine + $0 }
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

    private func windowLine(_ index: Int, fadesUpcoming: Bool = true) -> some View {
        let line = TranscriptLineView(
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
            onReport: { onReportLine?(index) },
            sentenceMenuPlayer: sentenceMenuPlayer,
            karaokeTime: currentTime,
            lightPaper: usesReadingPlate && JojoPalette.scheme == .light,
            measuresKaraokeRows: false,
            singleLineKaraoke: windowMode
        )
        return Group {
            if fadesUpcoming && index > clampedCurrentLine {
                line.mask {
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black.opacity(0.78), location: 0.48),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .opacity(0.58)
            } else {
                line
            }
        }
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

nonisolated struct KaraokeRowsSpace: Hashable {
    let index: Int
}

nonisolated struct KaraokeRowFrames: PreferenceKey {
    static let defaultValue: [Int: [CGRect]] = [:]

    static func reduce(value: inout [Int: [CGRect]], nextValue: () -> [Int: [CGRect]]) {
        value.merge(nextValue(), uniquingKeysWith: +)
    }
}

private struct KaraokeRowMetrics: Equatable {
    let count: Int
    let threeRowHeight: CGFloat

    init(_ frames: [CGRect]) {
        var rows: [CGRect] = []
        for frame in frames.sorted(by: { $0.minY < $1.minY }) {
            if let last = rows.last, abs(last.minY - frame.minY) < 0.5 {
                rows[rows.count - 1] = last.union(frame)
            } else {
                rows.append(frame)
            }
        }
        count = rows.count
        let limit = KaraokeReadingWindow.maxLines
        if rows.count > limit {
            threeRowHeight = (0...(rows.count - limit)).map { first in
                rows[first + limit - 1].maxY - rows[first].minY
            }.min() ?? 0
        } else {
            threeRowHeight = rows.last?.maxY ?? 0
        }
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

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

    /// Feed karaoke is one natural transcript window. Japanese wraps at word boundaries,
    /// translations follow their sentence, and learners can browse vertically at any time.
    private var feedTranscript: some View {
        GeometryReader { viewport in
            scrollingTranscript(in: viewport.size)
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

    private func scrollingTranscript(in size: CGSize) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: landscapeReadingWindow) {
                LazyVStack(alignment: .leading, spacing: Spacing.m) {
                    ForEach(Array(clip.lines.indices), id: \.self) { index in
                        windowLine(index)
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
                    guard abs(value.translation.height) > abs(value.translation.width) else { return }
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
                      size.height > 16,
                      !geometry.frame.isEmpty,
                      geometry.frame.minY.isFinite,
                      geometry.frame.maxY.isFinite else { return }
                let anchor = followAnchor(for: geometry.anchor.lineIndex)
                if reduceMotion {
                    proxy.scrollTo(geometry.anchor, anchor: anchor)
                } else {
                    withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.25)) {
                        proxy.scrollTo(geometry.anchor, anchor: anchor)
                    }
                }
            }
            .onChange(of: currentLine) { _, _ in
                guard !lookup.isPresented, Date.now >= transcriptBrowseUntil else { return }
                follow(clampedCurrentLine, proxy: proxy)
            }
            .onChange(of: isPlaying) { _, playing in
                guard playing, !lookup.isPresented,
                      transcriptBrowseUntil == .distantFuture else { return }
                transcriptBrowseUntil = .distantPast
                follow(clampedCurrentLine, proxy: proxy)
            }
            .onChange(of: lookup.isPresented) { _, presented in
                if !presented, Date.now >= transcriptBrowseUntil { follow(clampedCurrentLine, proxy: proxy) }
            }
            .onChange(of: size.height) { _, _ in
                if Date.now >= transcriptBrowseUntil {
                    proxy.scrollTo(clampedCurrentLine, anchor: followAnchor(for: clampedCurrentLine))
                }
            }
            .onAppear {
                proxy.scrollTo(clampedCurrentLine, anchor: followAnchor(for: clampedCurrentLine))
            }
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
            lightPaper: usesReadingPlate && JojoPalette.scheme == .light
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
        let anchor = followAnchor(for: index)
        if reduceMotion {
            proxy.scrollTo(index, anchor: anchor)
        } else {
            withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.45)) {
                proxy.scrollTo(index, anchor: anchor)
            }
        }
    }

    /// The opening line begins at the top of the karaoke well. Once a previous line
    /// exists, the active line settles in the middle and the transcript moves around it.
    private func followAnchor(for lineIndex: Int) -> UnitPoint {
        lineIndex == clip.lines.startIndex ? .top : .center
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
    let anchor: KaraokeWordAnchor
    let frame: CGRect
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

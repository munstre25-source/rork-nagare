import SwiftUI

/// Reusable clip composition: channel → centered video → transcript.
/// Immersive feed matches Kiku: video sits in the vertical middle of the page so the next swipe replaces that center.
struct ClipStageView: View {
    let clip: Clip
    var videoAspect: CGFloat = 16 / 10
    var onlyCurrentLine: Bool = false
    var pulseTokenIndex: Int?
    var isPulsing: Bool = false
    var tooltip: String?
    var showsChannelRow: Bool = true
    var channelTrailing: AnyView?
    var showsRail: Bool = true
    /// Feed page: title-forward chrome, current-line karaoke, quieter chrome, centered stage.
    var immersiveFeed: Bool = false
    var nextClip: Clip? = nil
    var onActivate: () -> Void = {}
    var onFullscreen: (() -> Void)?
    var onInfo: (() -> Void)?
    var onShadowing: (() -> Void)?

    @Environment(PlaybackCoordinator.self) private var coordinator
    @Environment(WordLookupController.self) private var lookup
    @Environment(AppModel.self) private var app
    @State private var dragOffset: CGFloat = 0

    private var isPopupHere: Bool {
        lookup.selection?.clip.id == clip.id
    }

    private var resolvedAspect: CGFloat { immersiveFeed ? 16 / 9 : videoAspect }
    private var resolvedOnlyCurrent: Bool { immersiveFeed ? true : onlyCurrentLine }

    var body: some View {
        let player = coordinator.player(for: clip)
        VStack(spacing: 0) {
            if showsChannelRow {
                ChannelRow(
                    clip: clip,
                    trailing: channelTrailing,
                    showsFollow: !immersiveFeed,
                    emphasizesTitle: immersiveFeed
                )
                .padding(.vertical, immersiveFeed ? 4 : 10)
            }

            if immersiveFeed {
                // Kiku: black above the stage so the clip sits in the middle of the page.
                Spacer(minLength: 0)
            }

            ClipVideoView(
                clip: clip,
                player: player,
                showsRail: showsRail,
                compactChrome: immersiveFeed,
                onActivate: onActivate,
                onFullscreen: onFullscreen,
                onInfo: onInfo,
                onShadowing: immersiveFeed ? nil : onShadowing
            )
            .aspectRatio(resolvedAspect, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay { popupLayer }
            .zIndex(1)

            TranscriptSection(
                clip: clip,
                player: player,
                onlyCurrentLine: resolvedOnlyCurrent,
                pulseTokenIndex: pulseTokenIndex,
                isPulsing: isPulsing,
                tooltip: tooltip,
                forceDenseAids: false
            )
            .fixedSize(horizontal: false, vertical: true)

            if immersiveFeed {
                // Matching spacer below so the stage is vertically centered.
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: immersiveFeed ? .infinity : nil, alignment: immersiveFeed ? .center : .top)
        .onChange(of: isPopupHere) { _, presented in
            guard coordinator.activeClipId == clip.id else { return }
            if presented {
                coordinator.pauseForPopup()
            } else {
                coordinator.resumeAfterPopupIfNeeded()
            }
        }
    }

    @ViewBuilder
    private var popupLayer: some View {
        if isPopupHere {
            GeometryReader { geo in
                ZStack {
                    Color.black.opacity(0.28)
                        .contentShape(Rectangle())
                        .onTapGesture { dismiss() }
                    TapPopupCard(compact: true)
                        .frame(maxWidth: min(340, geo.size.width - 28))
                        // Keep most of the video visible around the card — Kiku-sized, not full-bleed.
                        .frame(maxHeight: geo.size.height * 0.62, alignment: .top)
                        .clipped()
                        .offset(y: max(0, dragOffset))
                        .gesture(
                            DragGesture(minimumDistance: 12)
                                .onChanged { value in dragOffset = value.translation.height }
                                .onEnded { value in
                                    if value.translation.height > 70 || value.predictedEndTranslation.height > 160 {
                                        dismiss()
                                    }
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { dragOffset = 0 }
                                }
                        )
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .transition(.asymmetric(
                insertion: .scale(scale: 0.92).combined(with: .opacity),
                removal: .opacity
            ))
        }
    }

    private func dismiss() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            lookup.dismiss()
        }
    }
}

/// Reads the player's time and feeds the transcript panel; isolated so only this subtree updates at playback rate.
struct TranscriptSection: View {
    let clip: Clip
    let player: (any ClipPlayer)?
    var onlyCurrentLine: Bool = false
    var pulseTokenIndex: Int?
    var isPulsing: Bool = false
    var tooltip: String?
    var forceDenseAids: Bool = false

    var body: some View {
        LiveTranscriptPanel(
            clip: clip,
            currentLine: player?.currentLineIndex ?? 0,
            spokenToken: player?.isPlaying == true ? player?.currentTokenIndex : nil,
            pulseTokenIndex: pulseTokenIndex,
            isPulsing: isPulsing,
            tooltip: tooltip,
            onlyCurrentLine: onlyCurrentLine,
            forceDenseAids: forceDenseAids
        )
    }
}

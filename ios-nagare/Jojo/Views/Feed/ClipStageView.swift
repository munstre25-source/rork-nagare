import SwiftUI

/// Reusable clip composition used by the Feed, the clip player screen and the onboarding demo:
/// channel row → video → live transcript, with the tap-to-understand popup floating above the transcript.
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
    /// TikTok-style feed page: title-forward chrome, dense karaoke, next-clip peek.
    var immersiveFeed: Bool = false
    var nextClip: Clip? = nil
    var onActivate: () -> Void = {}
    var onFullscreen: (() -> Void)?
    var onInfo: (() -> Void)?
    var onShadowing: (() -> Void)?

    @Environment(PlaybackCoordinator.self) private var coordinator
    @Environment(WordLookupController.self) private var lookup
    @State private var dragOffset: CGFloat = 0

    private var isPopupHere: Bool {
        lookup.selection?.clip.id == clip.id
    }

    private var resolvedAspect: CGFloat { immersiveFeed ? 16 / 9 : videoAspect }
    private var resolvedOnlyCurrent: Bool { immersiveFeed ? true : onlyCurrentLine }

    var body: some View {
        let player = coordinator.player(for: clip)
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                if showsChannelRow {
                    ChannelRow(
                        clip: clip,
                        trailing: channelTrailing,
                        emphasizesTitle: immersiveFeed
                    )
                    .padding(.vertical, immersiveFeed ? 6 : 10)
                }
                ClipVideoView(
                    clip: clip,
                    player: player,
                    showsRail: showsRail,
                    onActivate: onActivate,
                    onFullscreen: onFullscreen,
                    onInfo: onInfo,
                    onShadowing: onShadowing
                )
                .aspectRatio(resolvedAspect, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .overlay(alignment: .bottom) { popupLayer }
                .zIndex(1)
                TranscriptSection(
                    clip: clip,
                    player: player,
                    onlyCurrentLine: resolvedOnlyCurrent,
                    pulseTokenIndex: pulseTokenIndex,
                    isPulsing: isPulsing,
                    tooltip: tooltip,
                    forceDenseAids: immersiveFeed
                )
                .overlay {
                    if isPopupHere {
                        Color.black.opacity(0.5)
                            .contentShape(Rectangle())
                            .onTapGesture { dismiss() }
                            .transition(.opacity)
                            .accessibilityLabel("Dismiss word card")
                            .accessibilityAddTraits(.isButton)
                    }
                }
                if immersiveFeed {
                    // Reserve space so the next-clip peek doesn't cover karaoke.
                    Color.clear.frame(height: nextClip == nil || isPopupHere ? 8 : 64)
                }
            }

            if immersiveFeed, let nextClip, !isPopupHere {
                NextClipPeek(clip: nextClip)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
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
            ZStack(alignment: .bottom) {
                Color.black.opacity(0.35)
                    .contentShape(Rectangle())
                    .onTapGesture { dismiss() }
                TapPopupCard()
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Spacing.m)
                    .offset(y: 64 + max(0, dragOffset))
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
            .transition(.asymmetric(
                insertion: .scale(scale: 0.92, anchor: .bottom).combined(with: .opacity).combined(with: .offset(y: 30)),
                removal: .opacity.combined(with: .offset(y: 40))
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

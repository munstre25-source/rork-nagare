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
    var onActivate: () -> Void = {}
    var onFullscreen: (() -> Void)?
    var onInfo: (() -> Void)?

    @Environment(PlaybackCoordinator.self) private var coordinator
    @Environment(WordLookupController.self) private var lookup
    @State private var dragOffset: CGFloat = 0

    private var isPopupHere: Bool {
        lookup.selection?.clip.id == clip.id
    }

    var body: some View {
        let player = coordinator.player(for: clip)
        VStack(spacing: 0) {
            if showsChannelRow {
                ChannelRow(clip: clip, trailing: channelTrailing)
                    .padding(.vertical, 10)
            }
            ClipVideoView(
                clip: clip,
                player: player,
                showsRail: showsRail,
                onActivate: onActivate,
                onFullscreen: onFullscreen,
                onInfo: onInfo
            )
            .aspectRatio(videoAspect, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .bottom) { popupLayer }
            .zIndex(1)
            TranscriptSection(
                clip: clip,
                player: player,
                onlyCurrentLine: onlyCurrentLine,
                pulseTokenIndex: pulseTokenIndex,
                isPulsing: isPulsing,
                tooltip: tooltip
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

    var body: some View {
        LiveTranscriptPanel(
            clip: clip,
            currentLine: player?.currentLineIndex ?? 0,
            spokenToken: player?.isPlaying == true ? player?.currentTokenIndex : nil,
            pulseTokenIndex: pulseTokenIndex,
            isPulsing: isPulsing,
            tooltip: tooltip,
            onlyCurrentLine: onlyCurrentLine
        )
    }
}

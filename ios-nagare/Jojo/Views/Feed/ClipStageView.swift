import SwiftUI

/// Reusable clip composition matching kiku demo2 For You:
/// video → action row → karaoke, dictionary card centered over the stage.
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
    /// Feed page: Kiku For You layout (video + action strip + karaoke).
    var immersiveFeed: Bool = false
    /// When true, the video takes the upper half of the page. When false, it shrinks so the transcript leads.
    var videoExpanded: Bool = true
    var onToggleVideoSize: (() -> Void)? = nil
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

    /// Landscape player that leaves room for karaoke (kiku demo2).
    private var resolvedAspect: CGFloat { immersiveFeed ? 16 / 10 : videoAspect }

    /// Feed pages pass a resize control. Fullscreen and previews keep the fixed aspect.
    private var usesFlexibleVideo: Bool { immersiveFeed && onToggleVideoSize != nil }

    var body: some View {
        Group {
            if usesFlexibleVideo {
                GeometryReader { geo in
                    stage(videoHeight: videoHeight(in: geo.size))
                }
            } else {
                stage(videoHeight: nil)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: immersiveFeed ? .infinity : nil, alignment: .top)
        .background(usesFlexibleVideo ? Color.canvas : (immersiveFeed ? Color.bgPlayer : Color.clear))
        .overlay {
            if isPopupHere { popupLayer }
        }
        .clipped()
        .onChange(of: isPopupHere) { _, presented in
            guard coordinator.activeClipId == clip.id else { return }
            if presented {
                coordinator.pauseForPopup()
            } else {
                coordinator.resumeAfterPopupIfNeeded()
            }
        }
    }

    private func videoHeight(in size: CGSize) -> CGFloat {
        let natural = size.width * 10 / 16
        let expanded = videoExpanded && !isPopupHere
        if expanded {
            return min(natural, max(180, size.height * 0.52))
        }
        return min(natural * 0.62, max(132, size.height * 0.30))
    }

    @ViewBuilder
    private func stage(videoHeight: CGFloat?) -> some View {
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

            ZStack(alignment: .bottomTrailing) {
                ClipVideoView(
                    clip: clip,
                    player: player,
                    showsControls: !immersiveFeed,
                    showsRail: immersiveFeed ? false : showsRail,
                    compactChrome: immersiveFeed,
                    onActivate: onActivate,
                    onFullscreen: onFullscreen,
                    onInfo: immersiveFeed ? nil : onInfo,
                    onShadowing: immersiveFeed ? nil : onShadowing
                )
                .modifier(ClipVideoFrame(height: videoHeight, aspect: resolvedAspect))

                if let onToggleVideoSize, !isPopupHere {
                    Button(action: onToggleVideoSize) {
                        Image(systemName: videoExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(.black.opacity(0.55), in: Circle())
                    }
                    .padding(10)
                    .accessibilityLabel(videoExpanded ? "Minimize video" : "Maximize video")
                }
            }

            if immersiveFeed {
                ClipActionRow(
                    clip: clip,
                    player: player,
                    onInfo: onInfo,
                    onShadowing: onShadowing
                )
            }

            if usesFlexibleVideo {
                transcript(player: player)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                transcript(player: player)
                    .frame(maxWidth: .infinity, maxHeight: immersiveFeed ? .infinity : nil, alignment: .top)
            }
        }
    }

    private func transcript(player: (any ClipPlayer)?) -> some View {
        TranscriptSection(
            clip: clip,
            player: player,
            onlyCurrentLine: immersiveFeed ? false : onlyCurrentLine,
            pulseTokenIndex: pulseTokenIndex,
            isPulsing: isPulsing,
            tooltip: tooltip,
            forceDenseAids: immersiveFeed,
            windowMode: immersiveFeed
        )
    }

    /// Centered mid-stage like kiku demo2 (~6s); never cropped to the video bounds.
    private var popupLayer: some View {
        ZStack {
            Color.black.opacity(0.18)
                .contentShape(Rectangle())
                .onTapGesture { dismiss() }
            TapPopupCard(compact: true)
                .padding(.horizontal, 14)
                .frame(maxWidth: 340)
                .fixedSize(horizontal: false, vertical: true)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.asymmetric(
            insertion: .scale(scale: 0.94).combined(with: .opacity).combined(with: .offset(y: 16)),
            removal: .opacity
        ))
    }

    private func dismiss() {
        withAnimation(Motion.popupSpring) {
            lookup.dismiss()
        }
    }
}

/// Fixed aspect, or an explicit height when the feed video is minimized or maximized.
private struct ClipVideoFrame: ViewModifier {
    var height: CGFloat?
    var aspect: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        if let height {
            content
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .clipped()
        } else {
            content
                .aspectRatio(aspect, contentMode: .fit)
                .frame(maxWidth: .infinity)
        }
    }
}

/// Speed / bookmark / replay-line / info row under the video (Kiku action chrome).
struct ClipActionRow: View {
    let clip: Clip
    let player: (any ClipPlayer)?
    var onInfo: (() -> Void)?
    var onShadowing: (() -> Void)?

    @Environment(AppModel.self) private var app
    @Environment(PlaybackCoordinator.self) private var coordinator

    private var rateLabel: String {
        switch coordinator.preferredRate {
        case 0.75: "0.75x"
        case 0.5: "0.5x"
        default: "1x"
        }
    }

    var body: some View {
        HStack(spacing: Spacing.s) {
            Button {
                Haptics.selection()
                coordinator.cycleRate()
            } label: {
                Text(rateLabel)
                    .font(.footnote.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 36)
                    .background(Color.fieldFill, in: Capsule())
                    .frame(minHeight: 44)
            }
            .accessibilityLabel("Playback speed \(rateLabel)")

            Button {
                Haptics.light()
                withAnimation(.snappy) { _ = app.toggleFavorite(clip.id) }
            } label: {
                Image(systemName: app.isFavorite(clip.id) ? "bookmark.fill" : "bookmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(app.isFavorite(clip.id) ? Color.designOrange : .secondary)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(app.isFavorite(clip.id) ? "Remove bookmark" : "Bookmark clip")

            Button {
                Haptics.selection()
                if player == nil { coordinator.activate(clip) }
                player?.toggleLoopCurrentLine()
            } label: {
                Image(systemName: "repeat")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(player?.loopRange != nil ? Color.designOrange : .secondary)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(player?.loopRange != nil ? "Stop looping line" : "Loop current line")

            if let onShadowing {
                Button(action: onShadowing) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Shadowing practice")
            }

            Spacer(minLength: 0)

            if let onInfo {
                Button(action: onInfo) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Clip info")
            }
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, 4)
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
    /// Kiku window: current + next line, no nested scroll.
    var windowMode: Bool = false

    var body: some View {
        LiveTranscriptPanel(
            clip: clip,
            currentLine: player?.currentLineIndex ?? 0,
            spokenToken: player?.isPlaying == true ? player?.currentTokenIndex : nil,
            pulseTokenIndex: pulseTokenIndex,
            isPulsing: isPulsing,
            tooltip: tooltip,
            onlyCurrentLine: onlyCurrentLine,
            forceDenseAids: forceDenseAids,
            windowMode: windowMode
        )
    }
}

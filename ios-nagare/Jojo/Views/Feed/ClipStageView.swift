import SwiftUI

/// Reusable clip composition matching kiku demo2 For You / ULTIMATE Explore watch:
/// video → Kiku action strip (… maximize box) → karaoke. Dictionary card centered over the stage.
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
    /// Maximized fills the page with the video and lays the words on that picture.
    var videoExpanded: Bool = false
    var onToggleVideoSize: (() -> Void)? = nil
    var nextClip: Clip? = nil
    var onActivate: () -> Void = {}
    var onFullscreen: (() -> Void)?
    var onInfo: (() -> Void)?
    var onShadowing: (() -> Void)?
    /// When the feed has faded its chrome, the next tap on the video brings it back.
    var watchChromeHidden: Bool = false
    var onRevealWatchChrome: () -> Void = {}
    var onSkip: (() -> Void)? = nil
    /// The For You feed reports its active page's controls to the guided tour.
    var reportsCoachAnchors: Bool = false
    /// Early on, one quiet line under the controls says what tapping a word does.
    var showsWordHint: Bool = false

    @Environment(PlaybackCoordinator.self) private var coordinator
    @Environment(WordLookupController.self) private var lookup
    @Environment(AppModel.self) private var app
    @State private var dragOffset: CGFloat = 0

    private var isPopupHere: Bool {
        lookup.selection?.clip.id == clip.id
    }

    private var isCoachPage: Bool {
        reportsCoachAnchors && coordinator.activeClipId == clip.id
    }

    /// Landscape player that leaves room for karaoke (kiku demo2).
    private var resolvedAspect: CGFloat { immersiveFeed ? 16 / 9 : videoAspect }

    /// Feed pages pass a resize control. Fullscreen and previews keep the fixed aspect.
    private var usesFlexibleVideo: Bool { immersiveFeed && onToggleVideoSize != nil }

    private func columnWidth(in size: CGSize) -> CGFloat {
        min(max(0, size.width - 24), 560)
    }

    /// Resting feed size: full-width 16:9, capped so karaoke keeps the lower half (kikufeedlayout).
    private func videoSize(in size: CGSize) -> CGSize {
        let column = columnWidth(in: size)
        let naturalHeight = column * 9 / 16
        let height = min(naturalHeight, max(180, size.height * 0.38))
        return CGSize(width: column, height: height)
    }

    var body: some View {
        Group {
            if usesFlexibleVideo {
                GeometryReader { geo in
                    // Keep the same AVPlayer-backed hierarchy when resizing. Replacing it with
                    // a full-page view while a paged LazyVStack is animating can detach the
                    // player layer and crash UIKit.
                    let largeVideoHeight = min(max(260, geo.size.height * 0.62), geo.size.height * 0.72)
                    stage(
                        videoHeight: videoExpanded ? largeVideoHeight : videoSize(in: geo.size).height,
                        videoWidth: videoExpanded ? columnWidth(in: geo.size) : videoSize(in: geo.size).width,
                        columnWidth: columnWidth(in: geo.size)
                    )
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                }
            } else {
                stage(videoHeight: nil, videoWidth: nil, columnWidth: nil)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: immersiveFeed ? .infinity : nil, alignment: .top)
        .background(usesFlexibleVideo || immersiveFeed ? Color.canvas : Color.clear)
        .overlay {
            if isPopupHere { popupLayer }
        }
        .overlay(alignment: .top) {
            if isPopupHere, !lookup.previewOnly, lookup.occurrenceCount == 1, let token = lookup.selection?.token {
                savedBanner(token.dictionaryForm.isEmpty ? token.surface : token.dictionaryForm)
                    .padding(.top, 10)
                    .padding(.horizontal, 20)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
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

    @ViewBuilder
    private func stage(videoHeight: CGFloat?, videoWidth: CGFloat?, columnWidth: CGFloat?) -> some View {
        let player = coordinator.player(for: clip)
        restingStage(player: player, videoHeight: videoHeight, videoWidth: videoWidth, columnWidth: columnWidth)
    }

    private func restingStage(player: (any ClipPlayer)?, videoHeight: CGFloat?, videoWidth: CGFloat?, columnWidth: CGFloat?) -> some View {
        VStack(spacing: 0) {
            if showsChannelRow {
                ChannelRow(
                    clip: clip,
                    trailing: channelTrailing,
                    showsFollow: !immersiveFeed,
                    emphasizesTitle: false
                )
                .padding(.vertical, immersiveFeed ? 2 : 10)
                .frame(width: columnWidth)
                .frame(maxWidth: .infinity)
            }

            // Video — max/min box lives on the bottom-trailing corner of the frame (kikufeedlayout).
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
                    onShadowing: immersiveFeed ? nil : onShadowing,
                    fitsFrame: false,
                    watchChromeHidden: watchChromeHidden,
                    onRevealWatchChrome: onRevealWatchChrome,
                    onSkip: onSkip
                )
                .modifier(ClipVideoFrame(width: videoWidth, height: videoHeight, aspect: resolvedAspect))

                if immersiveFeed, let onToggleVideoSize, !isPopupHere {
                    VideoSizeBox(expanded: false, action: onToggleVideoSize)
                        .padding(8)
                }
            }
            .coachTarget(.video, active: isCoachPage)
            .frame(maxWidth: .infinity)

            if immersiveFeed {
                ClipActionRow(
                    clip: clip,
                    player: player,
                    onInfo: onInfo,
                    videoExpanded: videoExpanded,
                    // Corner box on the video owns resize; keep strip free of a second control.
                    onToggleVideoSize: nil
                )
                .frame(width: columnWidth)
                .frame(maxWidth: .infinity)
            }

            if immersiveFeed, showsWordHint {
                Label("Tap any underlined word for its meaning. It saves to Vocab on its own.", systemImage: "hand.tap")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .frame(width: columnWidth, alignment: .leading)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 2)
                    .transition(.opacity)
            }

            transcript(player: player)
                .coachTarget(.transcript, active: isCoachPage)
                .frame(width: columnWidth)
                .frame(maxWidth: .infinity, maxHeight: usesFlexibleVideo || immersiveFeed ? .infinity : nil, alignment: .top)
                .clipped()
        }
    }

    private func savedBanner(_ word: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.spokenGreen)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(word) added to your words.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text("Ready to review anytime.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }

    private func transcript(player: (any ClipPlayer)?, onVideo: Bool = false) -> some View {
        TranscriptSection(
            clip: clip,
            player: player,
            onlyCurrentLine: immersiveFeed ? false : onlyCurrentLine,
            pulseTokenIndex: pulseTokenIndex,
            isPulsing: isPulsing,
            tooltip: tooltip,
            forceDenseAids: immersiveFeed,
            windowMode: immersiveFeed,
            followingLines: onVideo ? 1 : 2,
            sitsOnVideo: onVideo
        )
    }

    private var popupLayer: some View {
        ZStack {
            Color.black.opacity(0.18)
                .contentShape(Rectangle())
                .onTapGesture { dismiss() }
            TapPopupCard(compact: true)
                .padding(.horizontal, 14)
                .frame(maxWidth: 340)
                .fixedSize(horizontal: false, vertical: true)
                .coachTarget(.popupCard, active: isCoachPage)
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
        .transition(.opacity)
    }

    private func dismiss() {
        withAnimation(Motion.popupSpring) {
            lookup.dismiss()
        }
    }
}

/// Kiku boxed maximize / minimize — four corner brackets in a rounded square.
struct VideoSizeBox: View {
    var expanded: Bool
    var action: () -> Void

    var body: some View {
        Button(action: {
            Haptics.selection()
            action()
        }) {
            Image(systemName: expanded
                  ? "arrow.down.right.and.arrow.up.left"
                  : "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.primary)
                .frame(width: 32, height: 32)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.85), lineWidth: 1.6)
                )
        }
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
        .accessibilityLabel(expanded ? "Minimize video" : "Maximize video")
        .accessibilityHint(
            expanded
                ? "Returns the video to its usual size, with the words underneath"
                : "Enlarges the video so the words sit on the picture"
        )
    }
}

/// Fixed aspect, or an explicit size when the feed video is minimized or maximized.
private struct ClipVideoFrame: ViewModifier {
    var width: CGFloat?
    var height: CGFloat?
    var aspect: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        if let height {
            content
                .frame(width: width)
                .frame(maxWidth: width == nil ? .infinity : nil)
                .frame(height: height)
                .clipped()
        } else {
            content
                .aspectRatio(aspect, contentMode: .fit)
                .frame(maxWidth: .infinity)
        }
    }
}

/// Kiku action chrome under the video: time · 1x · bookmark · play · info · (optional size box).
struct ClipActionRow: View {
    let clip: Clip
    let player: (any ClipPlayer)?
    var onInfo: (() -> Void)?
    var onShadowing: (() -> Void)?
    var videoExpanded: Bool = false
    var onToggleVideoSize: (() -> Void)? = nil

    @Environment(AppModel.self) private var app
    @Environment(PlaybackCoordinator.self) private var coordinator
    @State private var showFeatureRequest = false

    private var rateLabel: String {
        switch coordinator.preferredRate {
        case 0.75: "0.75x"
        case 0.5: "0.5x"
        default: "1x"
        }
    }

    private var progress: Double {
        let duration = max(player?.duration ?? clip.durationSec, 0.001)
        return min(1, max(0, (player?.currentTime ?? 0) / duration))
    }

    var body: some View {
        VStack(spacing: 4) {
            // Thin scrub track under the picture (kikuforyou).
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.12))
                    Capsule()
                        .fill(Color.sakuraPink)
                        .frame(width: max(4, proxy.size.width * progress))
                }
            }
            .frame(height: 3)
            .padding(.horizontal, 2)

            HStack(spacing: 4) {
                Text("\(formatClock(player?.currentTime ?? 0)) / \(formatClock(player?.duration ?? clip.durationSec))")
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Spacer(minLength: 4)

                Button {
                    Haptics.selection()
                    coordinator.cycleRate()
                } label: {
                    Text(rateLabel)
                        .font(.caption.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 8)
                        .frame(minHeight: 28)
                        .background(Color.fieldFill, in: Capsule())
                        .frame(minHeight: 44)
                }
                .accessibilityLabel("Playback speed \(rateLabel)")

                Button {
                    Haptics.light()
                    withAnimation(.snappy) { _ = app.toggleFavorite(clip.id) }
                } label: {
                    rowIcon(app.isFavorite(clip.id) ? "bookmark.fill" : "bookmark",
                            tint: app.isFavorite(clip.id) ? Color.designOrange : .secondary)
                }
                .accessibilityLabel(app.isFavorite(clip.id) ? "Remove bookmark" : "Bookmark clip")

                Button {
                    Haptics.selection()
                    if player == nil { coordinator.activate(clip) }
                    else { player?.togglePlay() }
                } label: {
                    Image(systemName: player?.isPlaying == true ? "pause.fill" : "play.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.primary)
                        .frame(width: 28, height: 28)
                        .background(Color.fieldFill, in: Circle())
                        .frame(width: 34, height: 44)
                }
                .accessibilityLabel(player?.isPlaying == true ? "Pause" : "Play")

                if let onInfo {
                    Button(action: onInfo) {
                        rowIcon("info.circle", tint: .secondary)
                    }
                    .accessibilityLabel("Clip info")
                }

                Button {
                    Haptics.selection()
                    coordinator.pauseForPopup()
                    showFeatureRequest = true
                } label: {
                    rowIcon("lightbulb", tint: .secondary)
                }
                .accessibilityLabel("Request a feature")

                if let onToggleVideoSize {
                    VideoSizeBox(expanded: videoExpanded, action: onToggleVideoSize)
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .sheet(isPresented: $showFeatureRequest, onDismiss: {
            coordinator.resumeAfterPopupIfNeeded()
        }) {
            ClipFeatureRequestSheet(contextNote: "While watching “\(clip.title)”.")
        }
    }

    private func rowIcon(_ system: String, tint: Color) -> some View {
        Image(systemName: system)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 34, height: 44)
            .contentShape(Rectangle())
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
    /// Kiku window: current line plus the lines after it, no nested scroll.
    var windowMode: Bool = false
    /// How many lines after the current one stay on screen.
    var followingLines: Int = 1
    /// Words paint directly on the picture instead of on a card under the video.
    var sitsOnVideo: Bool = false

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
            windowMode: windowMode,
            followingLines: followingLines,
            sitsOnVideo: sitsOnVideo
        )
    }
}

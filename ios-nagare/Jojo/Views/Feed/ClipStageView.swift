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
    /// Maximized grows the video while keeping the karaoke in its own section below.
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

    @Environment(PlaybackCoordinator.self) private var coordinator
    @Environment(WordLookupController.self) private var lookup
    @Environment(AppModel.self) private var app
    @AppStorage("jojo.wordSavedHintShown") private var hasShownWordSavedHint = false
    @State private var wordSavedHint: String?
    /// Shorts: the captions button hides the separate karaoke section.
    @State private var showsShortsCaptions: Bool = true
    /// Top of the words, in stage space. The dictionary card docks just above it (Kiku).
    @State private var transcriptTop: CGFloat = 0
    /// Bottom of the picture, in stage space. The dictionary card never rises above it.
    @State private var videoBottom: CGFloat = 0

    private var isPopupHere: Bool {
        lookup.selection?.clip.id == clip.id
    }

    private var isCoachPage: Bool {
        reportsCoachAnchors && coordinator.activeClipId == clip.id
    }

    /// Portrait uploads use their native frame; landscape uploads keep the wide player.
    private var resolvedAspect: CGFloat {
        immersiveFeed && clip.isPortraitVideo ? 9 / 16 : (immersiveFeed ? 16 / 9 : videoAspect)
    }

    /// Feed pages pass a resize control. Fullscreen and previews keep the fixed aspect.
    private var usesFlexibleVideo: Bool { immersiveFeed && onToggleVideoSize != nil }

    private func columnWidth(in size: CGSize) -> CGFloat {
        min(max(0, size.width - 24), 560)
    }

    /// Kiku normal feed: the landscape player runs edge to edge at its true 16:9.
    private func videoSize(in size: CGSize) -> CGSize {
        let maxHeight = max(180, size.height * 0.42)
        let width = min(min(size.width, 640), maxHeight * 16 / 9)
        let height = width * 9 / 16
        return CGSize(width: width, height: height)
    }

    /// Maximize uses the largest 16:9 frame that fits the whole feed viewport without cropping.
    private func expandedVideoSize(in size: CGSize) -> CGSize {
        let maxHeight = max(0, size.height)
        let width = min(size.width, maxHeight * 16 / 9)
        return CGSize(width: width, height: width * 9 / 16)
    }

    /// Maximized landscape page: title on top, big video, words + rail, progress at the bottom.
    private var showsMaximizedLandscape: Bool { usesFlexibleVideo && videoExpanded && !clip.isPortraitVideo }

    /// Portrait Shorts use a portrait player with a separate timer and karaoke section.
    private var showsShortsStage: Bool { usesFlexibleVideo && clip.isPortraitVideo }

    var body: some View {
        Group {
            if showsShortsStage {
                GeometryReader { geo in
                    shortsStage(in: geo.size)
                        .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                }
            } else if usesFlexibleVideo {
                GeometryReader { geo in
                    // Keep the same AVPlayer-backed hierarchy when resizing. Replacing it with
                    // a full-page view while a paged LazyVStack is animating can detach the
                    // player layer and crash UIKit.
                    let restingSize = videoSize(in: geo.size)
                    let expandedSize = expandedVideoSize(in: geo.size)
                    stage(
                        videoHeight: videoExpanded ? expandedSize.height : restingSize.height,
                        videoWidth: videoExpanded ? expandedSize.width : restingSize.width,
                        columnWidth: columnWidth(in: geo.size),
                        stageSize: geo.size
                    )
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                }
            } else {
                stage(videoHeight: nil, videoWidth: nil, columnWidth: nil)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: immersiveFeed ? .infinity : nil, alignment: .top)
        .background(showsMaximizedLandscape ? Color.black : (usesFlexibleVideo || immersiveFeed ? Color.canvas : Color.clear))
        .coordinateSpace(name: StageSpace.name)
        .overlay {
            if isPopupHere { popupLayer }
        }
        .overlay(alignment: .top) {
            if let wordSavedHint {
                savedBanner(wordSavedHint)
                    .padding(.top, 10)
                    .padding(.horizontal, 20)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task(id: wordSavedHint) {
                        try? await Task.sleep(for: .seconds(2.5))
                        guard !Task.isCancelled else { return }
                        withAnimation(.easeOut(duration: 0.2)) { self.wordSavedHint = nil }
                    }
            }
        }
        .clipped()
        .onChange(of: isPopupHere) { _, presented in
            guard coordinator.activeClipId == clip.id else { return }
            if presented {
                if !hasShownWordSavedHint,
                   !lookup.previewOnly,
                   lookup.occurrenceCount == 1,
                   let token = lookup.selection?.token {
                    hasShownWordSavedHint = true
                    withAnimation(Motion.popupSpring) {
                        wordSavedHint = token.dictionaryForm.isEmpty ? token.surface : token.dictionaryForm
                    }
                }
                coordinator.pauseForPopup()
            } else {
                coordinator.resumeAfterPopupIfNeeded()
            }
        }
    }

    @ViewBuilder
    private func stage(videoHeight: CGFloat?, videoWidth: CGFloat?, columnWidth: CGFloat?, stageSize: CGSize? = nil) -> some View {
        let player = coordinator.player(for: clip)
        restingStage(player: player, videoHeight: videoHeight, videoWidth: videoWidth, columnWidth: columnWidth, stageSize: stageSize)
    }

    private func restingStage(player: (any ClipPlayer)?, videoHeight: CGFloat?, videoWidth: CGFloat?, columnWidth: CGFloat?, stageSize: CGSize? = nil) -> some View {
        let maximized = showsMaximizedLandscape
        return VStack(spacing: 0) {
            if showsChannelRow {
                ChannelRow(
                    clip: clip,
                    trailing: maximized ? nil : channelTrailing,
                    showsFollow: !immersiveFeed,
                    emphasizesTitle: maximized
                )
                .padding(.vertical, immersiveFeed ? (maximized ? 8 : 2) : 10)
                .frame(width: columnWidth)
                .frame(maxWidth: .infinity)
                .opacity(maximized && watchChromeHidden ? 0 : 1)
                .animation(.easeInOut(duration: 0.35), value: watchChromeHidden)
            }

            if maximized {
                Color.clear.frame(height: 8)
            } else {
                Color.clear.frame(height: 18)
            }

            // Video: the max/min box sits on the frame's bottom-trailing corner while resting.
            // The video keeps its position in this tree in both sizes so the player never reattaches.
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

                if immersiveFeed, !maximized, let onToggleVideoSize, !isPopupHere {
                    VideoSizeBox(expanded: false, action: onToggleVideoSize)
                        .padding(8)
                        .transition(.opacity)
                }
            }
            .coachTarget(.video, active: isCoachPage)
            .modifier(FrameBottomReader(bottom: $videoBottom))
            .frame(maxWidth: .infinity)
            // Theater centers the picture in the space between the title row and the words
            // (it never hugs the top); resting keeps it snug under the title like a feed card.
            .frame(maxHeight: maximized ? .infinity : nil, alignment: maximized ? .center : .top)

            if maximized {
                // Theater words: a plated zone of comfortable height with the rail beside it,
                // then progress and the YouTube mark close the page at the very bottom.
                HStack(alignment: .top, spacing: 4) {
                    if showsShortsCaptions {
                        shortsKaraoke(player: player, maxHeight: theaterWordsHeight(for: stageSize?.height ?? 620))
                            .coachTarget(.transcript, active: isCoachPage)
                            .background(Color.bgSurfaceDark, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    } else {
                        Spacer(minLength: 0)
                    }
                    ShortsRail(
                        clip: clip,
                        player: player,
                        showsCaptions: showsShortsCaptions,
                        onToggleCaptions: { withAnimation(.snappy) { showsShortsCaptions.toggle() } },
                        onInfo: onInfo,
                        onMinimize: onToggleVideoSize,
                        onPicture: false
                    )
                    // The centered dictionary card floats over this zone while it is up.
                    .opacity(isPopupHere ? 0 : 1)
                    .animation(.easeInOut(duration: 0.2), value: isPopupHere)
                }
                .padding(.horizontal, 12)
                .frame(height: theaterWordsHeight(for: stageSize?.height ?? 620), alignment: .top)

                ShortsFooter(clip: clip, player: player, onPicture: false, sourceMark: "YouTube")
                    .frame(width: columnWidth)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 6)
                    .padding(.bottom, 12)
            } else {
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

                transcript(player: player)
                    .coachTarget(.transcript, active: isCoachPage)
                    .modifier(TranscriptTopReader(top: $transcriptTop))
                    .frame(width: columnWidth)
                    .frame(maxWidth: .infinity, maxHeight: usesFlexibleVideo || immersiveFeed ? .infinity : nil, alignment: .top)
                    .clipped()
            }
        }
    }

    // MARK: Shorts: every mode keeps video, timer, and karaoke in separate stacked areas.

    private func shortsStage(in size: CGSize) -> some View {
        let player = coordinator.player(for: clip)
        let card = CGSize(width: max(0, min(size.width - 12, 620)), height: max(0, size.height - 6))
        let maximized = videoExpanded
        // Resting: the picture owns the top band of the split card. Theater: the picture
        // grows into the largest true 9:16 frame the card holds and the words dock onto
        // its bottom as a solid floating panel — the words still never paint on the picture.
        let videoHeight = maximized
            ? min(card.height - 16, card.width * 16 / 9)
            : min(card.height * 0.68, card.width * 16 / 9)
        let videoWidth = card.width

        return ZStack(alignment: .top) {
            // Keep one player view in the hierarchy while its frame changes on maximize.
            ClipVideoView(
                clip: clip,
                player: player,
                showsControls: false,
                showsRail: false,
                compactChrome: true,
                onActivate: onActivate,
                onFullscreen: onFullscreen,
                fitsFrame: true,
                watchChromeHidden: watchChromeHidden,
                onRevealWatchChrome: onRevealWatchChrome,
                onSkip: onSkip
            )
            .frame(width: videoWidth, height: videoHeight)
            .frame(width: card.width, height: card.height, alignment: .top)
            .background(Color.black)
            .coachTarget(.video, active: isCoachPage)

            VStack(spacing: 4) {
                // Words flow under the picture at rest; in theater the block docks onto
                // the picture's bottom edge.
                Color.clear.frame(height: maximized ? 0 : videoHeight)
                if showsShortsCaptions {
                    shortsKaraoke(player: player, maxHeight: card.height * (maximized ? 0.32 : 0.25))
                        .frame(maxWidth: .infinity, alignment: .top)
                        .padding(.horizontal, maximized ? 10 : 12)
                        .background(Color.bgSurfaceDark, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                }
                // Kiku's vertical Shorts order: the karaoke section follows the video;
                // the clip timer sits under that section.
                ShortsFooter(clip: clip, player: player, onPicture: maximized)
                    .frame(width: videoWidth)
                    .padding(.top, 4)
                    .padding(.bottom, maximized ? 16 : 10)
                if !maximized {
                    Spacer(minLength: 0)
                }
            }
            .frame(width: card.width, height: card.height, alignment: maximized ? .bottom : .top)
            .background(alignment: .bottom) {
                if maximized {
                    // The light bottom wash (55%) keeps the white timer glyphs readable
                    // over the footage in theater.
                    LinearGradient(
                        colors: [Color.black.opacity(0.55), .clear],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                    .frame(height: 150)
                    .allowsHitTesting(false)
                }
            }

            ShortsHeader(clip: clip)
                .frame(width: videoWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .top)
                .padding(.top, 10)
                .opacity(watchChromeHidden ? 0 : 1)

            HStack {
                Spacer(minLength: 0)
                shortsRail(player: player, onPicture: maximized)
            }
            .frame(width: card.width, height: videoHeight, alignment: .trailing)
            .padding(.trailing, 4)
            // The centered dictionary card owns the page while it is up; the rail steps back.
            .opacity(isPopupHere ? 0 : 1)
            .animation(.easeInOut(duration: 0.2), value: isPopupHere)
        }
        .frame(width: card.width, height: card.height)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .frame(maxWidth: .infinity)
        .padding(.top, 2)
    }

    private func shortsRail(player: (any ClipPlayer)?, onPicture: Bool) -> some View {
        ShortsRail(
            clip: clip,
            player: player,
            showsCaptions: showsShortsCaptions,
            onToggleCaptions: { withAnimation(.snappy) { showsShortsCaptions.toggle() } },
            onInfo: onInfo,
            onMaximize: videoExpanded ? nil : onToggleVideoSize,
            onMinimize: videoExpanded ? onToggleVideoSize : nil,
            onPicture: onPicture
        )
        .opacity(watchChromeHidden ? 0.35 : 1)
        .animation(.easeInOut(duration: 0.35), value: watchChromeHidden)
    }

    /// Height of the words zone on the maximized landscape page: comfortable for the
    /// current line plus its lookahead, never taller than about a third of the stage.
    private func theaterWordsHeight(for stageHeight: CGFloat) -> CGFloat {
        min(max(180, stageHeight * 0.34), 320)
    }

    private func shortsKaraoke(
        player: (any ClipPlayer)?,
        maxHeight: CGFloat
    ) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                transcript(player: player)
                    .fixedSize(horizontal: false, vertical: true)
                    .coachTarget(.transcript, active: isCoachPage)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
            }
            .scrollBounceBehavior(.basedOnSize)
            .onChange(of: player?.currentLineIndex) { _, index in
                guard let index else { return }
                withAnimation(Motion.lineAdvance) { proxy.scrollTo(index, anchor: .top) }
            }
            .onAppear {
                if let index = player?.currentLineIndex { proxy.scrollTo(index, anchor: .top) }
            }
        }
        .frame(maxHeight: maxHeight)
        .modifier(TranscriptTopReader(top: $transcriptTop))
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

    private func transcript(player: (any ClipPlayer)?, following: Int? = nil) -> some View {
        TranscriptSection(
            clip: clip,
            player: player,
            onlyCurrentLine: immersiveFeed ? false : onlyCurrentLine,
            pulseTokenIndex: pulseTokenIndex,
            isPulsing: isPulsing,
            tooltip: tooltip,
            forceDenseAids: immersiveFeed,
            windowMode: immersiveFeed,
            // Keep the active line plus the next two queued in every feed layout. As playback
            // advances, the window rolls forward so learners never need to scroll for lyrics.
            followingLines: following ?? 2
        )
    }

    /// Kiku's dictionary card floats horizontally CENTERED on every page. It docks in the
    /// space BELOW the picture: it never covers the video, and on shorts it docks just above
    /// the words panel, over the bottom of the picture. The card hugs its content; when it
    /// runs long, only the middle scrolls INSIDE the card — the mastery chips, Share and
    /// page dots stay pinned and always visible.
    private var popupLayer: some View {
        GeometryReader { geo in
            let stageHeight = geo.size.height
            let onShorts = showsShortsStage
            let shortsAnchor: CGFloat? = transcriptTop > 200
                ? min(transcriptTop - 6, stageHeight) : nil
            let zoneTop = onShorts
                ? 0.0
                : (videoBottom > 0 ? min(videoBottom + 8, stageHeight) : stageHeight * 0.38)
            let bottomPad: CGFloat = onShorts
                ? max(0, stageHeight - (shortsAnchor ?? stageHeight * 0.7))
                : (showsMaximizedLandscape ? 84 : 96)
            let zoneHeight = max(0, stageHeight - zoneTop)
            let availableCardHeight = max(0, zoneHeight - bottomPad)
            let cardMaxHeight = onShorts
                ? min(availableCardHeight, stageHeight * 0.62)
                : availableCardHeight
            ZStack(alignment: .bottom) {
                // A whisper of dim marks the tap-to-close area, confined to the card's zone
                // so the picture above stays untouched.
                Color.black.opacity(0.05)
                    .frame(height: onShorts ? stageHeight : zoneHeight)
                    .contentShape(Rectangle())
                    .onTapGesture { dismiss() }
                    .accessibilityHidden(true)
                TapPopupCard(
                    compact: true,
                    scrollableMiddleHeight: max(120, cardMaxHeight - 310)
                )
                .frame(maxWidth: 420)
                .frame(maxHeight: cardMaxHeight, alignment: .bottom)
                .coachTarget(.popupCard, active: isCoachPage)
                .padding(.bottom, bottomPad)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .bottom)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
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
                : "Enlarges the video while keeping the karaoke underneath"
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
            followingLines: followingLines
        )
    }
}

/// Named space shared by the stage and its overlays so the card can dock above the words.
enum StageSpace {
    static let name = "clipStage"
}

/// Reports where the words begin so the dictionary card can sit right above them.
private struct TranscriptTopReader: ViewModifier {
    @Binding var top: CGFloat

    func body(content: Content) -> some View {
        content.onGeometryChange(for: CGFloat.self) { proxy in
            proxy.frame(in: .named(StageSpace.name)).minY
        } action: { newValue in
            if abs(newValue - top) > 0.5 { top = newValue }
        }
    }
}

/// Reports where the picture ends so the dictionary card never rises above it.
private struct FrameBottomReader: ViewModifier {
    @Binding var bottom: CGFloat

    func body(content: Content) -> some View {
        content.onGeometryChange(for: CGFloat.self) { proxy in
            proxy.frame(in: .named(StageSpace.name)).maxY
        } action: { newValue in
            if abs(newValue - bottom) > 0.5 { bottom = newValue }
        }
    }
}

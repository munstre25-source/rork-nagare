import SwiftUI

/// Reusable Jojo clip composition: video → learning controls → karaoke, with a centered
/// dictionary workspace that stays independent from transcript layout.
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
    var showsTheaterControls: Bool = false
    var onTheaterPresentationChange: (Bool) -> Void = { _ in }
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
    /// Reserved top space: the full header for wide clips, only the solid progress strip for Shorts.
    var topInset: CGFloat = 0
    /// Early on, one quiet line under the controls says what tapping a word does.

    @Environment(PlaybackCoordinator.self) private var coordinator
    @Environment(WordLookupController.self) private var lookup
    @Environment(AppModel.self) private var app
    @AppStorage("jojo.wordSavedHintShown") private var hasShownWordSavedHint = false
    @State private var wordSavedHint: String?
    /// CC removes every subtitle layer on every clip until it is turned back on.
    @AppStorage(PlayerPrefs.subtitlesHiddenKey) private var subtitlesHidden = false
    @AppStorage(PlayerPrefs.immersionKaraokeStyleKey) private var immersionStyle = ""
    @AppStorage(PlayerPrefs.karaokeTextSizeKey) private var karaokeTextSize: Double = 1
    @AppStorage(PlayerPrefs.popupTextSizeKey) private var popupTextSize: Double = 1
    private var showsShortsCaptions: Bool { !subtitlesHidden }
    /// Three wrapped Japanese rows plus readings, translation, and panel padding.
    @ScaledMetric(relativeTo: .body) private var karaokeReadingHeight: CGFloat = 320
    @ScaledMetric(relativeTo: .body) private var landscapeKaraokeHeight: CGFloat = 200

    private var theaterReadingHeight: CGFloat {
        clip.isPortraitVideo ? karaokeReadingHeight : landscapeKaraokeHeight
    }
    @State private var playbackControlsHeight: CGFloat = 88
    @State private var channelRowHeight: CGFloat = 48
    @State private var actionRowHeight: CGFloat = 56
    @State private var transcriptReportLineIndex: Int?
    @State private var showTranscriptReport = false
    /// Top of the words, retained for transcript layout diagnostics.
    @State private var transcriptTop: CGFloat = 0
    /// Bottom of the picture, retained for stage layout diagnostics.
    @State private var videoBottom: CGFloat = 0

    private var isPopupHere: Bool {
        lookup.selection?.clip.id == clip.id
    }

    private var isCoachPage: Bool {
        reportsCoachAnchors && coordinator.activeClipId == clip.id
    }

    /// Portrait uploads use their native frame; landscape uploads keep the wide player.
    private var resolvedAspect: CGFloat {
        if immersiveFeed,
           let player = coordinator.player(for: clip) as? YouTubeClipPlayer,
           let aspect = player.videoAspectRatio {
            return CGFloat(aspect)
        }
        return immersiveFeed && clip.isPortraitVideo ? 9 / 16 : (immersiveFeed ? 16 / 9 : videoAspect)
    }

    /// Feed pages pass a resize control. Fullscreen and previews keep the fixed aspect.
    private var usesFlexibleVideo: Bool { immersiveFeed && onToggleVideoSize != nil }

    private func columnWidth(in size: CGSize) -> CGFloat {
        min(max(0, size.width - 24), 560)
    }

    /// Kiku normal feed: the landscape player runs edge to edge at its true 16:9.
    private func videoSize(in size: CGSize) -> CGSize {
        if isCompactLandscape(size) {
            // Landscape resting: the words take a trailing column, the picture takes the
            // rest. Stacking there would glue the video to the top edge and leave the
            // bottom half of the page dead.
            let words = wordsColumnWidth(in: size.width)
            let maxHeight = max(0, size.height - (showsChannelRow ? channelRowHeight : 0) - actionRowHeight - 22)
            let width = min(size.width - words - 44, maxHeight * 16 / 9, 900)
            return CGSize(width: width, height: width * 9 / 16)
        }
        return RestingFeedGeometry.make(
            in: size, preferredCaptionHeight: theaterReadingHeight,
            channelHeight: showsChannelRow ? channelRowHeight : 0,
            controlsHeight: actionRowHeight
        ).videoSize
    }

    /// Maximize uses the largest 16:9 frame that fits the whole feed viewport without cropping.
    private func expandedVideoSize(in size: CGSize) -> CGSize {
        return LandscapeTheaterGeometry.make(
            in: size,
            preferredCaptionHeight: showsShortsCaptions ? theaterReadingHeight : 0,
            // Keep this space reserved while the controls fade so the video and karaoke
            // never jump when the learner taps the maximized player.
            controlsHeight: clip.isPortraitVideo ? playbackControlsHeight : actionRowHeight,
            videoAspect: resolvedAspect
        ).videoSize
    }

    /// Landscape phones: the stage is wider than tall. Stacking video over words there
    /// either glues the picture to the top edge or clips the words.
    private func isCompactLandscape(_ size: CGSize?) -> Bool {
        guard let size, size.width > 60, size.height > 60 else { return false }
        return size.height < size.width
    }

    private func wordsColumnWidth(in stageWidth: CGFloat) -> CGFloat {
        min(max(stageWidth * 0.3, 230), 380)
    }

    /// Maximized landscape page: video, karaoke with timer beneath, and a trailing control rail.
    private var showsMaximizedLandscape: Bool { usesFlexibleVideo && videoExpanded && !clip.isPortraitVideo }

    /// Portrait Shorts fill the card; karaoke sits on a bottom gradient of the picture.
    private var showsShortsStage: Bool { usesFlexibleVideo && clip.isPortraitVideo }

    var body: some View {
        Group {
            if showsShortsStage {
                GeometryReader { geo in
                    let contentHeight = max(0, geo.size.height - topInset)
                    shortsStage(in: CGSize(width: geo.size.width, height: contentHeight))
                        .frame(width: geo.size.width, height: contentHeight, alignment: .top)
                        .padding(.top, topInset)
                }
            } else if usesFlexibleVideo {
                GeometryReader { geo in
                    // Keep the same AVPlayer-backed hierarchy when resizing. Replacing it with
                    // a full-page view while a paged LazyVStack is animating can detach the
                    // player layer and crash UIKit.
                    let resting = RestingFeedGeometry.make(
                        in: geo.size,
                        preferredCaptionHeight: theaterReadingHeight,
                        channelHeight: showsChannelRow ? channelRowHeight : 0,
                        controlsHeight: actionRowHeight
                    )
                    let expandedSize = expandedVideoSize(in: geo.size)
                    stage(
                        videoHeight: videoExpanded ? expandedSize.height : resting.videoSize.height,
                        videoWidth: videoExpanded ? expandedSize.width : resting.videoSize.width,
                        columnWidth: columnWidth(in: geo.size),
                        stageSize: geo.size,
                        restingCaptionHeight: videoExpanded ? nil : resting.captionHeight
                    )
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                }
                .padding(.top, topInset)
            } else {
                stage(videoHeight: nil, videoWidth: nil, columnWidth: nil)
            }
        }
        // No outer bottom padding — even a few points makes the next clip peep under the dock.
        .onChange(of: app.profile.tapWordsEnabled) { _, enabled in
            if !enabled && isPopupHere { dismiss() }
        }
        .frame(maxWidth: .infinity, maxHeight: immersiveFeed ? .infinity : nil, alignment: .top)
        .background(usesFlexibleVideo || immersiveFeed ? Color.watchBackground : Color.clear)
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
        // Hard clip so a tall karaoke well cannot paint into the next feed page.
        .clipped()
        .contentShape(Rectangle())
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
        .sheet(isPresented: $showTranscriptReport, onDismiss: {
            transcriptReportLineIndex = nil
            coordinator.resumeAfterPopupIfNeeded()
        }) {
            if let lineIndex = transcriptReportLineIndex {
                TranscriptCorrectionSheet(clip: clip, lineIndex: lineIndex)
            }
        }
    }

    @ViewBuilder
    private func stage(
        videoHeight: CGFloat?,
        videoWidth: CGFloat?,
        columnWidth: CGFloat?,
        stageSize: CGSize? = nil,
        restingCaptionHeight: CGFloat? = nil
    ) -> some View {
        let player = coordinator.player(for: clip)
        restingStage(
            player: player,
            videoHeight: videoHeight,
            videoWidth: videoWidth,
            columnWidth: columnWidth,
            stageSize: stageSize,
            restingCaptionHeight: restingCaptionHeight
        )
    }

    private func restingStage(
        player: (any ClipPlayer)?,
        videoHeight: CGFloat?,
        videoWidth: CGFloat?,
        columnWidth: CGFloat?,
        stageSize: CGSize? = nil,
        restingCaptionHeight: CGFloat? = nil
    ) -> some View {
        let maximized = showsMaximizedLandscape
        return Group {
            if !maximized && isCompactLandscape(stageSize) {
                compactLandscapeStage(
                    player: player,
                    videoWidth: videoWidth,
                    videoHeight: videoHeight,
                    stageSize: stageSize ?? .zero,
                    columnWidth: columnWidth
                )
            } else {
                fullStage(
                    player: player,
                    videoHeight: videoHeight,
                    videoWidth: videoWidth,
                    columnWidth: columnWidth,
                    stageSize: stageSize,
                    maximized: maximized,
                    restingCaptionHeight: restingCaptionHeight
                )
            }
        }
    }

    /// Landscape resting: picture + controls left, words right. Nothing glued to the top
    /// edge, no dead space at the bottom.
    private func compactLandscapeStage(
        player: (any ClipPlayer)?,
        videoWidth: CGFloat?,
        videoHeight: CGFloat?,
        stageSize: CGSize,
        columnWidth: CGFloat?
    ) -> some View {
        let wordsWidth = wordsColumnWidth(in: stageSize.width)
        return VStack(spacing: 8) {
            if showsChannelRow {
                ChannelRow(clip: clip, trailing: channelTrailing, showsFollow: false, emphasizesTitle: false)
                    .padding(.vertical, 4)
                    .frame(width: columnWidth)
                    .frame(maxWidth: .infinity)
                    .opacity(watchChromeHidden ? 0 : 1)
                    .animation(.easeInOut(duration: 0.35), value: watchChromeHidden)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                        if height.isFinite, height > 0, abs(height - channelRowHeight) > 1 {
                            channelRowHeight = height
                        }
                    }
            }
            HStack(alignment: .center, spacing: 14) {
                VStack(spacing: 6) {
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
                                .transition(.opacity)
                        }
                    }
                    .coachTarget(.video, active: isCoachPage)
                    .modifier(FrameBottomReader(bottom: $videoBottom))

                    if immersiveFeed {
                        ClipActionRow(
                            clip: clip,
                            player: player,
                            onInfo: onInfo,
                            videoExpanded: videoExpanded,
                            onToggleVideoSize: nil
                        )
                        .frame(width: videoWidth)
                    }
                }

                Group {
                    if subtitlesHidden {
                        SubtitlesOffPill()
                            .frame(maxHeight: .infinity)
                    } else {
                        transcript(player: player, showsLearningControls: false)
                            .coachTarget(.transcript, active: isCoachPage)
                            .modifier(TranscriptTopReader(top: $transcriptTop))
                    }
                }
                    .frame(width: wordsWidth, alignment: .top)
                    .frame(maxHeight: immersiveFeed && !clip.isPortraitVideo ? min(landscapeKaraokeHeight, stageSize.height * 0.58) : nil, alignment: .top)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 12)
        }
        .padding(.bottom, 6)
    }

    /// Wide-screen theater keeps the same playback row under the picture as the default feed,
    /// with the karaoke in the adjacent reading column.
    private func maximizedLandscapeStage(
        player: (any ClipPlayer)?,
        videoWidth: CGFloat?,
        videoHeight: CGFloat?,
        stageSize: CGSize,
        columnWidth: CGFloat?
    ) -> some View {
        let wordsWidth = wordsColumnWidth(in: stageSize.width)
        return HStack(alignment: .center, spacing: 12) {
            VStack(spacing: 6) {
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
                .modifier(ClipVideoFrame(width: videoWidth, height: videoHeight, aspect: resolvedAspect))
                .coachTarget(.video, active: isCoachPage)
                .modifier(FrameBottomReader(bottom: $videoBottom))

                ClipActionRow(
                    clip: clip,
                    player: player,
                    onInfo: onInfo,
                    onShadowing: onShadowing,
                    videoExpanded: true,
                    onToggleVideoSize: nil
                )
                .opacity(showsTheaterControls ? 1 : 0)
                .allowsHitTesting(showsTheaterControls)
                .accessibilityHidden(!showsTheaterControls)
            }
            .frame(width: max(0, stageSize.width - wordsWidth - 36))

            Group {
                if showsShortsCaptions {
                    theaterKaraoke(player: player)
                } else {
                    SubtitlesOffPill()
                }
            }
            .frame(width: wordsWidth, alignment: .top)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(Color.karaokePaper)
            .coachTarget(.transcript, active: isCoachPage)
            .modifier(TranscriptTopReader(top: $transcriptTop))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.horizontal, 12)
        .padding(.top, 16)
        .padding(.bottom, 10)
        .simultaneousGesture(
            DragGesture(minimumDistance: 28).onEnded { _ in
                onRevealWatchChrome()
            }
        )
    }

    private func fullStage(
        player: (any ClipPlayer)?,
        videoHeight: CGFloat?,
        videoWidth: CGFloat?,
        columnWidth: CGFloat?,
        stageSize: CGSize? = nil,
        maximized: Bool,
        restingCaptionHeight: CGFloat? = nil
    ) -> some View {
        let layoutSize = stageSize ?? CGSize(width: videoWidth ?? 360, height: 640)
        let usesLandscapeActionRow = maximized && !clip.isPortraitVideo
        let theater = LandscapeTheaterGeometry.make(
            in: layoutSize,
            preferredCaptionHeight: showsShortsCaptions ? theaterReadingHeight : 0,
            controlsHeight: maximized ? (usesLandscapeActionRow ? actionRowHeight : playbackControlsHeight) : 0,
            videoAspect: resolvedAspect
        )
        return VStack(spacing: 0) {
            if showsChannelRow && !maximized {
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
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    if height.isFinite, height > 0, abs(height - channelRowHeight) > 1 {
                        channelRowHeight = height
                    }
                }
            }

            if maximized {
                Color.clear.frame(height: theater.videoTop)
            } else {
                Color.clear.frame(height: immersiveFeed ? 4 : 18)
            }

            // Video: the max/min box sits on the frame's bottom-trailing corner while resting.
            // The video keeps its position in this tree in both sizes so the player never reattaches.
            let picture = ZStack(alignment: .bottomTrailing) {
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
                    fitsFrame: maximized,
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
            picture.frame(maxWidth: .infinity)
            // Picture keeps its budget when subtitle aids grow; karaoke scrolls inside its well.
            .layoutPriority(1)

            if usesLandscapeActionRow {
                ClipActionRow(
                    clip: clip,
                    player: player,
                    onInfo: onInfo,
                    onShadowing: onShadowing,
                    videoExpanded: true,
                    onToggleVideoSize: nil
                )
                    .frame(width: videoWidth)
                    .opacity(showsTheaterControls ? 1 : 0)
                    .allowsHitTesting(showsTheaterControls)
                    .accessibilityHidden(!showsTheaterControls)
            }

            if maximized {
                if showsShortsCaptions {
                    Group {
                        if resolvedAspect < 1 {
                            shortsKaraoke(player: player, maxHeight: theater.captionHeight)
                        } else {
                            theaterKaraoke(player: player)
                        }
                    }
                        .padding(.horizontal, 16)
                        .frame(maxHeight: usesLandscapeActionRow ? .infinity : theater.captionHeight)
                        .padding(.top, LandscapeTheaterGeometry.spacing)
                        .background(showsShortsCaptions ? Color.karaokePaper : Color.clear)
                }
                if clip.isPortraitVideo {
                    playbackControls(player: player, sourceMark: "YouTube")
                        .padding(.horizontal, 12)
                        .padding(.top, LandscapeTheaterGeometry.spacing)
                        .opacity(showsTheaterControls ? 1 : 0)
                        .allowsHitTesting(showsTheaterControls)
                        .accessibilityHidden(!showsTheaterControls)
                }
                Spacer(minLength: 0)
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
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                        if height.isFinite, height > 0, abs(height - actionRowHeight) > 1 {
                            actionRowHeight = height
                        }
                    }
                }

                // Start the reading window directly under the controls.
                Color.clear.frame(height: immersiveFeed ? 6 : 10)

                Group {
                    if subtitlesHidden && immersiveFeed {
                        SubtitlesOffPill()
                            .padding(.top, 18)
                    } else {
                        transcript(player: player, showsLearningControls: false)
                            .coachTarget(.transcript, active: isCoachPage)
                            .modifier(TranscriptTopReader(top: $transcriptTop))
                    }
                }
                    .frame(width: columnWidth)
                    .frame(maxHeight: immersiveFeed && !clip.isPortraitVideo ? restingCaptionHeight : nil, alignment: .top)
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: usesFlexibleVideo || immersiveFeed ? .infinity : nil,
                        alignment: .top
                    )
                    .clipped()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .clipped()
    }

    // MARK: Shorts: picture under the floating header, rail on the right, karaoke below.

    private func shortsStage(in size: CGSize) -> some View {
        let player = coordinator.player(for: clip)
        let focus = videoExpanded
        let captionsOn = showsShortsCaptions
        let karaokeBelow = captionsOn && !focus
        let layout = ShortsFeedGeometry.make(
            in: size,
            preferredCaptionHeight: karaokeReadingHeight,
            captionsVisible: captionsOn,
            focused: focus
        )
        let videoHeight = layout.videoHeight
        let bandHeight = focus && captionsOn
            ? ShortsStageGeometry.make(in: CGSize(width: size.width, height: videoHeight),
                                       preferredCaptionHeight: karaokeReadingHeight,
                                       controlsHeight: 0).captionHeight
            : 0
        let railHidden = focus && watchChromeHidden

        return VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                ClipVideoView(
                    clip: clip,
                    player: player,
                    showsControls: false,
                    showsRail: false,
                    compactChrome: true,
                    onActivate: onActivate,
                    onFullscreen: onFullscreen,
                    fitsFrame: true,
                    watchChromeHidden: false,
                    onRevealWatchChrome: onRevealWatchChrome,
                    onSkip: onSkip
                )
                // Explicit width: an aspect-fill poster must never widen the stack.
                .frame(width: size.width, height: videoHeight)
                .clipped()
                .background(Color.bgPlayer)
                .coachTarget(.video, active: isCoachPage)

                // YouTube fills unused portrait-video space with a blurred duplicate.
                // Mask just those side gutters in the regular Shorts feed.
                if karaokeBelow {
                    let pictureWidth = min(size.width, videoHeight * 9 / 16)
                    HStack(spacing: 0) {
                        Color.black
                        Color.clear.frame(width: pictureWidth)
                        Color.black
                    }
                    .frame(width: size.width, height: videoHeight)
                    .allowsHitTesting(false)
                }

                if focus && captionsOn && bandHeight > 0 {
                    shortsKaraokeBand(player: player, width: size.width, height: bandHeight)
                }

                if !isPopupHere {
                    ShortsRail(
                        clip: clip,
                        player: player,
                        expanded: focus,
                        onInfo: onInfo,
                        onToggleSize: onToggleVideoSize,
                        onPresentationChange: onTheaterPresentationChange
                    )
                    .padding(.trailing, 8)
                    .padding(.bottom, focus && captionsOn ? max(0, bandHeight - 96) + 8 : 8)
                    .frame(width: size.width, height: videoHeight, alignment: .bottomTrailing)
                    .opacity(railHidden ? 0 : 1)
                    .allowsHitTesting(!railHidden)
                    .animation(.easeInOut(duration: 0.3), value: railHidden)
                }
            }
            .frame(width: size.width, height: videoHeight)
            .clipped()
            .layoutPriority(1)
            .modifier(FrameBottomReader(bottom: $videoBottom))

            if karaokeBelow {
                ShortsFooter(clip: clip, player: player, onPicture: false, sourceMark: "Shorts", showsSourceMark: false)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .frame(width: size.width, height: layout.footerHeight)
                    .accessibilityHidden(railHidden)

                transcript(player: player, showsLearningControls: false, showsLineTools: false)
                    .coachTarget(.transcript, active: isCoachPage)
                    .modifier(TranscriptTopReader(top: $transcriptTop))
                    .padding(.horizontal, 14)
                    .padding(.top, 14)
                    .frame(width: size.width, height: layout.karaokeHeight, alignment: .top)
                    .background(Color.karaokePaper)
                    .clipped()
            }

            if !karaokeBelow {
                ShortsFooter(clip: clip, player: player, onPicture: false, sourceMark: "Shorts", showsSourceMark: false)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .frame(width: size.width, height: layout.footerHeight)
                    .opacity(railHidden ? 0 : 1)
                    .accessibilityHidden(railHidden)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .background(Color.watchBackground)
        .animation(.snappy(duration: 0.28), value: captionsOn)
        .clipped()
    }

    private func playbackControls(player: (any ClipPlayer)?, sourceMark: String) -> some View {
        VStack(spacing: 2) {
            theaterControls(player: player)
            ShortsFooter(
                clip: clip,
                player: player,
                onPicture: false,
                sourceMark: sourceMark,
                showsSourceMark: false
            )
        }
        .padding(.vertical, 4)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color.bgSurfaceDark)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { height in
            if height.isFinite, height > 0, abs(height - playbackControlsHeight) > 1 {
                playbackControlsHeight = height
            }
        }
    }

    private func theaterControls(player: (any ClipPlayer)?, vertical: Bool = false) -> some View {
        TheaterPlaybackControls(
            clip: clip,
            player: player,
            expanded: videoExpanded,
            vertical: vertical,
            showsCaptions: Binding(get: { !subtitlesHidden }, set: { subtitlesHidden = !$0 }),
            onInfo: onInfo,
            onMinimize: onToggleVideoSize,
            onPresentationChange: onTheaterPresentationChange
        )
        .opacity(isPopupHere ? 0 : 1)
        .allowsHitTesting(!isPopupHere)
    }

    private func theaterKaraoke(player: (any ClipPlayer)?) -> some View {
        transcript(player: player, showsLearningControls: false, showsLineTools: false)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .coachTarget(.transcript, active: isCoachPage)
            .modifier(TranscriptTopReader(top: $transcriptTop))
    }

    private func shortsKaraoke(
        player: (any ClipPlayer)?,
        maxHeight: CGFloat
    ) -> some View {
        // Legacy well path for maximized portrait theater stacks that still sit under the picture.
        transcript(player: player, showsLearningControls: false, showsLineTools: false, onPicture: false)
            .frame(maxWidth: .infinity, maxHeight: maxHeight, alignment: .top)
            .coachTarget(.transcript, active: isCoachPage)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .modifier(TranscriptTopReader(top: $transcriptTop))
    }

    /// Three-line karaoke on a soft bottom scrim so portrait footage shows through the band.
    /// The band has a fixed height and top-aligned lines, so the current line never moves
    /// when the next sentence is shorter or longer.
    private func shortsKaraokeBand(player: (any ClipPlayer)?, width: CGFloat, height: CGFloat) -> some View {
        transcript(player: player, showsLearningControls: false, showsLineTools: false, onPicture: true)
            .frame(width: max(0, width - 76), height: max(0, height - 12), alignment: .top)
            .padding(.bottom, 12)
            .padding(.top, 36)
            .padding(.leading, 14)
            .frame(width: width, alignment: .leading)
            .background(
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0), location: 0),
                        .init(color: .black.opacity(0.42), location: 0.28),
                        .init(color: .black.opacity(0.72), location: 0.7),
                        .init(color: .black.opacity(0.82), location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .coachTarget(.transcript, active: isCoachPage)
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

    private func transcript(
        player: (any ClipPlayer)?,
        showsLearningControls: Bool = true,
        showsLineTools: Bool = false,
        onPicture: Bool = false
    ) -> some View {
        let usesPortraitImmersionTextSettings = immersiveFeed && clip.isPortraitVideo && videoExpanded
        return VStack(spacing: Spacing.s) {
            if immersiveFeed && showsLearningControls {
                SubtitleLearningControls(isActive: coordinator.activeClipId == clip.id && !isPopupHere)
            }
            TranscriptSection(
                clip: clip,
                player: player,
                onlyCurrentLine: immersiveFeed ? false : onlyCurrentLine,
                pulseTokenIndex: pulseTokenIndex,
                isPulsing: isPulsing,
                tooltip: tooltip,
                forceDenseAids: immersiveFeed,
                respectsProfileDisplay: immersiveFeed,
                onReportLine: { lineIndex in
                    coordinator.pauseForPopup()
                    transcriptReportLineIndex = lineIndex
                    showTranscriptReport = true
                },
                windowMode: immersiveFeed,
                showsLineTools: showsLineTools,
                onPicture: onPicture,
                sentenceMenuPlayer: immersiveFeed && coordinator.activeClipId == clip.id ? player : nil,
                landscapeReadingWindow: immersiveFeed && !clip.isPortraitVideo,
                portraitReadingPlate: immersiveFeed && clip.isPortraitVideo && !videoExpanded && !onPicture,
                fadesTopLines: videoExpanded && !clip.isPortraitVideo
            )
            .modifier(OptionalTypeSize(index: usesPortraitImmersionTextSettings ? karaokeTextSize : 1))
            .environment(
                \.amberImmersionKaraoke,
                usesPortraitImmersionTextSettings && immersionStyle == ImmersionKaraokeStyle.amber.rawValue
            )
        }
    }

    /// The dictionary lives at the visual center of the stage. Its detail region scrolls
    /// internally, so expanding definitions or Ask Jojo never pushes actions behind the dock.
    private var popupLayer: some View {
        GeometryReader { geo in
            let stageHeight = geo.size.height
            let grow = 1 + max(0, popupTextSize - 1) * 0.12
            let cardHeight = min(520 * grow, stageHeight * 0.74)
            let middleHeight = min(270 * grow, stageHeight * 0.34)
            ZStack {
                Color.black.opacity(0.05)
                    .contentShape(Rectangle())
                    .onTapGesture { dismiss() }
                    .accessibilityHidden(true)
                TapPopupCard(
                    compact: true,
                    scrollableMiddleHeight: middleHeight
                )
                .modifier(OptionalTypeSize(index: popupTextSize))
                .frame(maxWidth: 430)
                .frame(maxHeight: cardHeight, alignment: .top)
                .coachTarget(.popupCard, active: isCoachPage)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
        }
        .padding(.horizontal, 10)
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    private func dismiss() {
        withAnimation(Motion.popupSpring) {
            lookup.dismiss()
        }
    }
}

/// Theater controls stay separate from karaoke and shrink to a compact row on narrow screens.
private struct TheaterPlaybackControls: View {
    let clip: Clip
    let player: (any ClipPlayer)?
    var expanded: Bool = true
    var vertical: Bool = false
    @Binding var showsCaptions: Bool
    var onInfo: (() -> Void)?
    var onMinimize: (() -> Void)?
    var onPresentationChange: (Bool) -> Void

    @State private var showsOptions = false
    @State private var compactOptions = false
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
        Group {
            if vertical {
                ViewThatFits(in: .vertical) {
                    controls(compact: false, vertical: true)
                    controls(compact: true, vertical: true)
                    ScrollView(.vertical, showsIndicators: false) {
                        controls(compact: false, vertical: true)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
                .frame(width: 48)
                .frame(maxHeight: .infinity)
            } else {
                ViewThatFits(in: .horizontal) {
                    controls(compact: false)
                    controls(compact: true)
                    ScrollView(.horizontal, showsIndicators: false) {
                        controls(compact: true)
                    }
                    .frame(height: 44)
                    .scrollBounceBehavior(.basedOnSize)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 2)
            }
        }
        .confirmationDialog("Playback options", isPresented: $showsOptions, titleVisibility: .hidden) {
            if compactOptions {
                Button(app.isLiked(clip.id) ? "Unlike video" : "Like video") { _ = app.toggleLike(clip.id) }
                Button(app.isFavorite(clip.id) ? "Remove bookmark" : "Bookmark clip") { _ = app.toggleFavorite(clip.id) }
            }
            Button(showsCaptions ? "Hide karaoke" : "Show karaoke") { showsCaptions.toggle() }
            Button(player?.loopRange == nil ? "Loop current sentence" : "Stop looping sentence") {
                if player == nil { coordinator.activate(clip) }
                coordinator.player?.toggleLoopCurrentLine()
            }
            if let onInfo { Button("Clip info", action: onInfo) }
            Button("Cancel", role: .cancel) {}
        }
        .onChange(of: showsOptions) { _, presented in onPresentationChange(presented) }
    }

    private func controls(compact: Bool, vertical: Bool = false) -> some View {
        let layout = vertical
            ? AnyLayout(VStackLayout(spacing: 4))
            : AnyLayout(HStackLayout(spacing: 4))
        return layout {
            control(player?.isPlaying == true ? "pause.fill" : "play.fill",
                    label: player?.isPlaying == true ? "Pause" : "Play") {
                if player == nil { coordinator.activate(clip) }
                else { player?.togglePlay() }
            }

            Button {
                Haptics.selection()
                coordinator.cycleRate()
            } label: {
                Text(rateLabel)
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Playback speed \(rateLabel)")

            if !compact {
                control(app.isLiked(clip.id) ? "heart.fill" : "heart", label: "Like video",
                        active: app.isLiked(clip.id)) {
                    _ = app.toggleLike(clip.id)
                }
                control(app.isFavorite(clip.id) ? "bookmark.fill" : "bookmark", label: "Bookmark clip",
                        active: app.isFavorite(clip.id)) {
                    _ = app.toggleFavorite(clip.id)
                }
            }

            TranscriptDisplayMenu(compact: true, onPresentationChange: onPresentationChange)

            ShareLink(item: shareText) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Share video")

            Button {
                compactOptions = compact
                showsOptions = true
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("More playback options")

            if let onMinimize {
                Button {
                    Haptics.selection()
                    onMinimize()
                } label: {
                    VideoSizeGlyph(expanded: expanded, size: 18)
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(expanded ? "Normal video size" : "Maximize video")
            }
        }
        .fixedSize(horizontal: !vertical, vertical: vertical)
    }

    private func control(_ symbol: String, label: String, active: Bool = false,
                         action: @escaping () -> Void) -> some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(active ? Color.designOrange : Color.primary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private var shareText: String {
        if let url = clip.youtubeURL {
            return "Learning Japanese with “\(clip.title)” on Jojo 流れ \(url.absoluteString)"
        }
        return "Learning Japanese with “\(clip.title)” on Jojo 流れ"
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
            VideoSizeGlyph(expanded: expanded, size: 21)
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Color.videoControlBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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

struct VideoSizeGlyph: View {
    let expanded: Bool
    let size: CGFloat

    var body: some View {
        if expanded {
            Path { path in
                for x in [-1.0, 1.0] {
                    for y in [-1.0, 1.0] {
                        let center = size / 2
                        let elbow = CGPoint(x: center + CGFloat(x) * size * 0.17,
                                            y: center + CGFloat(y) * size * 0.17)
                        path.move(to: CGPoint(x: elbow.x, y: center + CGFloat(y) * size * 0.43))
                        path.addLine(to: elbow)
                        path.addLine(to: CGPoint(x: center + CGFloat(x) * size * 0.43, y: elbow.y))
                    }
                }
            }
            .stroke(style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
        } else {
            Image(systemName: "viewfinder")
                .font(.system(size: size, weight: .semibold))
        }
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

/// Action chrome under the video: time · speed · like · bookmark · play · info.
struct ClipActionRow: View {
    let clip: Clip
    let player: (any ClipPlayer)?
    var onInfo: (() -> Void)?
    var onShadowing: (() -> Void)?
    var videoExpanded: Bool = false
    var onToggleVideoSize: (() -> Void)? = nil

    @Environment(AppModel.self) private var app
    @Environment(PlaybackCoordinator.self) private var coordinator

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

            HStack(spacing: 2) {
                Text("\(formatClock(player?.currentTime ?? 0)) / \(formatClock(player?.duration ?? clip.durationSec))")
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Spacer(minLength: 2)

                Button {
                    Haptics.selection()
                    coordinator.cycleRate()
                } label: {
                    Text(rateLabel)
                        .font(.caption.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 6)
                        .frame(minHeight: 28)
                        .background(Color.fieldFill, in: Capsule())
                        .frame(minHeight: 44)
                }
                .accessibilityLabel("Playback speed \(rateLabel)")

                Button {
                    Haptics.light()
                    withAnimation(.snappy) { _ = app.toggleLike(clip.id) }
                } label: {
                    rowIcon(app.isLiked(clip.id) ? "heart.fill" : "heart",
                            tint: app.isLiked(clip.id) ? Color.designOrange : .secondary)
                }
                .accessibilityLabel(app.isLiked(clip.id) ? "Unlike video" : "Like video")

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
                        .frame(width: 30, height: 44)
                }
                .accessibilityLabel(player?.isPlaying == true ? "Pause" : "Play")

                SubtitlesToggleButton(tint: .secondary, activeTint: .sakuraPink)

                PlayerSettingsButton(clip: clip, player: player)

                if let onInfo {
                    Button(action: onInfo) {
                        rowIcon("info.circle", tint: .secondary)
                    }
                    .accessibilityLabel("Clip info")
                }

                if let onToggleVideoSize {
                    VideoSizeBox(expanded: videoExpanded, action: onToggleVideoSize)
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
    }

    private func rowIcon(_ system: String, tint: Color) -> some View {
        Image(systemName: system)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 30, height: 44)
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
    var respectsProfileDisplay: Bool = false
    var onReportLine: ((Int) -> Void)?
    /// Bounded feed viewport with smooth transcript following.
    var windowMode: Bool = false
    var showsLineTools: Bool = true
    var onPicture: Bool = false
    var sentenceMenuPlayer: (any ClipPlayer)? = nil
    var landscapeReadingWindow = false
    var portraitReadingPlate = false
    var fadesTopLines = false

    var body: some View {
        LiveTranscriptPanel(
            clip: clip,
            currentLine: player?.currentLineIndex ?? 0,
            spokenToken: player?.isPlaying == true ? player?.currentTokenIndex : nil,
            isPlaying: player?.isPlaying == true,
            currentTime: player?.currentTime ?? 0,
            pulseTokenIndex: pulseTokenIndex,
            isPulsing: isPulsing,
            tooltip: tooltip,
            onlyCurrentLine: onlyCurrentLine,
            forceDenseAids: forceDenseAids,
            respectsProfileDisplay: respectsProfileDisplay,
            onReportLine: onReportLine,
            windowMode: windowMode,
            showsLineTools: showsLineTools,
            onPicture: onPicture,
            sentenceMenuPlayer: sentenceMenuPlayer,
            landscapeReadingWindow: landscapeReadingWindow,
            portraitReadingPlate: portraitReadingPlate,
            fadesTopLines: fadesTopLines
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

/// Applies the learner's subtitle or card size only when it differs from the default,
/// so system accessibility sizes still win otherwise.
private struct OptionalTypeSize: ViewModifier {
    var index: Double

    @ViewBuilder
    func body(content: Content) -> some View {
        if Int(index.rounded()) == 1 {
            content
        } else {
            content.dynamicTypeSize(PlayerPrefs.typeSize(index))
        }
    }
}

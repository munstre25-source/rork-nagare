import SwiftUI

/// The heart of the app: one clip per page, Kiku-style, with a control to shrink or grow the video.
struct FeedView: View {
    @Environment(AppModel.self) private var app
    @State private var coordinator = PlaybackCoordinator()
    @State private var lookup = WordLookupController()
    @State private var clips: [Clip] = []
    @State private var currentId: String?
    @State private var infoClip: Clip?
    @State private var fullscreenClip: Clip?
    @State private var showSearch: Bool = false
    @State private var reportClip: Clip?
    @State private var quizClip: Clip?
    @State private var shadowingClip: Clip?
    @State private var pendingLoopLine: Int?
    @State private var videoExpanded: Bool = VideoFramePreference.isExpanded
    @State private var bornCard: BornCardPayload?
    @State private var watchChromeVisible: Bool = true
    @State private var chromeHideTask: Task<Void, Never>?
    @State private var resumeSnapshot: (clipId: String, time: Double, line: Int, title: String, channel: String)?
    @State private var showResumeChip: Bool = false
    @Environment(\.scenePhase) private var scenePhase
    let isActiveTab: Bool
    var onOpenExplore: () -> Void = {}
    var tabBarHidden: Binding<Bool> = .constant(false)

    var body: some View {
        VStack(spacing: 0) {
            StudySessionClock(running: isActiveTab && scenePhase == .active)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.l)
                .padding(.top, 2)
            if !app.profile.hideDailyGoalBar {
                DailyGoalBar()
                    .padding(.top, 2)
            }
            if showResumeChip, let resumeSnapshot {
                ResumeChip(
                    title: resumeSnapshot.title,
                    channel: resumeSnapshot.channel,
                    time: resumeSnapshot.time,
                    onResume: { resumeFromSnapshot() },
                    onDismiss: {
                        showResumeChip = false
                        ResumePlaybackStore.clear()
                        self.resumeSnapshot = nil
                    }
                )
            }
            header
            ZStack {
                feedPager
                if let quizClip {
                    ClipQuizOverlay(clip: quizClip) {
                        withAnimation(.snappy) { self.quizClip = nil }
                        advance()
                    }
                    .transition(.opacity)
                    .zIndex(2)
                }
                if let toast = app.cameBackToast {
                    VStack {
                        CameBackToast(
                            surface: toast.surface,
                            gloss: toast.gloss,
                            onReview: {
                                app.dismissCameBackToast()
                                app.pendingDeepLink = .review
                            }
                        )
                        .padding(.top, 8)
                        Spacer()
                    }
                    .zIndex(3)
                    .onAppear {
                        Task {
                            try? await Task.sleep(for: .seconds(4.5))
                            if app.cameBackToast?.id == toast.id {
                                withAnimation(.snappy) { app.dismissCameBackToast() }
                            }
                        }
                    }
                }
                if let step = app.firstSessionCoach {
                    FirstSessionWinOverlay(step: step) {
                        app.skipFirstSessionCoach()
                    }
                    .zIndex(4)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .overlay {
                if let bornCard {
                    BornFlashcard(surface: bornCard.surface, romaji: bornCard.romaji, gloss: bornCard.gloss) {
                        self.bornCard = nil
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
            }
        }
        .background(Color.canvas.ignoresSafeArea())
        .environment(coordinator)
        .environment(lookup)
        .simultaneousGesture(TapGesture().onEnded { revealWatchChrome() })
        .onAppear {
            setup()
            scheduleWatchChromeHide()
            loadResumeChip()
        }
        .onChange(of: isActiveTab) { _, active in
            if active {
                resumeIfPossible()
                scheduleWatchChromeHide()
            } else {
                coordinator.pause()
                lookup.dismiss()
                showWatchChrome()
                ImmersionIsland.end()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                coordinator.persistResumePoint()
                coordinator.pause()
                coordinator.endHoldSlow()
                app.persistWatchLog()
                app.refreshStreakReminder()
                showWatchChrome()
            }
        }
        .onChange(of: currentId) { _, newId in
            lookup.dismiss()
            revealWatchChrome()
            guard let newId, let clip = clips.first(where: { $0.id == newId }),
                  isActiveTab, quizClip == nil else { return }
            coordinator.activate(clip)
            track("clip_view", props: ["clip": clip.id, "tab": "For You"])
            ImmersionIsland.note(
                clip: clip,
                lineIndex: coordinator.player?.spokenLine ?? 0,
                tokenIndex: coordinator.player?.spokenToken,
                minutesLeft: app.minutesLeft,
                goalProgress: app.goalProgress,
                accent: app.profile.theme.rawValue
            )
        }
        .onChange(of: app.pendingFeedClipId) { _, _ in openPendingClip() }
        .onChange(of: app.catalogGeneration) { _, _ in absorbNewClips() }
        .onChange(of: app.tasteRevision) { _, _ in mirrorUpcoming() }
        .onChange(of: lookup.isPresented) { _, presented in
            if presented { showWatchChrome() } else { scheduleWatchChromeHide() }
        }
        .onChange(of: quizClip?.id) { _, _ in
            if quizClip != nil { showWatchChrome() } else { scheduleWatchChromeHide() }
        }
        .onChange(of: app.profile.fadeWatchChrome) { _, enabled in
            if enabled { scheduleWatchChromeHide() } else { showWatchChrome() }
        }
        .onChange(of: coordinator.player?.isPlaying ?? false) { _, playing in
            if playing { scheduleWatchChromeHide() } else { showWatchChrome() }
        }
        .onChange(of: lookup.tapPulse) { _, _ in
            guard lookup.occurrenceCount == 1, let selection = lookup.selection else { return }
            let gloss = lookup.explanation?.definitions.first ?? selection.token.definitions.first ?? ""
            bornCard = BornCardPayload(
                surface: selection.token.surface,
                romaji: lookup.explanation?.romaji ?? selection.token.romaji,
                gloss: gloss
            )
        }
        .sheet(item: $infoClip) { clip in
            ClipInfoSheet(
                clip: clip,
                onShadowing: {
                    coordinator.pause()
                    shadowingClip = clip
                },
                onFullscreen: {
                    coordinator.pause()
                    pendingLoopLine = nil
                    fullscreenClip = clip
                }
            )
        }
        .sheet(item: $reportClip) { clip in
            ClipInfoSheet(clip: clip)
        }
        .sheet(isPresented: $showSearch) {
            SearchView()
        }
        .sheet(item: $shadowingClip, onDismiss: resumeIfPossible) { clip in
            ShadowingOverlay(clip: clip)
                .environment(coordinator)
        }
        .fullScreenCover(item: $fullscreenClip, onDismiss: resumeIfPossible) { clip in
            ClipPlayerScreen(clip: clip, startLine: pendingLoopLine, loopLine: pendingLoopLine != nil)
        }
    }

    /// Kiku For You chrome: centered For You / Explore + flag. Goal bar sits above.
    private var header: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: 40, height: 40)
            Spacer(minLength: 0)
            CenteredModeSwitch(forYouSelected: true, onForYou: {}, onExplore: onOpenExplore)
            Spacer(minLength: 0)
            Button {
                reportClip = clips.first(where: { $0.id == currentId })
            } label: {
                Image(systemName: "flag")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 40, height: 40)
            }
            .accessibilityLabel("Clip info & report")
            .contextMenu {
                Button {
                    showSearch = true
                } label: {
                    Label("Search clips", systemImage: "magnifyingglass")
                }
                Button {
                    reportClip = clips.first(where: { $0.id == currentId })
                } label: {
                    Label("Clip info & report", systemImage: "flag")
                }
            }
        }
        .opacity(watchChromeVisible ? 1 : 0)
        .allowsHitTesting(watchChromeVisible)
        .animation(.easeInOut(duration: 0.4), value: watchChromeVisible)
        .padding(.horizontal, 8)
        .padding(.bottom, 2)
    }

    private var feedPager: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ForEach(clips) { clip in
                    ClipStageView(
                        clip: clip,
                        showsChannelRow: true,
                        immersiveFeed: true,
                        videoExpanded: videoExpanded,
                        onToggleVideoSize: {
                            Haptics.selection()
                            withAnimation(.snappy) { videoExpanded.toggle() }
                            VideoFramePreference.isExpanded = videoExpanded
                        },
                        onActivate: { coordinator.activate(clip) },
                        onFullscreen: {
                            coordinator.pause()
                            pendingLoopLine = nil
                            fullscreenClip = clip
                        },
                        onInfo: { infoClip = clip },
                        onShadowing: {
                            coordinator.pause()
                            shadowingClip = clip
                        },
                        watchChromeHidden: !watchChromeVisible,
                        onRevealWatchChrome: { revealWatchChrome() },
                        onSkip: {
                            if let id = currentId, let clip = clips.first(where: { $0.id == id }) {
                                app.noteClipSkipped(clip)
                            }
                            mirrorUpcoming()
                            advance()
                        }
                    )
                    .containerRelativeFrame(.vertical)
                    .id(clip.id)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $currentId)
        .scrollDisabled(lookup.isPresented || quizClip != nil)
        .scrollIndicators(.hidden)
        .background(Color.canvas)
        .clipped()
    }

    private func setup() {
        let playback = coordinator
        coordinator.onWatchTick = { [weak app, weak playback] seconds in
            app?.addWatch(seconds: seconds)
            guard let app, let playback, let player = playback.player else { return }
            let clip = player.clip
            if Int(player.currentTime) % 8 == 0 {
                playback.persistResumePoint()
            }
            if let tokenIdx = player.spokenToken,
               let line = clip.lines[safe: player.spokenLine],
               let token = line.tokens[safe: tokenIdx],
               token.tappable {
                app.noteSpokenWordCameBack(token: token, clipId: clip.id)
            }
            ImmersionIsland.note(
                clip: clip,
                lineIndex: player.spokenLine,
                tokenIndex: player.spokenToken,
                minutesLeft: app.minutesLeft,
                goalProgress: app.goalProgress,
                accent: app.profile.theme.rawValue
            )
        }
        coordinator.onFinished = { handleClipFinished() }
        if clips.isEmpty {
            reloadClips()
            openPendingClip()
        }
        resumeIfPossible()
    }

    private func loadResumeChip() {
        guard let snap = ResumePlaybackStore.snapshot else {
            showResumeChip = false
            resumeSnapshot = nil
            return
        }
        // Don't nag if already on that clip near the saved time.
        if currentId == snap.clipId { return }
        resumeSnapshot = snap
        showResumeChip = true
    }

    private func resumeFromSnapshot() {
        guard let snap = resumeSnapshot else { return }
        showResumeChip = false
        if !clips.contains(where: { $0.id == snap.clipId }), let clip = app.clip(id: snap.clipId) {
            clips.insert(clip, at: 0)
        }
        withAnimation { currentId = snap.clipId }
        if let clip = clips.first(where: { $0.id == snap.clipId }) {
            coordinator.activate(clip, seekTime: snap.time)
        }
        ResumePlaybackStore.clear()
        resumeSnapshot = nil
        track("resume_chip_tapped")
    }

    private func absorbNewClips() {
        let known = Set(clips.map(\.id))
        let newcomers = app.forYouClips.filter { !known.contains($0.id) }
        guard !newcomers.isEmpty else { return }
        if let id = currentId, let index = clips.firstIndex(where: { $0.id == id }) {
            clips.insert(contentsOf: newcomers, at: index + 1)
        } else {
            clips.append(contentsOf: newcomers)
        }
        mirrorUpcoming()
    }

    /// The clip on screen stays. Everything after it is reordered around what they just watched.
    private func mirrorUpcoming() {
        let ranked = app.forYouClips
        guard let id = currentId, let index = clips.firstIndex(where: { $0.id == id }) else {
            clips = ranked
            currentId = clips.first?.id
            return
        }
        let kept = Set(clips.prefix(index + 1).map(\.id))
        clips = Array(clips.prefix(index + 1)) + ranked.filter { !kept.contains($0.id) }
    }

    private func reloadClips() {
        clips = app.forYouClips
        currentId = clips.first(where: { $0.id == currentId })?.id ?? clips.first?.id
    }

    private func resumeIfPossible() {
        guard isActiveTab, fullscreenClip == nil, quizClip == nil, shadowingClip == nil,
              let id = currentId, let clip = clips.first(where: { $0.id == id }) else { return }
        coordinator.activate(clip)
    }

    /// End of clip → remember it, then a micro-quiz, then advance.
    private func handleClipFinished() {
        if let id = currentId { app.markClipFinished(id) }
        mirrorUpcoming()
        guard quizClip == nil,
              let id = currentId,
              let clip = clips.first(where: { $0.id == id }),
              !ClipQuizBuilder.questions(for: clip, count: 1).isEmpty else {
            advance()
            return
        }
        coordinator.pause()
        withAnimation(.snappy) { quizClip = clip }
    }

    /// Auto-advance to the next clip at the end.
    private func advance() {
        guard let id = currentId, let index = clips.firstIndex(where: { $0.id == id }) else { return }
        let next = clips.indices.contains(index + 1) ? clips[index + 1] : clips.first
        withAnimation(.easeInOut(duration: 0.45)) { currentId = next?.id }
    }

    private func openPendingClip() {
        guard let id = app.pendingFeedClipId else { return }
        app.pendingFeedClipId = nil
        reloadClips()
        if !clips.contains(where: { $0.id == id }), let clip = app.clip(id: id) {
            clips.insert(clip, at: 0)
        }
        withAnimation { currentId = id }
    }

    /// Bring For You / Explore and the tab capsule back, then hide them again once playback settles.
    private func revealWatchChrome() {
        chromeHideTask?.cancel()
        if !watchChromeVisible || app.feedChromeHidden {
            withAnimation(.easeOut(duration: 0.28)) {
                watchChromeVisible = true
                app.feedChromeHidden = false
            }
        }
        scheduleWatchChromeHide()
    }

    /// Keep the chrome up. Used when playback stops or the learner leaves the feed.
    private func showWatchChrome() {
        chromeHideTask?.cancel()
        guard !watchChromeVisible || app.feedChromeHidden else { return }
        withAnimation(.easeOut(duration: 0.28)) {
            watchChromeVisible = true
            app.feedChromeHidden = false
        }
    }

    private func scheduleWatchChromeHide() {
        chromeHideTask?.cancel()
        guard app.profile.fadeWatchChrome, isActiveTab else {
            showWatchChrome()
            return
        }
        chromeHideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.6))
            guard !Task.isCancelled else { return }
            guard coordinator.player?.isPlaying == true,
                  !lookup.isPresented,
                  quizClip == nil,
                  bornCard == nil,
                  infoClip == nil,
                  shadowingClip == nil,
                  fullscreenClip == nil else { return }
            withAnimation(.easeInOut(duration: 0.45)) {
                watchChromeVisible = false
                app.feedChromeHidden = true
            }
        }
    }
}

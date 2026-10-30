import SwiftUI
import SwiftData

/// The heart of the app: one clip per page, Kiku-style, with a control to shrink or grow the video.
struct FeedView: View {
    @Environment(AppModel.self) private var app
    @Query private var savedWords: [SavedWord]
    @State private var coordinator = PlaybackCoordinator()
    @State private var lookup = WordLookupController()
    @State private var clips: [Clip] = []
    @State private var currentId: String?
    @State private var infoClip: Clip?
    @State private var fullscreenClip: Clip?
    @State private var showSearch: Bool = false
    @State private var showLibrary: Bool = false
    @State private var reviewSession: ReviewSessionConfig?
    @State private var reportClip: Clip?
    @State private var quizClip: Clip?
    @State private var shadowingClip: Clip?
    @State private var pendingLoopLine: Int?
    // One full-screen clip per page. Feed controls overlay the video; maximize hides them.
    @State private var videoExpanded: Bool = false
    /// Maximize shortcut: a swipe down brings the navigation dock back over the theater;
    /// a swipe up tucks it away again — no need to minimize first.
    @State private var maximizeNavShown: Bool = false
    @State private var bornCard: BornCardPayload?
    @State private var watchChromeVisible: Bool = true
    @State private var chromeHideTask: Task<Void, Never>?
    @State private var resumeSnapshot: (clipId: String, time: Double, line: Int, title: String, channel: String)?
    @State private var showResumeChip: Bool = false
    @AppStorage("jojo.quickChecksEnabled") private var quickChecksEnabled = true
    /// When the current clip came on screen, to tell a real swipe from a quick flick past.
    @State private var clipShownAt: Date = .now
    /// Set right before code (not the learner) changes `currentId`.
    @State private var programmaticClipChange: Bool = false
    @Environment(\.scenePhase) private var scenePhase
    let isActiveTab: Bool
    var onOpenExplore: () -> Void = {}
    var tabBarHidden: Binding<Bool> = .constant(false)

    var body: some View {
        ZStack(alignment: .top) {
            // The navigation chrome is a real row ABOVE the feed, never painted on top of
            // the video. In theater the chrome steps out and the picture takes the screen.
            VStack(spacing: 0) {
                if !videoExpanded {
                    VStack(spacing: 0) {
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
                    }
                    .opacity(watchChromeVisible ? 1 : 0)
                    .allowsHitTesting(watchChromeVisible)
                    .environment(\.colorScheme, .dark)
                    .animation(.easeInOut(duration: 0.4), value: watchChromeVisible)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(1)
                }
                feedPager
                    // Theater owns the screen edge to edge; resting keeps the picture
                    // below the status bar and the For You / Explore row.
                    .ignoresSafeArea(edges: videoExpanded ? .top : [])
            }

            if let quizClip {
                ClipQuizOverlay(
                    clip: quizClip,
                    onFinished: {
                        withAnimation(.snappy) { self.quizClip = nil }
                        advance()
                    },
                    onDisableQuickChecks: {
                        quickChecksEnabled = false
                        withAnimation(.snappy) { self.quizClip = nil }
                        advance()
                    }
                )
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
                        },
                        onDismiss: { withAnimation(.snappy) { app.dismissCameBackToast() } }
                    )
                    .padding(.top, 8)
                    Spacer()
                }
                .zIndex(3)
                .task(id: toast.id) {
                    try? await Task.sleep(for: .seconds(4.5))
                    guard !Task.isCancelled, app.cameBackToast?.id == toast.id else { return }
                    withAnimation(.snappy) { app.dismissCameBackToast() }
                }
            }

        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.canvas.ignoresSafeArea())
        .environment(coordinator)
        .environment(lookup)
        .simultaneousGesture(TapGesture().onEnded { revealWatchChrome() })
        // Maximize shortcut: vertical swipes nudge the navigation in and out while the
        // theater keeps playing. A swipe down shows the dock, up hides it again.
        .simultaneousGesture(
            DragGesture(minimumDistance: 28)
                .onEnded { value in
                    guard videoExpanded else { return }
                    let dy = value.translation.height
                    if dy > 48, !maximizeNavShown {
                        Haptics.selection()
                        withAnimation(.snappy) { maximizeNavShown = true }
                    } else if dy < -48, maximizeNavShown {
                        Haptics.selection()
                        withAnimation(.snappy) { maximizeNavShown = false }
                    }
                }
        )
        .onAppear {
            setup()
            scheduleWatchChromeHide()
            loadResumeChip()
            startGuidedTourSoon()
        }
        // Maximized hands the whole screen to the video, so the floating dock steps away too
        // (a swipe down brings it back as a shortcut).
        .onChange(of: videoExpanded) { _, expanded in
            if !expanded { maximizeNavShown = false }
            syncDock()
        }
        .onChange(of: maximizeNavShown) { _, _ in syncDock() }
        .onDisappear {
            if videoExpanded { app.hidesMainTabBar = false }
        }
        .onChange(of: isActiveTab) { _, active in
            syncDock()
            if active {
                Task { await app.refreshRemoteClips() }
                resumeIfPossible()
                scheduleWatchChromeHide()
                startGuidedTourSoon()
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
        .onChange(of: currentId) { oldId, newId in
            lookup.dismiss()
            revealWatchChrome()
            noteClipChange(from: oldId)
            guard let newId, let clip = clips.first(where: { $0.id == newId }),
                  isActiveTab, quizClip == nil else { return }
            if let index = clips.firstIndex(where: { $0.id == newId }), index >= max(0, clips.count - 3) {
                Task { await app.refreshRemoteClips() }
            }
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
        .fullScreenCover(isPresented: $showLibrary) {
            LibraryView(presentedModally: true)
        }
        .fullScreenCover(item: $reviewSession) { config in
            ReviewSessionView(config: config)
        }
        .sheet(item: $shadowingClip, onDismiss: resumeIfPossible) { clip in
            ShadowingOverlay(clip: clip)
                .environment(coordinator)
        }
        .fullScreenCover(item: $fullscreenClip, onDismiss: resumeIfPossible) { clip in
            ClipPlayerScreen(clip: clip, startLine: pendingLoopLine, loopLine: pendingLoopLine != nil)
        }
    }

    /// Feed navigation layered over the video: centered For You / Explore switch and search.
    private var header: some View {
        HStack(spacing: 0) {
            Button {
                Haptics.selection()
                showLibrary = true
            } label: {
                Image(systemName: "books.vertical")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Library")
            Spacer(minLength: 0)
            CenteredModeSwitch(forYouSelected: true, onForYou: {}, onExplore: onOpenExplore)
            Spacer(minLength: 0)
            // Report lives in the clip's info sheet (the ⓘ under the video), so the corner
            // holds the one thing people look for up here: search.
            Button {
                Haptics.selection()
                showSearch = true
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Search clips by word")
        }
        .opacity(watchChromeVisible ? 1 : 0)
        .allowsHitTesting(watchChromeVisible)
        .animation(.easeInOut(duration: 0.4), value: watchChromeVisible)
        .padding(.horizontal, 8)
        .padding(.bottom, 2)
    }

    /// A due-review invitation belongs beside the Feed, never in front of the next clip.
    private var dueReviewPrompt: some View {
        let count = dueReviewCount
        return Button {
            reviewSession = ReviewSessionConfig(title: "Review", keys: dueReviewKeys)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "rectangle.stack.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Color.sakuraButton, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(count == 1 ? "1 card is ready" : "\(count) cards are ready")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                    Text("A quick review will help them stick.")
                        .font(.caption)
                        .foregroundStyle(Color.studyMuted)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text("Review")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.sakuraButton)
            }
            .padding(10)
            .background(Color.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.cardStroke))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(count == 1 ? "1 card ready to review" : "\(count) cards ready to review")
    }

    private var dueReviewKeys: [String] {
        _ = app.reviewAvailabilityRevision
        let due = Set(app.relevantDueKeys(limit: 10))
        return savedWords.map(\.key).filter { due.contains($0) }
    }

    private var dueReviewCount: Int {
        _ = app.reviewAvailabilityRevision
        return savedWords.count { $0.state != .known && $0.dueAt <= Date() }
    }

    /// Until a few words are saved (and outside the guided tour), say what a word tap does.
    private var feedPager: some View {
        GeometryReader { viewport in
            ScrollViewReader { proxy in
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
                                videoExpanded.toggle()
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
                            },
                            reportsCoachAnchors: true,
                        )
                        // Match every page to the actual viewport. The available height changes
                        // when feed chrome or the tab bar hides during maximize/minimize.
                        .frame(width: viewport.size.width, height: viewport.size.height)
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
            // Rotation and dock show/hide resize every page. Without re-anchoring, the
            // scroll offset lands mid-page and the learner sees two half feeds at once.
            .onChange(of: viewport.size) { _, _ in
                guard let id = currentId else { return }
                proxy.scrollTo(id, anchor: .top)
            }
            }
        }
        .clipped()
    }

    /// The dock hides while the theater owns the screen, and returns for the swipe-down
    /// shortcut so navigation is always one gesture away without minimizing.
    private func syncDock() {
        app.hidesMainTabBar = videoExpanded && isActiveTab && !maximizeNavShown
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
        programmaticClipChange = true
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
            programmaticClipChange = true
            currentId = clips.first?.id
            return
        }
        let kept = Set(clips.prefix(index + 1).map(\.id))
        clips = Array(clips.prefix(index + 1)) + ranked.filter { !kept.contains($0.id) }
    }

    private func reloadClips() {
        let ranked = app.forYouClips
        #if DEBUG
        // Debug stays entirely offline: only the bundled Japanese-learning clips are shown.
        // This guarantees every visible item is playable in a fresh simulator session.
        if app.purchases.debugBypassActive {
            // Offline clips lead, then the real catalog (Shorts and landscape) follows.
            let showcase = app.debugShowcaseClips(limit: 3)
            let ids = Set(showcase.map(\.id))
            clips = showcase + ranked.filter { !ids.contains($0.id) }
        } else {
            clips = ranked
        }
        #else
        clips = ranked
        #endif
        let target = clips.first(where: { $0.id == currentId })?.id ?? clips.first?.id
        if target != currentId {
            programmaticClipChange = true
            currentId = target
        }
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
        guard quickChecksEnabled,
              quizClip == nil,
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
        programmaticClipChange = true
        withAnimation(.easeInOut(duration: 0.45)) { currentId = next?.id }
    }

    private func openPendingClip() {
        guard let id = app.pendingFeedClipId else { return }
        app.pendingFeedClipId = nil
        reloadClips()
        if !clips.contains(where: { $0.id == id }), let clip = app.clip(id: id) {
            clips.insert(clip, at: 0)
        }
        programmaticClipChange = currentId != id
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

    /// A swipe counts toward the experience prompt only when the learner did it and had
    /// actually looked at the previous clip (auto-advance, deep links and reloads don't count).
    private func noteClipChange(from oldId: String?) {
        let dwell = Date().timeIntervalSince(clipShownAt)
        clipShownAt = .now
        if programmaticClipChange {
            programmaticClipChange = false
            return
        }
        guard oldId != nil, isActiveTab, dwell >= FeedbackPromptConfig.minDwellSeconds else { return }
        app.noteMeaningfulSwipe()
        track("feed_swiped", props: ["dwell": String(Int(dwell.rounded()))])
    }

    /// First visit after onboarding: start the guided tour once the clip has settled.
    private func startGuidedTourSoon() {
        guard app.profile.onboardingCompleted, GuidanceCenter.shared.tourStep == nil else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            guard isActiveTab, app.profile.onboardingCompleted else { return }
            GuidanceCenter.shared.startTourIfNeeded(legacyFinished: app.guidedTourLegacyFinished)
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
                  // Keep the Vocab dock visible while the guided tour may point at it.
                  GuidanceCenter.shared.tourStep == nil,
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

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
    @State private var theaterOptionsPresented = false
    @State private var goalCompletionVisible = false
    @State private var headerHeight: CGFloat = 96
    @State private var celebration: FeedCelebration?
    @AppStorage(PlayerPrefs.focusModeKey) private var focusMode = false
    @AppStorage("jojo.seenAchievements") private var seenAchievements = ""
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @State private var bornCard: BornCardPayload?
    @State private var watchChromeVisible: Bool = true
    @State private var chromeHideTask: Task<Void, Never>?
    @State private var resumeSnapshot: (clipId: String, time: Double, line: Int, title: String, channel: String)?
    @State private var showResumeChip: Bool = false
    @AppStorage(PlaybackDefaults.quickChecksKey) private var quickChecksEnabled = true
    /// When the current clip came on screen, to tell a real swipe from a quick flick past.
    @State private var clipShownAt: Date = .now
    /// Set right before code (not the learner) changes `currentId`.
    @State private var programmaticClipChange: Bool = false
    @State private var autoAdvanceTask: Task<Void, Never>?
    @State private var autoScrollTargetId: String?
    /// Bumped whenever page height may change so the pager can re-pin the current clip.
    @State private var pageHeightEpoch: Int = 0
    @Environment(\.scenePhase) private var scenePhase
    let isActiveTab: Bool
    var onOpenExplore: () -> Void = {}
    var homeRequest: Int = 0
    var tabBarHidden: Binding<Bool> = .constant(false)

    var body: some View {
        ZStack(alignment: .top) {
            // The pager owns the full height. The For You / Explore header floats over the
            // top: over a gradient on vertical Shorts, over a solid band on landscape clips
            // (which get `topInset` so the picture still starts below it). The pager never
            // resizes when chrome fades, so two half-clips are never on screen at once.
            feedPager
            headerStack
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    if abs(height - headerHeight) > 0.5 { headerHeight = height }
                }
                .background(alignment: .top) { headerBackdrop }
                .frame(height: videoExpanded ? 0 : nil, alignment: .top)
                .clipped()
                .opacity(videoExpanded ? 0 : 1)
                .allowsHitTesting(!videoExpanded)
                .zIndex(1)

            if let celebration {
                FeedCelebrationToast(celebration: celebration)
                    .padding(.top, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(4)
                    .task(id: celebration.id) {
                        try? await Task.sleep(for: .seconds(3.2))
                        guard !Task.isCancelled, self.celebration?.id == celebration.id else { return }
                        withAnimation(.snappy) { self.celebration = nil }
                        scheduleWatchChromeHide()
                    }
                    .onTapGesture {
                        withAnimation(.snappy) { self.celebration = nil }
                        scheduleWatchChromeHide()
                    }
            }

            if quickChecksEnabled, let quizClip {
                ClipQuizOverlay(
                    clip: quizClip,
                    onFinished: { finishQuickCheck() },
                    onDisableQuickChecks: {
                        quickChecksEnabled = false
                        finishQuickCheck()
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
                        onReview: { dismissCameBackAlert(openReview: true) },
                        onDismiss: { dismissCameBackAlert(openReview: false) }
                    )
                    .padding(.top, 8)
                    Spacer()
                }
                .zIndex(3)
                .task(id: toast.id) {
                    await presentCameBackAlert(toast)
                }
            }

        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.watchBackground.ignoresSafeArea())
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
            if seenAchievements.isEmpty { checkAchievements() }
            setup()
            scheduleWatchChromeHide()
            loadResumeChip()
            startGuidedTourSoon()
        }
        // Maximized hands the whole screen to the video, so the floating dock steps away too
        // (a swipe down brings it back as a shortcut).
        .onChange(of: videoExpanded) { _, expanded in
            if !expanded { maximizeNavShown = false }
            if expanded { revealWatchChrome() }
            syncDock()
            bumpPageHeightEpoch()
        }
        .onChange(of: maximizeNavShown) { _, shown in
            syncDock()
            bumpPageHeightEpoch()
            if shown { revealWatchChrome() }
        }
        .onChange(of: watchChromeVisible) { _, _ in
            bumpPageHeightEpoch()
        }
        .onChange(of: app.hidesMainTabBar) { _, _ in
            bumpPageHeightEpoch()
        }
        .onChange(of: app.goalCelebrationCount) { _, _ in
            celebrate(FeedCelebration(kind: .goal, title: "You're on fire!",
                                      detail: "\(app.profile.dailyGoalMinutes) minutes of real Japanese today"))
        }
        .onChange(of: savedWords.count) { _, _ in checkAchievements() }
        .onChange(of: app.currentStreak) { _, _ in checkAchievements() }
        .onChange(of: goalCompletionVisible) { _, visible in
            if visible { showWatchChrome() } else { scheduleWatchChromeHide() }
        }
        .onChange(of: theaterOptionsPresented) { _, presented in
            if presented { chromeHideTask?.cancel() } else { scheduleWatchChromeHide() }
        }
        .accessibilityActions {
            if videoExpanded {
                Button(maximizeNavShown ? "Hide playback controls" : "Show playback controls") {
                    maximizeNavShown.toggle()
                }
            }
        }
        .onDisappear {
            autoAdvanceTask?.cancel()
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
                autoAdvanceTask?.cancel()
                coordinator.pause()
                lookup.dismiss()
                showWatchChrome()
                ImmersionIsland.end()
            }
        }
        .onChange(of: homeRequest) { _, _ in
            autoAdvanceTask?.cancel()
            lookup.dismiss()
            quizClip = nil
            bornCard = nil
            videoExpanded = false
            maximizeNavShown = false
            theaterOptionsPresented = false
            coordinator.endHoldSlow()
            showWatchChrome()
            resumeIfPossible()
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
            autoAdvanceTask?.cancel()
            if autoScrollTargetId != nil && autoScrollTargetId != newId { autoScrollTargetId = nil }
            lookup.dismiss()
            // Auto-advance must not flash chrome mid-scroll — that resizes the page and shakes.
            let wasProgrammatic = programmaticClipChange
            noteClipChange(from: oldId)
            if !wasProgrammatic {
                revealWatchChrome()
            }
            guard let newId, let clip = clips.first(where: { $0.id == newId }),
                  isActiveTab, quizClip == nil, !isCovered else { return }
            if let index = clips.firstIndex(where: { $0.id == newId }), index >= max(0, clips.count - 3) {
                Task { await app.refreshRemoteClips() }
            }
            coordinator.activate(clip)
            preloadUpcoming()
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
        // A screen opened over the feed (search, library, review) owns playback: the feed
        // pauses so two YouTube embeds never play at once (the covering player stalled at
        // 0:01 while the hidden feed kept auto-advancing — 2026-10-31).
        .onChange(of: isCovered) { _, covered in
            if covered {
                coordinator.persistResumePoint()
                coordinator.pause()
                lookup.dismiss()
            } else {
                resumeIfPossible()
            }
        }
        .onChange(of: app.pendingFeedClipId) { _, _ in openPendingClip() }
        .onChange(of: app.catalogGeneration) { _, _ in absorbNewClips() }
        .onChange(of: app.tasteRevision) { _, _ in mirrorUpcoming() }
        .onChange(of: lookup.isPresented) { _, presented in
            if presented { showWatchChrome() } else { scheduleWatchChromeHide() }
        }
        .onChange(of: quickChecksEnabled) { _, enabled in
            if !enabled { finishQuickCheck() }
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

    private var currentClip: Clip? {
        guard let currentId else { return clips.first }
        return clips.first { $0.id == currentId }
    }

    /// Navigation stays directly below the safe area; progress and resume details
    /// sit under it and fade with the watch chrome (opacity only, never height).
    private var headerStack: some View {
        VStack(spacing: 0) {
            header
                .opacity(navigationChromeOpacity)
            VStack(spacing: 0) {
                if !focusMode {
                    ProgressStrip(dueWords: dueReviewKeys.count, onReview: openDueReview)
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
            }
            .opacity(statusChromeOpacity)
        }
    }

    /// Playback settles persistent controls instead of removing them. Shorts need the
    /// lightest treatment because this chrome sits directly over the picture; landscape
    /// clips have a solid header band and can remain a little stronger.
    private var navigationChromeOpacity: Double {
        guard !watchChromeVisible else { return 1 }
        return currentClip?.isPortraitVideo == true ? 0.30 : 0.48
    }

    /// Progress and resume notices stay discoverable and tappable without competing with
    /// karaoke. Important, time-limited toasts temporarily restore everything to full strength.
    private var statusChromeOpacity: Double {
        guard !watchChromeVisible else { return 1 }
        return currentClip?.isPortraitVideo == true ? 0.20 : 0.36
    }

    @ViewBuilder
    private var headerBackdrop: some View {
        if currentClip?.isPortraitVideo == true {
            LinearGradient(
                colors: [Color.black.opacity(0.72), Color.black.opacity(0.35), .clear],
                startPoint: .top, endPoint: .bottom
            )
            .padding(.bottom, -36)
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
            .opacity(watchChromeVisible ? 1 : 0.42)
        } else {
            Color.watchBackground
                .ignoresSafeArea(edges: .top)
        }
    }

    /// Feed navigation just below the status bar, above progress and the video.
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
        .padding(.horizontal, 8)
        .padding(.bottom, 2)
    }

    private func celebrate(_ item: FeedCelebration) {
        guard !focusMode, isActiveTab, !lookup.isPresented else { return }
        if item.kind == .goal { Haptics.success() } else { Haptics.medium() }
        // Goals and achievements are short-lived and deserve one clear moment before the
        // ambient playback fade resumes.
        showWatchChrome()
        withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) { celebration = item }
    }

    private func presentCameBackAlert(_ toast: CameBackPayload) async {
        showWatchChrome()
        try? await Task.sleep(for: .seconds(4.5))
        guard !Task.isCancelled, app.cameBackToast?.id == toast.id else { return }
        dismissCameBackAlert(openReview: false)
    }

    private func dismissCameBackAlert(openReview: Bool) {
        withAnimation(.snappy) { app.dismissCameBackToast() }
        if openReview { app.pendingDeepLink = .review }
        scheduleWatchChromeHide()
    }

    /// Achievements are computed from progress; we only remember which ones were announced.
    private func checkAchievements() {
        let known = savedWords.count { $0.state == .known }
        let unlocked = ProfileAchievement.all(streak: app.currentStreak, words: savedWords.count, known: known,
                                              minutes: Int(app.totalWatchSeconds / 60)).filter(\.unlocked)
        var seen = Set(seenAchievements.split(separator: ",").map(String.init))
        let firstRun = seenAchievements.isEmpty
        let fresh = unlocked.filter { !seen.contains($0.id) }
        if firstRun { seen.insert("_") }
        guard !fresh.isEmpty || firstRun else { return }
        fresh.forEach { seen.insert($0.id) }
        seenAchievements = seen.sorted().joined(separator: ",")
        // The first check only records what was already earned before this feature existed.
        guard !firstRun, let newest = fresh.last else { return }
        celebrate(FeedCelebration(kind: .achievement, title: newest.title, detail: newest.detail, symbol: newest.symbol))
    }

    private func openDueReview() {
        let keys = dueReviewKeys
        guard !keys.isEmpty else { return }
        reviewSession = ReviewSessionConfig(title: "Review", keys: keys)
    }

    /// A due-review invitation belongs beside the Feed, never in front of the next clip.
    private var dueReviewPrompt: some View {
        let count = dueReviewCount
        return Button {
            openDueReview()
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
        ClipPager(
            ids: clips.map(\.id),
            currentId: $currentId,
            isDisabled: lookup.isPresented || quizClip != nil
        ) { id in
            if let clip = clips.first(where: { $0.id == id }) {
                        ClipStageView(
                            clip: clip,
                            // Video and channel metadata live in the info sheet, keeping the
                            // watch surface clear like the Kiku reference.
                            showsChannelRow: false,
                            immersiveFeed: true,
                            videoExpanded: videoExpanded,
                            // Player controls follow tap-to-reveal and auto-hide independently
                            // from the swipe-down navigation dock.
                            showsTheaterControls: videoExpanded && watchChromeVisible,
                            onTheaterPresentationChange: { theaterOptionsPresented = $0 },
                            onToggleVideoSize: {
                                Haptics.selection()
                                // Jump the page height; animating header/dock height leaves the
                                // scroll offset between two clips.
                                var transaction = Transaction()
                                transaction.disablesAnimations = true
                                withTransaction(transaction) { videoExpanded.toggle() }
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
                            topInset: videoExpanded ? 0 : headerHeight
                        )
                        .background(Color.watchBackground)
                        // Opaque mask so the next page cannot show through rounded corners.
                        .compositingGroup()
            } else {
                Color.watchBackground
            }
        }
        .background(Color.watchBackground)
        .clipped()
    }

    /// The dock hides while the theater owns the screen, and returns for the swipe-down
    /// shortcut so navigation is always one gesture away without minimizing.
    private func syncDock() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            app.hidesMainTabBar = videoExpanded && isActiveTab && !maximizeNavShown
        }
    }

    private func bumpPageHeightEpoch() {
        pageHeightEpoch &+= 1
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
        // Refresh objects and remove retired clips as well as adding new ones. Keeping
        // stale objects here used to retain old categories and unpublished lessons.
        let ranked = app.forYouClips
        let refreshed = Dictionary(uniqueKeysWithValues: ranked.map { ($0.id, $0) })
        clips = clips.compactMap { refreshed[$0.id] }
        if let currentId, refreshed[currentId] == nil {
            coordinator.pause()
            lookup.dismiss()
            programmaticClipChange = true
            self.currentId = nil
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
        preloadUpcoming()
    }

    private func reloadClips() {
        let ranked = app.forYouClips
        // Debug entitlement bypass uses the real personal feed too. Marketing demos
        // have their own explicit showcase rather than overriding onboarding choices.
        clips = ranked
        let target = clips.first(where: { $0.id == currentId })?.id ?? clips.first?.id
        if target != currentId {
            programmaticClipChange = true
            currentId = target
        }
    }

    /// True while another screen sits over the feed and owns playback.
    private var isCovered: Bool {
        showSearch || showLibrary || reviewSession != nil || fullscreenClip != nil || shadowingClip != nil
    }

    private func resumeIfPossible() {
        guard isActiveTab, !isCovered, quizClip == nil,
              let id = currentId, let clip = clips.first(where: { $0.id == id }) else { return }
        coordinator.activate(clip)
        preloadUpcoming()
    }

    /// Warm the next clip once the current one is playing — the swipe then starts instantly.
    private func preloadUpcoming() {
        guard let id = currentId, let index = clips.firstIndex(where: { $0.id == id }),
              let next = clips[safe: index + 1] else { return }
        coordinator.preload(next)
    }

    /// End of clip → remember it, then a micro-quiz, then advance.
    private func handleClipFinished() {
        guard !isCovered else { coordinator.pause(); return }
        if let id = currentId { app.markClipFinished(id) }
        mirrorUpcoming()
        // onFinished retains the view from setup; read storage rather than its
        // cached AppStorage value so Turn off and Profile changes take effect.
        guard PlaybackDefaults.quickChecksEnabled(),
              quizClip == nil,
              let id = currentId,
              let clip = clips.first(where: { $0.id == id }),
              !ClipQuizBuilder.questions(for: clip, count: 1).isEmpty else {
            scheduleAutomaticAdvance()
            return
        }
        coordinator.pause()
        withAnimation(.snappy) { quizClip = clip }
    }

    private func finishQuickCheck() {
        guard quizClip != nil else { return }
        withAnimation(.snappy) { quizClip = nil }
        scheduleAutomaticAdvance()
    }

    private func scheduleAutomaticAdvance() {
        autoAdvanceTask?.cancel()
        guard app.profile.autoAdvanceEnabled, let id = currentId else { return }
        let pause = max(0, min(3, app.profile.autoAdvancePauseSeconds))
        autoAdvanceTask = Task { @MainActor in
            if pause > 0 { try? await Task.sleep(for: .seconds(pause)) }
            guard !Task.isCancelled, isActiveTab, currentId == id, quizClip == nil else { return }
            advance()
        }
    }

    /// One smooth page turn — TikTok-style. No second hard snap after the animation.
    private func advance() {
        guard let id = currentId, let index = clips.firstIndex(where: { $0.id == id }) else { return }
        guard let next = clips[safe: index + 1] else { return }
        programmaticClipChange = true
        autoScrollTargetId = nil
        withAnimation(.spring(response: 0.38, dampingFraction: 0.92)) {
            currentId = next.id
        }
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
        guard (videoExpanded || app.profile.fadeWatchChrome), isActiveTab else {
            showWatchChrome()
            return
        }
        chromeHideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(videoExpanded ? 4 : 2.6))
            guard !Task.isCancelled else { return }
            guard coordinator.player?.isPlaying == true,
                  !voiceOverEnabled,
                  !theaterOptionsPresented,
                  !goalCompletionVisible,
                  !showSearch, !showLibrary,
                  // Keep the Vocab dock visible while the guided tour may point at it.
                  GuidanceCenter.shared.tourStep == nil,
                  !lookup.isPresented,
                  quizClip == nil,
                  bornCard == nil,
                  infoClip == nil,
                  shadowingClip == nil,
                  fullscreenClip == nil else { return }
            withAnimation(.easeInOut(duration: 0.45)) {
                if videoExpanded { maximizeNavShown = false }
                watchChromeVisible = false
                app.feedChromeHidden = true
            }
        }
    }
}

/// Keep each feed gesture to one clip, regardless of swipe velocity.
nonisolated struct SingleClipPerSwipeBehavior: ScrollTargetBehavior {
    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        target.rect.origin.y = Self.settledOffset(
            original: context.originalTarget.rect.minY,
            proposed: target.rect.minY,
            viewportHeight: context.containerSize.height,
            contentHeight: context.contentSize.height
        )
    }

    static func settledOffset(original: CGFloat, proposed: CGFloat,
                              viewportHeight: CGFloat, contentHeight: CGFloat) -> CGFloat {
        guard viewportHeight > 0 else { return original }
        let currentPage = Int((original / viewportHeight).rounded())
        let proposedPage = Int((proposed / viewportHeight).rounded())
        let lastPage = Int(max(0, (contentHeight / viewportHeight - 1).rounded(.down)))
        let onePageAtATime = min(max(proposedPage, currentPage - 1), currentPage + 1)
        let destination = min(max(onePageAtATime, 0), lastPage)
        return CGFloat(destination) * viewportHeight
    }
}

/// Re-pin the current clip after chrome or dock height changes. Page frames update across
/// several layout passes; one yield is not enough and leaves two clips sharing the screen.
enum FeedPageReanchor {
    /// Final settle after dock/header height changes have finished laying out.
    static let settleDelayNanoseconds: UInt64 = 450_000_000
    /// Intermediate passes while LazyVStack rebuilds page frames at the new height.
    static let passDelaysNanoseconds: [UInt64] = [0, 16_000_000, 100_000_000, settleDelayNanoseconds]

    @MainActor
    private static var pending: Task<Void, Never>?

    @MainActor
    static func schedule(
        currentId: String?,
        stillCurrent: @escaping @MainActor () -> String?,
        proxy: ScrollViewProxy
    ) {
        guard let id = currentId else { return }
        pending?.cancel()
        pending = Task { @MainActor in
            for delay in passDelaysNanoseconds {
                if delay > 0 {
                    try? await Task.sleep(nanoseconds: delay)
                } else {
                    await Task.yield()
                }
                guard !Task.isCancelled, stillCurrent() == id else { return }
                snap(id, proxy: proxy)
            }
        }
    }

    @MainActor
    static func snap(_ id: String, proxy: ScrollViewProxy) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            proxy.scrollTo(id, anchor: .top)
        }
    }
}

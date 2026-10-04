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
    @State private var videoExpanded: Bool = true
    @State private var bornCard: BornCardPayload?
    @Environment(\.scenePhase) private var scenePhase
    let isActiveTab: Bool
    var onOpenExplore: () -> Void = {}
    var tabBarHidden: Binding<Bool> = .constant(false)

    var body: some View {
        VStack(spacing: 0) {
            if !app.profile.hideDailyGoalBar {
                DailyGoalBar()
                    .padding(.top, 4)
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
        .onAppear(perform: setup)
        .onChange(of: isActiveTab) { _, active in
            if active { resumeIfPossible() } else { coordinator.pause(); lookup.dismiss() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                coordinator.pause()
                coordinator.endHoldSlow()
                app.persistWatchLog()
                app.refreshStreakReminder()
            }
        }
        .onChange(of: currentId) { _, newId in
            lookup.dismiss()
            guard let newId, let clip = clips.first(where: { $0.id == newId }),
                  isActiveTab, quizClip == nil else { return }
            coordinator.activate(clip)
            track("clip_view", props: ["clip": clip.id, "tab": "For You"])
        }
        .onChange(of: app.pendingFeedClipId) { _, _ in openPendingClip() }
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

    private var header: some View {
        ZStack {
            CenteredModeSwitch(forYouSelected: true, onForYou: {}, onExplore: onOpenExplore)
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                Button {
                    reportClip = clips.first(where: { $0.id == currentId })
                } label: {
                    Image(systemName: "flag")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 40, height: 40)
                }
                .accessibilityLabel("Report clip")
                Button {
                    showSearch = true
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 40, height: 40)
                }
                .accessibilityLabel("Search clips")
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 2)
    }

    private var feedPager: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ForEach(clips) { clip in
                    ClipStageView(
                        clip: clip,
                        showsChannelRow: false,
                        immersiveFeed: true,
                        videoExpanded: videoExpanded,
                        onToggleVideoSize: {
                            Haptics.selection()
                            withAnimation(.snappy) { videoExpanded.toggle() }
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
        coordinator.onWatchTick = { [weak app] seconds in app?.addWatch(seconds: seconds) }
        coordinator.onFinished = { handleClipFinished() }
        if clips.isEmpty {
            reloadClips()
            openPendingClip()
        }
        resumeIfPossible()
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

    /// End of clip → micro-quiz, then advance.
    private func handleClipFinished() {
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
}

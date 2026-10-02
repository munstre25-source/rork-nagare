import SwiftUI

nonisolated enum FeedTab: String, CaseIterable, Sendable {
    case forYou = "For You"
    case explore = "Explore"
}

/// The heart of the app: daily goal → For You / Explore → vertically paged clips.
struct FeedView: View {
    @Environment(AppModel.self) private var app
    @State private var coordinator = PlaybackCoordinator()
    @State private var lookup = WordLookupController()
    @State private var tab: FeedTab = .forYou
    @State private var clips: [Clip] = []
    @State private var currentId: String?
    @State private var infoClip: Clip?
    @State private var fullscreenClip: Clip?
    @State private var showSearch: Bool = false
    @State private var reportClip: Clip?
    @State private var quizClip: Clip?
    @State private var shadowingClip: Clip?
    @State private var pendingLoopLine: Int?
    @Namespace private var tabNamespace
    @Environment(\.scenePhase) private var scenePhase
    let isActiveTab: Bool

    var body: some View {
        VStack(spacing: 0) {
            if !app.profile.hideDailyGoalBar {
                DailyGoalBar()
                    .padding(.top, 4)
            }
            header
            ZStack {
                feedPager
                    .opacity(tab == .explore ? 0 : 1)
                    .allowsHitTesting(tab != .explore)
                if tab == .explore {
                    ExploreView(onPlay: { clip, loopLine in
                        coordinator.pause()
                        pendingLoopLine = loopLine
                        fullscreenClip = clip
                    })
                    .transition(.opacity)
                }
                if let quizClip {
                    ClipQuizOverlay(clip: quizClip) {
                        withAnimation(.snappy) { self.quizClip = nil }
                        advance()
                    }
                    .transition(.opacity)
                    .zIndex(2)
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
                  isActiveTab, tab != .explore, quizClip == nil else { return }
            coordinator.activate(clip)
            track("clip_view", props: ["clip": clip.id, "tab": tab.rawValue])
        }
        .onChange(of: tab) { _, newTab in
            lookup.dismiss()
            quizClip = nil
            reloadClips(for: newTab)
            if newTab == .explore { coordinator.pause() } else { resumeIfPossible() }
        }
        .onChange(of: app.pendingFeedClipId) { _, _ in openPendingClip() }
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
        HStack(spacing: Spacing.s) {
            HStack(spacing: Spacing.m) {
                ForEach(FeedTab.allCases, id: \.self) { item in
                    Button {
                        Haptics.selection()
                        withAnimation(Motion.tabSlide) { tab = item }
                    } label: {
                        VStack(spacing: 4) {
                            Text(item.rawValue)
                                .font(.subheadline.weight(tab == item ? .semibold : .regular))
                                .foregroundStyle(tab == item ? Color.primary : Color.secondary)
                            ZStack {
                                Capsule()
                                    .fill(Color.clear)
                                    .frame(width: 28, height: 2)
                                if tab == item {
                                    Capsule()
                                        .fill(Color.jojoOrange)
                                        .frame(width: 28, height: 2)
                                        .matchedGeometryEffect(id: "feedTabUnderline", in: tabNamespace)
                                }
                            }
                        }
                        .frame(minHeight: 40)
                    }
                    .accessibilityAddTraits(tab == item ? .isSelected : [])
                }
            }
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
        .padding(.horizontal, Spacing.l)
        .padding(.bottom, 2)
    }

    private var feedPager: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ForEach(Array(clips.enumerated()), id: \.element.id) { _, clip in
                    ClipStageView(
                        clip: clip,
                        immersiveFeed: true,
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
    }

    private func setup() {
        coordinator.onWatchTick = { [weak app] seconds in app?.addWatch(seconds: seconds) }
        coordinator.onFinished = { handleClipFinished() }
        if clips.isEmpty {
            reloadClips(for: tab)
            openPendingClip()
        }
        resumeIfPossible()
    }

    private func reloadClips(for tab: FeedTab) {
        switch tab {
        case .forYou:
            clips = app.forYouClips
        case .explore:
            break
        }
        if tab != .explore {
            currentId = clips.first(where: { $0.id == currentId })?.id ?? clips.first?.id
        }
    }

    private func resumeIfPossible() {
        guard isActiveTab, tab != .explore, fullscreenClip == nil, quizClip == nil, shadowingClip == nil,
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
        tab = .forYou
        reloadClips(for: .forYou)
        if !clips.contains(where: { $0.id == id }), let clip = app.clip(id: id) {
            clips.insert(clip, at: 0)
        }
        withAnimation { currentId = id }
    }
}

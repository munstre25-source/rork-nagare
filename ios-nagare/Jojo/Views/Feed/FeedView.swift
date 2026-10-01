import SwiftUI

nonisolated enum FeedTab: String, CaseIterable, Sendable {
    case forYou = "For You"
    case following = "Following"
    case explore = "Explore"
}

/// The heart of the app: daily goal → For You / Following / Explore → vertically paged clips.
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
        .background(Color.bgPlayer.ignoresSafeArea())
        .environment(coordinator)
        .environment(lookup)
        .environment(\.colorScheme, .dark)
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
        .onChange(of: app.followRevision) { _, _ in
            if tab == .following { reloadClips(for: .following) }
        }
        .sheet(item: $infoClip) { clip in
            ClipInfoSheet(clip: clip)
                .environment(\.colorScheme, .dark)
        }
        .sheet(item: $reportClip) { clip in
            ClipInfoSheet(clip: clip)
                .environment(\.colorScheme, .dark)
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
        HStack(spacing: Spacing.m) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.l) {
                    ForEach(FeedTab.allCases, id: \.self) { item in
                        Button {
                            Haptics.selection()
                            withAnimation(.snappy) { tab = item }
                        } label: {
                            VStack(spacing: 6) {
                                Text(item.rawValue)
                                    .font(.title3.weight(tab == item ? .semibold : .regular))
                                    .foregroundStyle(tab == item ? .white : .white.opacity(0.5))
                                Capsule()
                                    .fill(tab == item ? Color.jojoOrange : .clear)
                                    .frame(width: 44, height: 3)
                            }
                            .frame(minHeight: 44)
                        }
                        .accessibilityAddTraits(tab == item ? .isSelected : [])
                    }
                }
            }
            Button {
                showSearch = true
            } label: {
                ControlIcon(systemImage: "magnifyingglass")
            }
            .accessibilityLabel("Search clips")
            Button {
                reportClip = clips.first { $0.id == currentId }
            } label: {
                ControlIcon(systemImage: "flag")
            }
            .accessibilityLabel("Report or view source")
        }
        .padding(.horizontal, Spacing.l)
    }

    private var feedPager: some View {
        Group {
            if tab == .following, clips.isEmpty {
                followingEmpty
            } else {
                GeometryReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(clips.enumerated()), id: \.element.id) { index, clip in
                                ClipStageView(
                                    clip: clip,
                                    immersiveFeed: true,
                                    nextClip: clips.indices.contains(index + 1) ? clips[index + 1] : nil,
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
                                .frame(width: proxy.size.width, height: proxy.size.height)
                                .id(clip.id)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollTargetBehavior(.paging)
                    .scrollPosition(id: $currentId)
                    .scrollDisabled(lookup.isPresented || quizClip != nil)
                }
            }
        }
    }

    private var followingEmpty: some View {
        VStack(spacing: Spacing.m) {
            Image(systemName: "person.2.fill")
                .font(.largeTitle)
                .foregroundStyle(Color.jojoOrange)
            Text("Follow channels you like")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
            Text("Tap Follow on any clip in For You, then come back here for a tighter feed.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.65))
                .multilineTextAlignment(.center)
            Button {
                withAnimation(.snappy) { tab = .forYou }
            } label: {
                Text("Browse For You")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .frame(minHeight: 48)
                    .background(Color.jojoOrange, in: Capsule())
            }
            .padding(.top, Spacing.s)
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        case .following:
            clips = app.followingClips
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

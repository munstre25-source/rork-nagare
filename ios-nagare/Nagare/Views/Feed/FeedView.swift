import SwiftUI

nonisolated enum FeedTab: String, CaseIterable, Sendable {
    case forYou = "For You"
    case explore = "Explore"
}

/// The heart of the app: daily goal → For You / Explore tabs → vertically paged clips.
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
    @Environment(\.scenePhase) private var scenePhase
    let isActiveTab: Bool

    var body: some View {
        VStack(spacing: 0) {
            DailyGoalBar()
                .padding(.top, 4)
            header
            ZStack {
                forYouPager
                    .opacity(tab == .forYou ? 1 : 0)
                    .allowsHitTesting(tab == .forYou)
                if tab == .explore {
                    ExploreView(onPlay: { clip, loopLine in
                        coordinator.pause()
                        pendingLoopLine = loopLine
                        fullscreenClip = clip
                    })
                    .transition(.opacity)
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
                app.persistWatchLog()
                app.refreshStreakReminder()
            }
        }
        .onChange(of: currentId) { _, newId in
            lookup.dismiss()
            guard let newId, let clip = clips.first(where: { $0.id == newId }), isActiveTab, tab == .forYou else { return }
            coordinator.activate(clip)
            track("clip_view", props: ["clip": clip.id])
        }
        .onChange(of: tab) { _, newTab in
            lookup.dismiss()
            if newTab == .explore { coordinator.pause() } else { resumeIfPossible() }
        }
        .onChange(of: app.pendingFeedClipId) { _, _ in openPendingClip() }
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
        .fullScreenCover(item: $fullscreenClip, onDismiss: resumeIfPossible) { clip in
            ClipPlayerScreen(clip: clip, startLine: pendingLoopLine, loopLine: pendingLoopLine != nil)
        }
    }

    @State private var pendingLoopLine: Int?

    private var header: some View {
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
                            .fill(tab == item ? Color.nagareOrange : .clear)
                            .frame(width: 44, height: 3)
                    }
                    .frame(minHeight: 44)
                }
                .accessibilityAddTraits(tab == item ? .isSelected : [])
            }
            Spacer()
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

    private var forYouPager: some View {
        GeometryReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(clips) { clip in
                        ClipStageView(
                            clip: clip,
                            onActivate: { coordinator.activate(clip) },
                            onFullscreen: {
                                coordinator.pause()
                                pendingLoopLine = nil
                                fullscreenClip = clip
                            },
                            onInfo: { infoClip = clip }
                        )
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .id(clip.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $currentId)
            .scrollDisabled(lookup.isPresented)
        }
    }

    private func setup() {
        coordinator.onWatchTick = { [weak app] seconds in app?.addWatch(seconds: seconds) }
        coordinator.onFinished = { advance() }
        if clips.isEmpty {
            clips = app.forYouClips
            currentId = app.profile.firstClipId.flatMap { id in clips.first { $0.id == id }?.id } ?? clips.first?.id
            openPendingClip()
        }
        resumeIfPossible()
    }

    private func resumeIfPossible() {
        guard isActiveTab, tab == .forYou, fullscreenClip == nil,
              let id = currentId, let clip = clips.first(where: { $0.id == id }) else { return }
        coordinator.activate(clip)
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
        if !clips.contains(where: { $0.id == id }), let clip = app.clip(id: id) {
            clips.insert(clip, at: 0)
        }
        withAnimation { currentId = id }
    }
}

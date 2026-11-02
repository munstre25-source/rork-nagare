import SwiftUI

/// Full-screen player. A single clip stays put. A queue from Explore pages downward like For You.
struct ClipPlayerScreen: View {
    let clip: Clip
    var queue: [Clip] = []
    var startLine: Int?
    var loopLine: Bool = false

    private var playlist: [Clip] {
        var list = queue
        if !list.contains(where: { $0.id == clip.id }) {
            list.insert(clip, at: 0)
        }
        return list
    }

    var body: some View {
        if playlist.count > 1 {
            ClipQueueScreen(clips: playlist, startId: clip.id, startLine: startLine, loopLine: loopLine)
        } else {
            ImmersivePlayerScreen(clip: clip, startLine: startLine, loopLine: loopLine)
        }
    }
}

/// Vertical pager for a list of clips. Swipe down to the next one once playback has started.
struct ClipQueueScreen: View {
    let clips: [Clip]
    let startId: String
    var startLine: Int?
    var loopLine: Bool = false
    /// When this changes, the pager scrolls to that clip. Used by the marketing walkthrough.
    var forcedId: String? = nil
    /// Marketing playback loops every clip so both stay visibly playing.
    var loopPlayback: Bool = false
    /// Kept for walkthrough call sites; every player now starts at the standard frame.
    var preferMinimized: Bool = false

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var coordinator = PlaybackCoordinator()
    @State private var lookup = WordLookupController()
    @State private var currentId: String?
    @State private var videoExpanded: Bool
    @State private var showsTheaterControls = false
    @State private var theaterOptionsPresented = false
    @State private var infoClip: Clip?
    @State private var appliedStart: Bool = false

    init(
        clips: [Clip],
        startId: String,
        startLine: Int? = nil,
        loopLine: Bool = false,
        forcedId: String? = nil,
        loopPlayback: Bool = false,
        preferMinimized: Bool = false
    ) {
        self.clips = clips
        self.startId = startId
        self.startLine = startLine
        self.loopLine = loopLine
        self.forcedId = forcedId
        self.loopPlayback = loopPlayback
        self.preferMinimized = preferMinimized
        _currentId = State(initialValue: startId)
        _videoExpanded = State(initialValue: false)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(clips) { clip in
                        ClipStageView(
                            clip: clip,
                            showsChannelRow: false,
                            immersiveFeed: true,
                            videoExpanded: videoExpanded,
                            showsTheaterControls: showsTheaterControls,
                            onTheaterPresentationChange: { theaterOptionsPresented = $0 },
                            onToggleVideoSize: {
                                Haptics.selection()
                                videoExpanded.toggle()
                            },
                            onActivate: { show(clip.id) },
                            onInfo: { infoClip = clip }
                        )
                        .containerRelativeFrame(.vertical)
                        .id(clip.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $currentId)
            .scrollDisabled(lookup.isPresented)
            .scrollIndicators(.hidden)
            .background(Color.watchBackground)
            .clipped()

            // ULTIMATE Explore chrome: back + title + flag.
            HStack(spacing: 10) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(videoExpanded ? .black.opacity(0.45) : .clear, in: Circle())
                }
                .accessibilityLabel("Back")

                if videoExpanded {
                    Button {
                        Haptics.selection()
                        videoExpanded = false
                    } label: {
                        Label("Normal size", systemImage: "arrow.down.right.and.arrow.up.left")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .frame(minHeight: 40)
                            .background(.black.opacity(0.55), in: Capsule())
                    }
                } else {
                    Text("Explore")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                }

                Spacer(minLength: 0)

                if !videoExpanded {
                    Button {
                        if let id = currentId, let clip = clips.first(where: { $0.id == id }) {
                            infoClip = clip
                        }
                    } label: {
                        Image(systemName: "flag")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.75))
                            .frame(width: 40, height: 40)
                    }
                    .accessibilityLabel("Report clip")
                }
            }
            .padding(.leading, Spacing.m)
            .padding(.trailing, Spacing.m)
            .padding(.top, Spacing.s)
            .opacity(!videoExpanded || showsTheaterControls ? 1 : 0)
            .allowsHitTesting(!videoExpanded || showsTheaterControls)
            .accessibilityHidden(videoExpanded && !showsTheaterControls)
        }
        .background(Color.watchBackground.ignoresSafeArea())
        .environment(coordinator)
        .environment(lookup)
        .modifier(TheaterChromeModifier(
            expanded: videoExpanded,
            visible: $showsTheaterControls,
            playing: coordinator.player?.isPlaying == true,
            blocked: lookup.isPresented || theaterOptionsPresented || infoClip != nil
        ))
        .onAppear {
            coordinator.onWatchTick = { [weak app] seconds in app?.addWatch(seconds: seconds) }
            coordinator.onFinished = { [weak app, weak coordinator] in
                guard !loopPlayback, let id = coordinator?.activeClipId else { return }
                app?.markClipFinished(id)
            }
            if currentId == nil { currentId = startId }
            if let currentId { show(currentId) }
        }
        .onDisappear { coordinator.stop() }
        .onChange(of: currentId) { _, id in
            lookup.dismiss()
            guard let id else { return }
            show(id)
        }
        .onChange(of: forcedId) { _, id in
            guard let id, id != currentId else { return }
            withAnimation(.easeInOut(duration: 0.55)) { currentId = id }
        }
        .sheet(item: $infoClip) { clip in
            ClipInfoSheet(clip: clip)
        }
    }

    private func show(_ id: String) {
        guard let clip = clips.first(where: { $0.id == id }) else { return }
        guard coordinator.activeClipId != id || !appliedStart else { return }
        let useStart = !appliedStart && id == startId
        appliedStart = true
        coordinator.activate(
            clip,
            startLine: (loopPlayback && id == startId) ? startLine : (useStart ? startLine : nil),
            loopLine: loopPlayback || (useStart && loopLine)
        )
        if !loopPlayback { track("clip_view", props: ["clip": clip.id, "tab": "Explore"]) }
        if let index = clips.firstIndex(where: { $0.id == id }), let next = clips[safe: index + 1] {
            coordinator.preload(next)
        }
    }
}

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

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var coordinator = PlaybackCoordinator()
    @State private var lookup = WordLookupController()
    @State private var currentId: String?
    @State private var videoExpanded: Bool = true
    @State private var infoClip: Clip?
    @State private var appliedStart: Bool = false

    init(
        clips: [Clip],
        startId: String,
        startLine: Int? = nil,
        loopLine: Bool = false,
        forcedId: String? = nil,
        loopPlayback: Bool = false
    ) {
        self.clips = clips
        self.startId = startId
        self.startLine = startLine
        self.loopLine = loopLine
        self.forcedId = forcedId
        self.loopPlayback = loopPlayback
        _currentId = State(initialValue: startId)
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
                            onToggleVideoSize: {
                                Haptics.selection()
                                withAnimation(.snappy) { videoExpanded.toggle() }
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

            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(.black.opacity(0.45), in: Circle())
            }
            .padding(.leading, Spacing.m)
            .padding(.top, Spacing.s)
            .accessibilityLabel("Back")
        }
        .background(Color.watchBackground.ignoresSafeArea())
        .environment(coordinator)
        .environment(lookup)
        .onAppear {
            coordinator.onWatchTick = { [weak app] seconds in app?.addWatch(seconds: seconds) }
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
            startLine: loopPlayback ? 0 : (useStart ? startLine : nil),
            loopLine: loopPlayback || (useStart && loopLine)
        )
    }
}

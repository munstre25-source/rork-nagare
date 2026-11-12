import SwiftUI

/// Explore single-clip player (ULTIMATE APP layout): back + Explore title, video with
/// boxed max/min, karaoke underneath. Matches ClipQueueScreen chrome.
struct ImmersivePlayerScreen: View {
    let clip: Clip
    var startLine: Int?
    var loopLine: Bool = false
    /// Shown in the top bar — Explore by default.
    var chromeTitle: String = "Explore"

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var coordinator = PlaybackCoordinator()
    @State private var lookup = WordLookupController()
    @State private var infoClip: Clip?
    @State private var videoExpanded: Bool = false
    @State private var showsTheaterControls = false
    @State private var theaterOptionsPresented = false

    var body: some View {
        VStack(spacing: 0) {
            if !videoExpanded { topBar }
            ClipStageView(
                clip: clip,
                videoAspect: 16 / 9,
                showsChannelRow: false,
                showsRail: false,
                immersiveFeed: true,
                videoExpanded: videoExpanded,
                showsTheaterControls: showsTheaterControls,
                onTheaterPresentationChange: { theaterOptionsPresented = $0 },
                onToggleVideoSize: {
                    Haptics.selection()
                    withAnimation(.easeInOut(duration: 0.25)) { videoExpanded.toggle() }
                },
                onActivate: { coordinator.activate(clip, startLine: startLine, loopLine: loopLine) },
                onInfo: { infoClip = clip }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .environment(\.colorScheme, .dark)
        .preferredColorScheme(.dark)
        .onAppear {
            coordinator.onWatchTick = { [weak app] seconds in app?.addWatch(seconds: seconds, clipId: clip.id) }
            coordinator.onFinished = { [weak app] in
                guard !loopLine else { return }
                app?.markClipFinished(clip.id)
            }
            coordinator.activate(clip, startLine: startLine, loopLine: loopLine)
            track("clip_view", props: ["clip": clip.id, "tab": "Explore"])
        }
        .onDisappear { coordinator.stop() }
        .sheet(item: $infoClip) { clip in
            ClipInfoSheet(clip: clip)
        }
        .overlay(alignment: .top) {
            if videoExpanded && showsTheaterControls {
                HStack {
                    Button {
                        coordinator.stop()
                        dismiss()
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                    Spacer(minLength: 0)
                    Button {
                        Haptics.selection()
                        withAnimation(.easeInOut(duration: 0.25)) { videoExpanded = false }
                    } label: {
                        Label {
                            Text("Normal size")
                        } icon: {
                            VideoSizeGlyph(expanded: true, size: 18)
                        }
                    }
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, Spacing.m)
                .padding(.top, Spacing.s)
                .buttonStyle(.bordered)
                .tint(.black.opacity(0.55))
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: Spacing.m) {
            Button {
                coordinator.stop()
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
            }
            .accessibilityLabel("Back")

            Text(chromeTitle)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)

            Spacer(minLength: 0)

            Button {
                infoClip = clip
            } label: {
                Image(systemName: "flag")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 40, height: 40)
            }
            .accessibilityLabel("Report clip")
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.s)
    }
}

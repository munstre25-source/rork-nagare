import SwiftUI

/// Full-screen single-clip player (fullscreen button, Explore, Review thumbnails, Search results).
/// Has its own playback coordinator and popup controller, and reuses the same Feed components.
struct ClipPlayerScreen: View {
    let clip: Clip
    var startLine: Int?
    var loopLine: Bool = false

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var coordinator = PlaybackCoordinator()
    @State private var lookup = WordLookupController()
    @State private var infoClip: Clip?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    coordinator.stop()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.white.opacity(0.1), in: Circle())
                }
                .accessibilityLabel("Close")
                VStack(alignment: .leading, spacing: 1) {
                    Text(clip.title).font(.headline).foregroundStyle(.white).lineLimit(1)
                    Text(clip.channelName).font(.caption).foregroundStyle(.white.opacity(0.55))
                }
                Spacer()
            }
            .padding(.horizontal, Spacing.l)
            .padding(.bottom, Spacing.s)
            ClipStageView(
                clip: clip,
                videoAspect: 16 / 11,
                showsChannelRow: false,
                onActivate: { coordinator.activate(clip) },
                onInfo: { infoClip = clip }
            )
        }
        .background(Color.bgPlayer.ignoresSafeArea())
        .environment(coordinator)
        .environment(lookup)
        .environment(\.colorScheme, .dark)
        .onAppear {
            coordinator.onWatchTick = { [weak app] seconds in app?.addWatch(seconds: seconds) }
            coordinator.activate(clip, startLine: startLine, loopLine: loopLine)
        }
        .onDisappear { coordinator.stop() }
        .sheet(item: $infoClip) { clip in
            ClipInfoSheet(clip: clip).environment(\.colorScheme, .dark)
        }
    }
}

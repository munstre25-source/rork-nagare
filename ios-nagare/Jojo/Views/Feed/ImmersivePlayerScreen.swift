import SwiftUI

/// Full-screen Kiku-style player: black canvas, channel header, centered video,
/// right rail, karaoke transcript, share / YouTube footer.
struct ImmersivePlayerScreen: View {
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
            topBar
            ClipStageView(
                clip: clip,
                videoAspect: 16 / 9,
                showsChannelRow: false,
                showsRail: false,
                immersiveFeed: true,
                onActivate: { coordinator.activate(clip, startLine: startLine, loopLine: loopLine) },
                onInfo: { infoClip = clip }
            )
            .overlay(alignment: .trailing) {
                immersiveRail
                    .padding(.trailing, Spacing.s)
                    .padding(.bottom, 120)
            }
            footer
        }
        .background(Color.watchBackground.ignoresSafeArea())
        .environment(coordinator)
        .environment(lookup)
        .environment(\.colorScheme, .dark)
        .preferredColorScheme(.dark)
        .onAppear {
            coordinator.onWatchTick = { [weak app] seconds in app?.addWatch(seconds: seconds) }
            coordinator.activate(clip, startLine: startLine, loopLine: loopLine)
        }
        .onDisappear { coordinator.stop() }
        .sheet(item: $infoClip) { clip in
            ClipInfoSheet(clip: clip)
        }
    }

    private var topBar: some View {
        HStack(spacing: Spacing.m) {
            Button {
                coordinator.stop()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.12), in: Circle())
            }
            .accessibilityLabel("Close")
            ChannelAvatar(clip: clip, size: 36)
            VStack(alignment: .leading, spacing: 1) {
                Text(clip.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(clip.channelName)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }
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

    private var immersiveRail: some View {
        VStack(spacing: Spacing.s) {
            Button {
                Haptics.light()
                withAnimation(.snappy) { _ = app.toggleFavorite(clip.id) }
            } label: {
                Image(systemName: app.isFavorite(clip.id) ? "bookmark.fill" : "bookmark")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(app.isFavorite(clip.id) ? Color.jojoOrange : .white)
                    .frame(width: 44, height: 44)
                    .background(.black.opacity(0.35), in: Circle())
            }
            .accessibilityLabel(app.isFavorite(clip.id) ? "Remove bookmark" : "Bookmark clip")

            Button {
                infoClip = clip
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.black.opacity(0.35), in: Circle())
            }
            .accessibilityLabel("Clip info")

            Button {
                Haptics.selection()
                cycleSubtitles()
            } label: {
                Image(systemName: "captions.bubble")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.black.opacity(0.35), in: Circle())
            }
            .accessibilityLabel("Cycle subtitles")

            Button {
                coordinator.stop()
                dismiss()
            } label: {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.black.opacity(0.35), in: Circle())
            }
            .accessibilityLabel("Collapse")
        }
    }

    private var footer: some View {
        HStack(spacing: Spacing.m) {
            ShareLink(item: shareText) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Share clip")

            Spacer(minLength: 0)

            ClipPosterView(clip: clip, showsSymbol: false)
                .frame(width: 56, height: 36)
                .clipShape(.rect(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                )

            if clip.hasRealVideo {
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color(hex: "#FF0033"))
                    .accessibilityLabel("Source: YouTube")
            }
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.s)
        .background(Color.bgPlayer)
    }

    private var shareText: String {
        if let url = clip.youtubeURL {
            return "Learning Japanese with “\(clip.title)” on Jojo 流れ \(url.absoluteString)"
        }
        let line = clip.lines.first.map { "\($0.text) — \($0.translation)" } ?? ""
        return "Learning Japanese with “\(clip.title)” on Jojo 流れ\n\(line)"
    }

    private func cycleSubtitles() {
        let modes = SubtitleMode.allCases
        let current = app.profile.subtitles
        let next = modes[(modes.firstIndex(of: current)! + 1) % modes.count]
        app.setSubtitleMode(next)
    }
}

import SwiftUI

/// Shorts title row drawn on the picture (Kiku): avatar, title, channel. Always white on a scrim.
struct ShortsHeader: View {
    let clip: Clip

    var body: some View {
        HStack(spacing: 10) {
            ChannelAvatar(clip: clip)
            VStack(alignment: .leading, spacing: 1) {
                Text(clip.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(clip.channelName)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .shadow(color: .black.opacity(0.35), radius: 6, y: 1)
        .accessibilityElement(children: .combine)
    }
}

/// Right-hand Shorts rail: speed, bookmark, captions, info, fullscreen. 44pt targets, white glyphs.
struct ShortsRail: View {
    let clip: Clip
    let player: (any ClipPlayer)?
    var showsCaptions: Bool
    var onToggleCaptions: () -> Void
    var onInfo: (() -> Void)?
    var onFullscreen: (() -> Void)?
    /// Portrait shorts: enter the in-feed theater (chrome steps away) instead of opening
    /// another player screen — resizing never leaves the feed.
    var onMaximize: (() -> Void)? = nil
    /// Maximized landscape: the last control returns the video to its usual size.
    var onMinimize: (() -> Void)? = nil
    /// White glyphs on footage; theme ink when the rail sits on the page.
    var onPicture: Bool = true

    @Environment(AppModel.self) private var app
    @Environment(PlaybackCoordinator.self) private var coordinator

    private var ink: Color { onPicture ? .white : .primary }

    private var rateLabel: String {
        switch coordinator.preferredRate {
        case 0.75: "0.75x"
        case 0.5: "0.5x"
        default: "1x"
        }
    }

    var body: some View {
        VStack(spacing: 2) {
            Button {
                Haptics.selection()
                coordinator.cycleRate()
            } label: {
                Text(rateLabel)
                    .font(.caption.weight(.heavy))
                    .monospacedDigit()
                    .foregroundStyle(ink)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Playback speed \(rateLabel)")

            railButton(
                app.isFavorite(clip.id) ? "bookmark.fill" : "bookmark",
                tint: app.isFavorite(clip.id) ? Color.designOrange : ink,
                label: app.isFavorite(clip.id) ? "Remove bookmark" : "Bookmark clip"
            ) {
                Haptics.light()
                withAnimation(.snappy) { _ = app.toggleFavorite(clip.id) }
            }

            if let onInfo {
                railButton("info.circle", tint: ink, label: "Clip info", action: onInfo)
            }

            railButton(
                showsCaptions ? "captions.bubble.fill" : "captions.bubble",
                tint: showsCaptions ? Color.designOrange : ink,
                label: showsCaptions ? "Hide words" : "Show words"
            ) {
                Haptics.selection()
                onToggleCaptions()
            }

            if let onMaximize {
                railButton("arrow.up.left.and.arrow.down.right", tint: ink, label: "Maximize video") {
                    onMaximize()
                }
            } else if let onFullscreen {
                railButton(onMinimize == nil ? "arrow.up.left.and.arrow.down.right" : "rotate.right",
                           tint: ink, label: onMinimize == nil ? "Fullscreen" : "Rotate to fullscreen") {
                    Haptics.selection()
                    onFullscreen()
                }
            }

            if let onMinimize {
                railButton("arrow.down.right.and.arrow.up.left", tint: ink, label: "Minimize video") {
                    Haptics.selection()
                    onMinimize()
                }
            }
        }
        .shadow(color: .black.opacity(onPicture ? 0.45 : 0), radius: 6, y: 1)
    }

    private func railButton(_ system: String, tint: Color, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(tint)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
    }
}

/// Bottom of a Short: thin progress, time, and the YouTube Shorts source mark.
struct ShortsFooter: View {
    let clip: Clip
    let player: (any ClipPlayer)?
    var onPicture: Bool = true
    var sourceMark: String = "Shorts"

    private var ink: Color { onPicture ? .white : .primary }

    private var progress: Double {
        let duration = max(player?.duration ?? clip.durationSec, 0.001)
        return min(1, max(0, (player?.currentTime ?? 0) / duration))
    }

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(ink.opacity(0.22))
                    Capsule()
                        .fill(Color.designOrange)
                        .frame(width: max(3, proxy.size.width * progress))
                }
            }
            .frame(height: 3)

            HStack {
                Text("\(formatClock(player?.currentTime ?? 0)) / \(formatClock(player?.duration ?? clip.durationSec))")
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(ink.opacity(0.8))
                Spacer(minLength: 8)
                HStack(spacing: 4) {
                    Image(systemName: "play.rectangle.fill")
                        .font(.system(size: 12, weight: .bold))
                    Text(sourceMark)
                        .font(.caption.weight(.heavy))
                }
                .foregroundStyle(ink.opacity(0.85))
                .accessibilityLabel(sourceMark == "Shorts" ? "YouTube Shorts" : "YouTube")
            }
        }
        .allowsHitTesting(false)
    }
}

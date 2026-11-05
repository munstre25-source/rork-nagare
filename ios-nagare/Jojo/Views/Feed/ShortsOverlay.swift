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

/// Right-hand Shorts rail over the picture: speed, like, bookmark, CC, gear, info, size.
struct ShortsRail: View {
    let clip: Clip
    let player: (any ClipPlayer)?
    var expanded: Bool
    var onInfo: (() -> Void)?
    var onToggleSize: (() -> Void)?
    var onPresentationChange: (Bool) -> Void = { _ in }

    @Environment(AppModel.self) private var app
    @Environment(PlaybackCoordinator.self) private var coordinator

    private var rateLabel: String {
        switch coordinator.preferredRate {
        case 0.75: "0.75x"
        case 0.5: "0.5x"
        default: "1x"
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            Button {
                Haptics.selection()
                coordinator.cycleRate()
            } label: {
                Text(rateLabel)
                    .font(.caption.weight(.heavy))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .modifier(VideoControlSurface())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Playback speed \(rateLabel)")

            railButton(
                app.isLiked(clip.id) ? "heart.fill" : "heart",
                tint: app.isLiked(clip.id) ? .videoControlAccent : .white,
                label: app.isLiked(clip.id) ? "Unlike video" : "Like video"
            ) {
                Haptics.light()
                withAnimation(.snappy) { _ = app.toggleLike(clip.id) }
            }

            railButton(
                app.isFavorite(clip.id) ? "bookmark.fill" : "bookmark",
                tint: app.isFavorite(clip.id) ? .videoControlAccent : .white,
                label: app.isFavorite(clip.id) ? "Remove bookmark" : "Bookmark clip"
            ) {
                Haptics.light()
                withAnimation(.snappy) { _ = app.toggleFavorite(clip.id) }
            }

            SubtitlesToggleButton(tint: .white, activeTint: .videoControlAccent, size: 18, width: 42, onPicture: true)
                .frame(height: 42)

            PlayerSettingsButton(clip: clip, player: player, tint: .white, size: 18, width: 42,
                                 onPicture: true, onPresentationChange: onPresentationChange)
                .frame(height: 42)

            if let onInfo {
                railButton("info.circle", tint: .white, label: "Clip info", action: onInfo)
            }

            if let onToggleSize {
                railButton(expanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                           tint: .white, label: expanded ? "Normal video size" : "Focus on the video") {
                    onToggleSize()
                }
            }
        }
        .shadow(color: .black.opacity(0.4), radius: 6, y: 1)
    }

    private func railButton(_ system: String, tint: Color, label: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            Image(systemName: system)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 42, height: 42)
                .contentShape(Rectangle())
                .modifier(VideoControlSurface())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Bottom-left of a Short: share and time, with a hairline progress along the picture's edge.
struct ShortsBottomBar: View {
    let clip: Clip
    let player: (any ClipPlayer)?

    private var progress: Double {
        let duration = max(player?.duration ?? clip.durationSec, 0.001)
        return min(1, max(0, (player?.currentTime ?? 0) / duration))
    }

    private var shareText: String {
        if let url = clip.youtubeURL {
            return "Learning Japanese with “\(clip.title)” on Jojo 流れ \(url.absoluteString)"
        }
        return "Learning Japanese with “\(clip.title)” on Jojo 流れ"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                ShareLink(item: shareText) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .modifier(VideoControlSurface())
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Share clip")
                Text("\(formatClock(player?.currentTime ?? 0)) / \(formatClock(player?.duration ?? clip.durationSec))")
                    .font(.caption2.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.videoControlBackground, in: Capsule())
                    .accessibilityLabel("Elapsed time")
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Rectangle().fill(.white.opacity(0.22))
                    Rectangle()
                        .fill(Color.videoControlAccent)
                        .frame(width: max(2, proxy.size.width * progress))
                }
            }
            .frame(height: 2.5)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

/// One quiet entry point for subtitle help on both landscape clips and Shorts.
struct TranscriptDisplayMenu: View {
    var tint: Color = .secondary
    var compact: Bool = false
    var onPicture: Bool = false
    var onPresentationChange: (Bool) -> Void = { _ in }

    @Environment(AppModel.self) private var app
    @State private var showsSettings = false

    var body: some View {
        Button {
            Haptics.selection()
            showsSettings = true
        } label: {
            Image(systemName: "captions.bubble")
                .font(.system(size: compact ? 19 : 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: compact ? 44 : 34, height: 44)
                .contentShape(Rectangle())
                .modifier(VideoControlSurface(onPicture: onPicture))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Subtitle help")
        .accessibilityValue(app.profile.subtitleDisplay.learningMode?.title ?? "Custom")
        .accessibilityHint("Opens learning modes, English, furigana, romaji and word lookup")
        .onChange(of: showsSettings) { _, presented in onPresentationChange(presented) }
        .sheet(isPresented: $showsSettings, onDismiss: {
            app.completeSubtitleSetup()
        }) {
            SubtitleLearningSettingsSheet()
        }
    }
}

/// Bottom of a Short: thin progress, time, and the YouTube Shorts source mark.
struct ShortsFooter: View {
    let clip: Clip
    let player: (any ClipPlayer)?
    var onPicture: Bool = true
    var sourceMark: String = "Shorts"

    private var ink: Color { onPicture ? .white : .primary }
    private var activeInk: Color { onPicture ? .videoControlAccent : .designOrange }

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
                        .fill(activeInk)
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
        .padding(.horizontal, onPicture ? 10 : 0)
        .padding(.vertical, onPicture ? 6 : 0)
        .background {
            if onPicture {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.videoControlBackground)
            }
        }
        .allowsHitTesting(false)
    }
}

/// A predictable backing for glyphs over video, including bright frames and black letterboxing.
struct VideoControlSurface: ViewModifier {
    var onPicture: Bool = true

    func body(content: Content) -> some View {
        content.background {
            if onPicture {
                Circle()
                    .fill(Color.videoControlBackground)
                    .overlay {
                        Circle().strokeBorder(.white.opacity(0.18), lineWidth: 0.75)
                    }
            }
        }
    }
}

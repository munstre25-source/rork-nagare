import SwiftUI

/// Formats seconds as m:ss.
nonisolated func formatClock(_ seconds: Double) -> String {
    let total = max(0, Int(seconds.rounded(.down)))
    return String(format: "%d:%02d", total / 60, total % 60)
}

/// The video surface: real YouTube or animated gradient poster, with play overlay, scrubber and controls.
struct ClipVideoView: View {
    let clip: Clip
    let player: (any ClipPlayer)?
    var showsControls: Bool = true
    var showsRail: Bool = true
    var onActivate: () -> Void = {}
    var onFullscreen: (() -> Void)?
    var onInfo: (() -> Void)?

    @Environment(AppModel.self) private var app
    @Environment(PlaybackCoordinator.self) private var coordinator
    @State private var heartBurst: Bool = false

    var body: some View {
        ZStack {
            surface
            if player?.isPlaying != true {
                Image(systemName: "play.fill")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 68, height: 68)
                    .background(.black.opacity(0.35), in: Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.2), lineWidth: 1))
                    .transition(.scale.combined(with: .opacity))
                    .allowsHitTesting(false)
            }
            if heartBurst {
                Image(systemName: "heart.fill")
                    .font(.system(size: 84))
                    .foregroundStyle(Color.nagareOrange)
                    .shadow(color: .black.opacity(0.4), radius: 12)
                    .transition(.scale(scale: 0.3).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if let player {
                withAnimation(.snappy) { player.togglePlay() }
            } else {
                onActivate()
            }
        }
        .onLongPressGesture(minimumDuration: 0.45) {
            let added = app.toggleFavorite(clip.id)
            Haptics.success()
            guard added else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) { heartBurst = true }
            Task {
                try? await Task.sleep(for: .milliseconds(750))
                withAnimation(.easeOut(duration: 0.25)) { heartBurst = false }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(clip.title) video")
        .accessibilityAction(named: "Play or pause") { player?.togglePlay() }
        .accessibilityAction(named: "Save to favorites") { _ = app.toggleFavorite(clip.id) }
        .overlay(alignment: .topLeading) { sourceBadge }
        .overlay(alignment: .trailing) {
            if showsRail { rail }
        }
        .overlay(alignment: .bottom) {
            if showsControls { controls }
        }
        .clipped()
    }

    @ViewBuilder
    private var surface: some View {
        if let youtube = player as? YouTubeClipPlayer {
            ZStack {
                GradientPoster(clip: clip, isAnimating: false)
                YouTubePlayerView(player: youtube)
                    .opacity(youtube.isReady ? 1 : 0)
            }
        } else {
            GradientPoster(clip: clip, isAnimating: player?.isPlaying == true)
        }
    }

    private var sourceBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: clip.hasRealVideo ? "play.rectangle.fill" : "waveform")
                .foregroundStyle(clip.hasRealVideo ? Color(hex: "#FF0033") : Color.nagareOrange)
            Text(clip.hasRealVideo ? "YouTube" : "Jojo Preview")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.black.opacity(0.4), in: Capsule())
        .padding(Spacing.m)
        .accessibilityLabel(clip.hasRealVideo ? "Source: YouTube" : "Preview clip")
    }

    private var rail: some View {
        VStack(spacing: Spacing.s) {
            RailButton(
                systemImage: app.isFavorite(clip.id) ? "bookmark.fill" : "bookmark",
                tint: app.isFavorite(clip.id) ? .nagareOrange : .white,
                label: app.isFavorite(clip.id) ? "Remove bookmark" : "Bookmark clip"
            ) {
                Haptics.light()
                withAnimation(.snappy) { _ = app.toggleFavorite(clip.id) }
            }
            if let onInfo {
                RailButton(systemImage: "info.circle", label: "Clip info", action: onInfo)
            }
        }
        .padding(.trailing, Spacing.s)
        .padding(.bottom, 40)
    }

    private var controls: some View {
        VStack(spacing: 0) {
            HStack(spacing: 2) {
                ShareLink(item: shareText) {
                    ControlIcon(systemImage: "square.and.arrow.up")
                }
                .accessibilityLabel("Share clip")
                PlaybackClock(clip: clip, player: player)
                Spacer(minLength: 0)
                Button {
                    Haptics.selection()
                    coordinator.cycleRate()
                } label: {
                    Text(rateLabel)
                        .font(.footnote.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .frame(minWidth: 44, minHeight: 30)
                        .background(.white.opacity(0.16), in: Capsule())
                        .frame(minHeight: 44)
                }
                .accessibilityLabel("Playback speed \(rateLabel)")
                Button {
                    Haptics.selection()
                    if player == nil { onActivate() }
                    player?.toggleLoopCurrentLine()
                } label: {
                    ControlIcon(systemImage: "repeat", tint: player?.loopRange != nil ? .nagareOrange : .white)
                }
                .accessibilityLabel(player?.loopRange != nil ? "Stop looping line" : "Loop current line")
                if let onFullscreen {
                    Button(action: onFullscreen) {
                        ControlIcon(systemImage: "arrow.up.left.and.arrow.down.right")
                    }
                    .accessibilityLabel("Fullscreen")
                }
                Button {
                    Haptics.selection()
                    coordinator.toggleMute()
                } label: {
                    ControlIcon(systemImage: coordinator.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                }
                .accessibilityLabel(coordinator.isMuted ? "Unmute" : "Mute")
            }
            .padding(.horizontal, Spacing.s)
            Scrubber(clip: clip, player: player)
        }
        .background(
            LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                .allowsHitTesting(false)
        )
    }

    private var rateLabel: String {
        switch coordinator.preferredRate {
        case 0.75: "0.75x"
        case 0.5: "0.5x"
        default: "1x"
        }
    }

    private var shareText: String {
        if let url = clip.youtubeURL {
            return "Learning Japanese with “\(clip.title)” on Jojo 流れ \(url.absoluteString)"
        }
        let line = clip.lines.first.map { "\($0.text) — \($0.translation)" } ?? ""
        return "Learning Japanese with “\(clip.title)” on Jojo 流れ\n\(line)"
    }
}

/// Elapsed / total label; isolated so only it re-renders on time changes.
private struct PlaybackClock: View {
    let clip: Clip
    let player: (any ClipPlayer)?

    var body: some View {
        Text("\(formatClock(player?.currentTime ?? 0)) / \(formatClock(clip.durationSec))")
            .font(.footnote.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(.white.opacity(0.9))
            .fixedSize()
    }
}

/// Thin draggable progress line.
private struct Scrubber: View {
    let clip: Clip
    let player: (any ClipPlayer)?
    @State private var dragProgress: Double?

    var body: some View {
        GeometryReader { proxy in
            let progress = dragProgress ?? ((player?.currentTime ?? 0) / max(clip.durationSec, 1))
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.22)).frame(height: 3)
                Capsule().fill(Color.nagareOrange).frame(width: proxy.size.width * progress, height: 3)
                Circle()
                    .fill(Color.nagareOrange)
                    .frame(width: dragProgress == nil ? 0 : 14, height: 14)
                    .offset(x: proxy.size.width * progress - 7)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        dragProgress = min(max(value.location.x / max(proxy.size.width, 1), 0), 1)
                    }
                    .onEnded { _ in
                        if let dragProgress { player?.seek(to: dragProgress * clip.durationSec) }
                        dragProgress = nil
                    }
            )
        }
        .frame(height: 18)
        .padding(.horizontal, Spacing.s)
        .accessibilityElement()
        .accessibilityLabel("Playback position")
        .accessibilityValue(formatClock(player?.currentTime ?? 0))
        .accessibilityAdjustableAction { direction in
            let t = player?.currentTime ?? 0
            switch direction {
            case .increment: player?.seek(to: t + 3)
            case .decrement: player?.seek(to: t - 3)
            @unknown default: break
            }
        }
    }
}

struct ControlIcon: View {
    let systemImage: String
    var tint: Color = .white

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }
}

private struct RailButton: View {
    let systemImage: String
    var tint: Color = .white
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(.black.opacity(0.35), in: Circle())
        }
        .accessibilityLabel(label)
    }
}

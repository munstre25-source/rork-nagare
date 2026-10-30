import SwiftUI
import AVFoundation

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
    /// Feed mode: scrubber + time + speed only; thin rail and tiny source mark.
    var compactChrome: Bool = false
    var onActivate: () -> Void = {}
    var onFullscreen: (() -> Void)?
    var onInfo: (() -> Void)?
    var onShadowing: (() -> Void)?
    /// Shows the entire picture inside the frame, the way the maximized feed does.
    var fitsFrame: Bool = false
    /// Feed focus: a tap on the video brings the chrome back instead of pausing.
    var watchChromeHidden: Bool = false
    var onRevealWatchChrome: () -> Void = {}
    /// Advance the feed when a YouTube embed cannot be recovered.
    var onSkip: (() -> Void)? = nil

    @Environment(AppModel.self) private var app
    @Environment(PlaybackCoordinator.self) private var coordinator
    @Environment(\.openURL) private var openURL
    @State private var saveBurst: Bool = false
    @State private var savedWordLabel: String?
    @State private var holdHint: Bool = false
    @State private var showFeatureRequest = false

    var body: some View {
        ZStack {
            surface
            if embedFailed {
                embedFailure
            }
            if player?.isPlaying != true, !coordinator.isHoldSlowActive, !embedFailed {
                Image(systemName: "play.fill")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 68, height: 68)
                    .background(.black.opacity(0.35), in: Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.2), lineWidth: 1))
                    .transition(.scale.combined(with: .opacity))
                    .allowsHitTesting(false)
            }
            if coordinator.isHoldSlowActive {
                VStack(spacing: 6) {
                    Image(systemName: "tortoise.fill")
                        .font(.title2)
                    Text("0.75× · looping line")
                        .font(.caption.weight(.bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.black.opacity(0.55), in: Capsule())
                .transition(.opacity)
                .allowsHitTesting(false)
            }
            if saveBurst {
                VStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 64))
                        .foregroundStyle(Color.jojoOrange)
                        .shadow(color: .black.opacity(0.4), radius: 12)
                    if let savedWordLabel {
                        Text(savedWordLabel)
                            .font(JojoFont.jp(18, bold: true, relativeTo: .headline))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.black.opacity(0.55), in: Capsule())
                    }
                }
                .transition(.scale(scale: 0.3).combined(with: .opacity))
                .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { doubleTapSave() }
        .onTapGesture(count: 1) {
            if embedFailed { return }
            if watchChromeHidden {
                onRevealWatchChrome()
                return
            }
            if let player {
                withAnimation(.snappy) { player.togglePlay() }
            } else {
                onActivate()
            }
        }
        .onLongPressGesture(minimumDuration: 0.35, maximumDistance: 48, pressing: { pressing in
            if pressing {
                if player == nil { onActivate() }
                coordinator.beginHoldSlow()
                withAnimation(.snappy) { holdHint = true }
                Haptics.medium()
            } else {
                coordinator.endHoldSlow()
                withAnimation(.snappy) { holdHint = false }
            }
        }, perform: {})
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(clip.title) video")
        .accessibilityHint("Double tap to save the current line. Hold to slow and loop.")
        .accessibilityAction(named: "Play or pause") { player?.togglePlay() }
        .accessibilityAction(named: "Save current line") { doubleTapSave() }
        .accessibilityAction(named: "Save to favorites") { _ = app.toggleFavorite(clip.id) }
        .overlay(alignment: .topLeading) { sourceBadge }
        .overlay(alignment: .trailing) {
            if showsRail { rail }
        }
        .overlay(alignment: .bottom) {
            if showsControls { controls }
        }
        .task(id: embedFailed) {
            // Never leave a learner staring at a dead clip: move on after a short beat.
            // Except when YouTube is limiting the whole network: auto-skipping then just fires
            // embed after embed at YouTube (the 2026-10-30 storm) and every clip fails anyway.
            guard embedFailed, let onSkip, !YouTubeSession.shared.isLimited else { return }
            try? await Task.sleep(for: .milliseconds(1800))
            guard !Task.isCancelled, embedFailed, !YouTubeSession.shared.isLimited else { return }
            onSkip()
        }
        .sheet(isPresented: $showFeatureRequest, onDismiss: {
            coordinator.resumeAfterPopupIfNeeded()
        }) {
            ClipFeatureRequestSheet(contextNote: "While watching “\(clip.title)”.")
        }
        .clipped()
    }

    private func openFeatureRequest() {
        Haptics.selection()
        coordinator.pauseForPopup()
        showFeatureRequest = true
    }

    private func doubleTapSave() {
        let lineIndex = player?.currentLineIndex ?? 0
        let count = app.saveLine(clip: clip, lineIndex: lineIndex)
        guard count > 0 else {
            Haptics.warning()
            return
        }
        Haptics.success()
        let surface = clip.lines[safe: lineIndex]?.tokens.first(where: \.tappable)?.surface
        savedWordLabel = surface.map { "Saved · \($0)" } ?? "Saved \(count) words"
        withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) { saveBurst = true }
        Task {
            try? await Task.sleep(for: .milliseconds(900))
            withAnimation(.easeOut(duration: 0.25)) {
                saveBurst = false
                savedWordLabel = nil
            }
        }
    }

    @ViewBuilder
    private var surface: some View {
        if let local = player as? LocalClipPlayer {
            ZStack {
                ClipPosterView(clip: clip, showsSymbol: false)
                LocalPlayerView(player: local, gravity: fitsFrame ? .resizeAspect : .resizeAspectFill)
                    // Keep a faint underlay until the first frame is ready so the surface never goes pure black.
                    .opacity(local.isReady ? 1 : 0.02)
            }
        } else if let youtube = player as? YouTubeClipPlayer {
            ZStack {
                ClipPosterView(clip: clip, showsSymbol: false)
                YouTubePlayerView(player: youtube)
                    .id(youtube.sessionGeneration)
                    .opacity(youtube.hasRenderedVideo && !youtube.embedFailed ? 1 : 0.01)
            }
        } else {
            ClipPosterView(clip: clip, isAnimating: player?.isPlaying == true)
        }
    }

    private var embedFailed: Bool {
        (player as? YouTubeClipPlayer)?.embedFailed == true
    }

    private var networkLimited: Bool {
        YouTubeSession.shared.isLimited && embedErrorIsRefusal
    }

    private var embedErrorIsRefusal: Bool {
        guard let code = (player as? YouTubeClipPlayer)?.embedErrorCode else { return false }
        return code == 101 || code == 150
    }

    private var embedFailureDetail: String {
        guard let code = (player as? YouTubeClipPlayer)?.embedErrorCode else {
            return "Check your connection"
        }
        switch code {
        case 100, 101, 150: return "Not playable in apps · removed from your feed"
        case PlaybackHealth.neverReadyCode, PlaybackHealth.stalledCode: return "The video didn’t start"
        default: return "YouTube error \(code)"
        }
    }

    private var embedFailure: some View {
        VStack(spacing: Spacing.m) {
            Text(networkLimited ? "YouTube is busy on this network" : "Video couldn’t load")
                .font(.headline)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text(networkLimited
                 ? "Retrying on its own — it’ll start the moment YouTube lets it"
                 : onSkip == nil ? embedFailureDetail : "\(embedFailureDetail) · skipping…")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
            HStack(spacing: Spacing.s) {
                if let url = clip.youtubeURL {
                    Button("Open in YouTube") {
                        openURL(url)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.jojoOrange)
                }
                if player is YouTubeClipPlayer {
                    Button("Try again") {
                        Haptics.selection()
                        (player as? YouTubeClipPlayer)?.retry()
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)
                }
                if let onSkip {
                    Button("Skip") {
                        Haptics.selection()
                        onSkip()
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)
                }
            }
        }
        .padding(Spacing.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.55))
    }

    private var sourceBadge: some View {
        Group {
            if clip.hasLocalVideo || clip.hasRealVideo {
                Image(systemName: clip.hasLocalVideo ? "film.fill" : "play.rectangle.fill")
                    .font(.system(size: compactChrome ? 11 : 12, weight: .bold))
                    .foregroundStyle(clip.hasLocalVideo ? Color.jojoOrange : Color(hex: "#FF0033"))
                    .padding(compactChrome ? 6 : 8)
                    .background(.black.opacity(0.45), in: Circle())
                    .padding(Spacing.s)
                    .accessibilityLabel(clip.hasLocalVideo ? "Source: Local video" : "Source: YouTube")
            }
        }
    }

    private var rail: some View {
        VStack(spacing: Spacing.s) {
            RailButton(
                systemImage: app.isFavorite(clip.id) ? "bookmark.fill" : "bookmark",
                tint: app.isFavorite(clip.id) ? .jojoOrange : .white,
                label: app.isFavorite(clip.id) ? "Remove bookmark" : "Bookmark clip"
            ) {
                Haptics.light()
                withAnimation(.snappy) { _ = app.toggleFavorite(clip.id) }
            }
            if let onShadowing {
                RailButton(systemImage: "mic.fill", label: "Shadowing practice", action: onShadowing)
            }
            if let onInfo {
                RailButton(systemImage: "info.circle", label: "Clip info", action: onInfo)
            }
            RailButton(systemImage: "lightbulb.fill", tint: .jojoOrange, label: "Request a feature") {
                openFeatureRequest()
            }
            if !compactChrome, let onFullscreen {
                RailButton(systemImage: "arrow.up.left.and.arrow.down.right", label: "Fullscreen", action: onFullscreen)
            }
        }
        .padding(.trailing, Spacing.s)
        .padding(.bottom, compactChrome ? 28 : 40)
    }

    private var controls: some View {
        VStack(spacing: 0) {
            if compactChrome {
                HStack(spacing: Spacing.s) {
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
                }
                .padding(.horizontal, Spacing.s)
            } else {
                HStack(spacing: 2) {
                    ShareLink(item: shareText) {
                        ControlIcon(systemImage: "square.and.arrow.up", tint: .white)
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
                        ControlIcon(systemImage: "repeat", tint: player?.loopRange != nil ? .jojoOrange : .white)
                    }
                    .accessibilityLabel(player?.loopRange != nil ? "Stop looping line" : "Loop current line")
                    if let onFullscreen {
                        Button(action: onFullscreen) {
                            ControlIcon(systemImage: "arrow.up.left.and.arrow.down.right", tint: .white)
                        }
                        .accessibilityLabel("Fullscreen")
                    }
                    Button {
                        Haptics.selection()
                        coordinator.toggleMute()
                    } label: {
                        ControlIcon(systemImage: coordinator.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill", tint: .white)
                    }
                    .accessibilityLabel(coordinator.isMuted ? "Unmute" : "Mute")
                }
                .padding(.horizontal, Spacing.s)
            }
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
        if let line = clip.lines.first {
            return UnderstoodLineShare.text(line: line, clip: clip, surface: nil)
        }
        if let url = clip.youtubeURL {
            return "Learning Japanese with “\(clip.title)” on Jojo 流れ \(url.absoluteString)"
        }
        return "Learning Japanese with “\(clip.title)” on Jojo 流れ"
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
                Capsule().fill(Color.jojoOrange).frame(width: proxy.size.width * progress, height: 3)
                Circle()
                    .fill(Color.jojoOrange)
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
    var tint: Color = .primary

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

import Foundation
import Observation

/// Owns the single active player for a surface (feed, clip detail, onboarding demo).
/// Only the active clip holds a live player; other pages show their poster.
@Observable
@MainActor
final class PlaybackCoordinator {
    private(set) var player: (any ClipPlayer)?
    private(set) var preferredRate: Double = PlaybackDefaults.storedRate
    private(set) var isMuted: Bool = false
    /// True while the user is hold-to-slow practicing.
    private(set) var isHoldSlowActive: Bool = false
    /// Learner manually cycled rate this session — category defaults stop overriding.
    private(set) var hasManualRate: Bool = false
    @ObservationIgnored var onFinished: (() -> Void)?
    @ObservationIgnored var onWatchTick: ((Double) -> Void)?
    @ObservationIgnored private var resumeAfterPopup = false
    @ObservationIgnored private var rateBeforeHold: Double = 1
    @ObservationIgnored private var loopBeforeHold: ClosedRange<Double>?
    /// Next clip's player, warmed while the current one plays so swiping starts instantly.
    @ObservationIgnored private var preloaded: (any ClipPlayer)?
    @ObservationIgnored private var preloadTask: Task<Void, Never>?

    var activeClipId: String? { player?.clip.id }

    func player(for clip: Clip) -> (any ClipPlayer)? {
        player?.clip.id == clip.id ? player : nil
    }

    func activate(_ clip: Clip, autoplay: Bool = true, startLine: Int? = nil, loopLine: Bool = false, seekTime: Double? = nil) {
        let defaults = PlaybackDefaults.applyCategoryDefaults(for: clip, hasManualRate: hasManualRate)
        if !hasManualRate {
            preferredRate = defaults.rate
        }
        let shouldLoop = loopLine || (!hasManualRate && defaults.preferLineLoop && startLine != nil)

        if let player, player.clip.id == clip.id {
            if let seekTime {
                player.seek(to: max(0, seekTime))
            } else if let startLine {
                position(player, line: startLine, loop: shouldLoop)
            }
            player.setRate(preferredRate)
            if autoplay { player.play() }
            return
        }
        // A pre-warmed player for this exact clip → swap it in, no cold start.
        if let failed = preloaded as? YouTubeClipPlayer, failed.clip.id == clip.id, failed.embedFailed {
            cancelPreload() // a warm player that already failed would only show its failure card
        }
        if let preloaded, preloaded.clip.id == clip.id {
            preloadTask?.cancel()
            preloadTask = nil
            self.preloaded = nil
            if onFinished != nil {
                preloaded.onFinished = { [weak self] in self?.onFinished?() }
            }
            preloaded.onWatchTick = { [weak self] seconds in self?.onWatchTick?(seconds) }
            preloaded.setRate(preferredRate)
            preloaded.setMuted(isMuted)
            if let seekTime {
                preloaded.seek(to: max(0, seekTime))
            } else if let startLine {
                position(preloaded, line: startLine, loop: shouldLoop)
            } else {
                preloaded.seek(to: 0)
            }
            player?.teardown()
            player = preloaded
            if autoplay { preloaded.play() }
            return
        }
        cancelPreload()
        player?.teardown()
        let newPlayer = ClipPlayerFactory.make(for: clip)
        newPlayer.setRate(preferredRate)
        newPlayer.setMuted(isMuted)
        if onFinished != nil {
            newPlayer.onFinished = { [weak self] in self?.onFinished?() }
        }
        newPlayer.onWatchTick = { [weak self] seconds in self?.onWatchTick?(seconds) }
        if let seekTime {
            newPlayer.seek(to: max(0, seekTime))
        } else if let startLine {
            position(newPlayer, line: startLine, loop: shouldLoop)
        }
        player = newPlayer
        if autoplay { newPlayer.play() }
    }

    /// Warms the next clip's player in the background. Local items start preparing
    /// immediately; YouTube's web view is prepared after the active clip renders. The
    /// prewarmed embed never autoplays: concurrent playback sessions can trigger error 150
    /// storms. YouTube may still need to buffer video data after the swipe.
    ///
    /// Gated (2026-10-30, night 12): the warm-up starts only once the current video is
    /// actually playing, and never while YouTube is limiting the network. Swapping the warm
    /// player in means the swipe avoids rebuilding the embed, while preserving one active
    /// playback session at a time.
    func preload(_ clip: Clip) {
        guard player?.clip.id != clip.id, preloaded?.clip.id != clip.id else { return }
        cancelPreload()
        if clip.hasLocalVideo {
            let warm = ClipPlayerFactory.make(for: clip, autoplaysOnLoad: false)
            warm.setRate(preferredRate)
            warm.setMuted(true)
            preloaded = warm
            return
        }
        preloadTask = Task { [weak self] in
            // Wait only for the current clip's first frame; don't add an arbitrary delay.
            var waited = 0
            while let current = self?.player as? YouTubeClipPlayer, !current.hasRenderedVideo, waited < 40 {
                try? await Task.sleep(for: .milliseconds(500))
                waited += 1
                if Task.isCancelled { return }
            }
            guard let self, !Task.isCancelled,
                  !YouTubeSession.shared.isLimited,
                  (self.player as? YouTubeClipPlayer)?.hasRenderedVideo ?? true,
                  self.player?.clip.id != clip.id else { return }
            let warm = ClipPlayerFactory.make(for: clip, autoplaysOnLoad: false)
            warm.setRate(self.preferredRate)
            warm.setMuted(true) // never audible in the background
            if let webPlayer = warm as? YouTubeClipPlayer {
                _ = webPlayer.webView // force creation + embed load + cue
            }
            guard !Task.isCancelled else { warm.teardown(); return }
            self.preloaded = warm
        }
    }

    private func cancelPreload() {
        preloadTask?.cancel()
        preloadTask = nil
        preloaded?.teardown()
        preloaded = nil
    }

    private func position(_ player: any ClipPlayer, line index: Int, loop: Bool) {
        guard let line = player.clip.lines[safe: index] else { return }
        player.seek(to: max(0, line.start - 0.3))
        player.setLoop(loop ? max(0, line.start - 0.3)...min(player.duration, line.end + 0.5) : nil)
    }

    func cycleRate() {
        let next: Double = preferredRate == 1 ? 0.75 : (preferredRate == 0.75 ? 0.5 : 1)
        preferredRate = next
        hasManualRate = true
        PlaybackDefaults.storedRate = next
        player?.setRate(next)
    }

    func toggleMute() {
        isMuted.toggle()
        player?.setMuted(isMuted)
    }

    /// Hold-to-practice: slow to 0.75× and loop the current line until released.
    func beginHoldSlow() {
        guard let player, !isHoldSlowActive else { return }
        isHoldSlowActive = true
        rateBeforeHold = preferredRate
        loopBeforeHold = player.loopRange
        preferredRate = 0.75
        player.setRate(0.75)
        if let line = player.clip.lines[safe: player.currentLineIndex] {
            player.setLoop(max(0, line.start - 0.3)...min(player.duration, line.end + 0.5))
        }
        if !player.isPlaying { player.play() }
    }

    func endHoldSlow() {
        guard isHoldSlowActive else { return }
        isHoldSlowActive = false
        preferredRate = rateBeforeHold
        player?.setRate(rateBeforeHold)
        player?.setLoop(loopBeforeHold)
    }

    func pause() {
        player?.pause()
    }

    /// Pauses for the word popup, remembering whether to resume.
    func pauseForPopup() {
        guard let player else { return }
        resumeAfterPopup = player.isPlaying
        player.pause()
    }

    func resumeAfterPopupIfNeeded() {
        if resumeAfterPopup { player?.play() }
        resumeAfterPopup = false
    }

    func stop() {
        cancelPreload()
        player?.teardown()
        player = nil
    }

    /// Persist resume point for cold start.
    func persistResumePoint() {
        guard let player else { return }
        ResumePlaybackStore.save(
            clip: player.clip,
            time: player.currentTime,
            lineIndex: player.currentLineIndex
        )
    }
}

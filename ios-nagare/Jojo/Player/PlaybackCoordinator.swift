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

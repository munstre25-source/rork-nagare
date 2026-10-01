import Foundation
import Observation

/// Owns the single active player for a surface (feed, clip detail, onboarding demo).
/// Only the active clip holds a live player; other pages show their poster.
@Observable
@MainActor
final class PlaybackCoordinator {
    private(set) var player: (any ClipPlayer)?
    private(set) var preferredRate: Double = 1
    private(set) var isMuted: Bool = false
    @ObservationIgnored var onFinished: (() -> Void)?
    @ObservationIgnored var onWatchTick: ((Double) -> Void)?
    @ObservationIgnored private var resumeAfterPopup = false

    var activeClipId: String? { player?.clip.id }

    func player(for clip: Clip) -> (any ClipPlayer)? {
        player?.clip.id == clip.id ? player : nil
    }

    func activate(_ clip: Clip, autoplay: Bool = true, startLine: Int? = nil, loopLine: Bool = false) {
        if let player, player.clip.id == clip.id {
            if let startLine { position(player, line: startLine, loop: loopLine) }
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
        if let startLine { position(newPlayer, line: startLine, loop: loopLine) }
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
        player?.setRate(next)
    }

    func toggleMute() {
        isMuted.toggle()
        player?.setMuted(isMuted)
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
}

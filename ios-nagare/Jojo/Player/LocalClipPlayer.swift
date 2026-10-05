import Foundation
import Observation
import AVFoundation
import CoreMedia

/// Plays a bundled `Clips/{clip.id}.mp4` with AVPlayer while driving karaoke from the same clock.
/// Prefer this over YouTube in simulators / Rork where WKWebView embeds are unreliable.
@Observable
@MainActor
final class LocalClipPlayer: ClipPlayer {
    let clip: Clip
    private(set) var currentTime: Double = 0
    private(set) var isPlaying = false
    private(set) var rate: Double = 1
    private(set) var isMuted = false
    private(set) var loopRange: ClosedRange<Double>?
    private(set) var isReady = false
    private(set) var spokenLine: Int = 0
    private(set) var spokenToken: Int?
    @ObservationIgnored var onFinished: (() -> Void)?
    @ObservationIgnored var onWatchTick: ((Double) -> Void)?

    @ObservationIgnored private(set) var avPlayer: AVPlayer
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var statusObserver: NSKeyValueObservation?
    @ObservationIgnored private var watchAccumulator: Double = 0
    @ObservationIgnored private var didFinish = false
    @ObservationIgnored private var lastTickWall = Date()
    @ObservationIgnored private var clock: Double = 0

    var duration: Double { clip.durationSec }

    init(clip: Clip) {
        self.clip = clip
        if let url = Clip.bundledVideoURL(for: clip.id) {
            let item = AVPlayerItem(url: url)
            avPlayer = AVPlayer(playerItem: item)
        } else {
            avPlayer = AVPlayer()
        }
        avPlayer.actionAtItemEnd = .none
        configureObservers()
    }

    private func configureObservers() {
        statusObserver = avPlayer.currentItem?.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self else { return }
                if item.status == .readyToPlay {
                    self.isReady = true
                }
            }
        }

        let interval = CMTime(seconds: 1.0 / 30.0, preferredTimescale: 600)
        timeObserver = avPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            let seconds = time.seconds
            guard seconds.isFinite else { return }
            let clock = PlaybackUI.note(
                time: seconds,
                duration: self.duration,
                clip: self.clip,
                uiTime: &self.currentTime,
                line: &self.spokenLine,
                token: &self.spokenToken
            )
            self.clock = clock

            let now = Date()
            let dt = now.timeIntervalSince(self.lastTickWall)
            self.lastTickWall = now
            if self.isPlaying {
                self.watchAccumulator += max(0, dt)
                if self.watchAccumulator >= 1 {
                    self.onWatchTick?(self.watchAccumulator)
                    self.watchAccumulator = 0
                }
            }

            if let loopRange = self.loopRange, clock >= loopRange.upperBound {
                self.seek(to: loopRange.lowerBound)
                if self.isPlaying { self.avPlayer.play() }
            } else if clock >= self.duration - 0.05 {
                self.handleClipEnd()
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: avPlayer.currentItem,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleVideoEnd()
            }
        }
    }

    private func handleVideoEnd() {
        // Sample files may be shorter than seed karaoke timings — loop the visual.
        if let loopRange {
            seek(to: loopRange.lowerBound)
            if isPlaying { avPlayer.play() }
            return
        }
        if clock < duration - 0.5 {
            seek(to: 0)
            if isPlaying { avPlayer.play() }
            return
        }
        handleClipEnd()
    }

    private func handleClipEnd() {
        guard !didFinish else { return }
        didFinish = true
        isPlaying = false
        avPlayer.pause()
        if let onFinished {
            onFinished()
        } else {
            seek(to: 0)
            play()
        }
    }

    func play() {
        didFinish = false
        lastTickWall = Date()
        isPlaying = true
        avPlayer.rate = Float(rate)
        if avPlayer.rate == 0 { avPlayer.play() }
    }

    func pause() {
        isPlaying = false
        avPlayer.pause()
    }

    func seek(to time: Double) {
        PlaybackUI.jump(
            to: time,
            duration: duration,
            clip: clip,
            uiTime: &currentTime,
            line: &spokenLine,
            token: &spokenToken
        )
        clock = currentTime
        let cm = CMTime(seconds: currentTime, preferredTimescale: 600)
        avPlayer.seek(to: cm, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func setRate(_ rate: Double) {
        self.rate = rate
        if isPlaying { avPlayer.rate = Float(rate) }
    }

    func setMuted(_ muted: Bool) {
        isMuted = muted
        avPlayer.isMuted = muted
    }

    func setLoop(_ range: ClosedRange<Double>?) {
        loopRange = range
        if let range, !range.contains(clock) { seek(to: range.lowerBound) }
    }

    func teardown() {
        pause()
        if let timeObserver {
            avPlayer.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        statusObserver?.invalidate()
        statusObserver = nil
        onFinished = nil
        onWatchTick = nil
        avPlayer.replaceCurrentItem(with: nil)
    }
}

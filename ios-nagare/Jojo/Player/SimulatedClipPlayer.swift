import Foundation
import Observation
import AVFoundation

/// Default player: animated gradient poster + timer that drives the karaoke cursor.
/// Optionally narrates each line with a ja-JP voice so clips are audible without real video.
@Observable
@MainActor
final class SimulatedClipPlayer: ClipPlayer {
    let clip: Clip
    private(set) var currentTime: Double = 0
    private(set) var isPlaying = false
    private(set) var rate: Double = 1
    private(set) var isMuted = false
    private(set) var loopRange: ClosedRange<Double>?
    @ObservationIgnored var onFinished: (() -> Void)?
    @ObservationIgnored var onWatchTick: ((Double) -> Void)?

    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var lastSpokenLine: Int = -1
    @ObservationIgnored private var watchAccumulator: Double = 0
    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()

    var duration: Double { clip.durationSec }

    init(clip: Clip) {
        self.clip = clip
    }

    func play() {
        guard !isPlaying else { return }
        if currentTime >= duration - 0.05 { currentTime = 0 }
        isPlaying = true
        lastSpokenLine = -1
        startTicker()
    }

    func pause() {
        isPlaying = false
        ticker?.cancel()
        ticker = nil
        synthesizer.pauseSpeaking(at: .word)
    }

    func seek(to time: Double) {
        currentTime = min(max(0, time), duration)
        lastSpokenLine = -1
        synthesizer.stopSpeaking(at: .immediate)
    }

    func setRate(_ rate: Double) {
        self.rate = rate
    }

    func setMuted(_ muted: Bool) {
        isMuted = muted
        if muted { synthesizer.stopSpeaking(at: .immediate) }
    }

    func setLoop(_ range: ClosedRange<Double>?) {
        loopRange = range
        if let range, !range.contains(currentTime) { seek(to: range.lowerBound) }
    }

    func teardown() {
        pause()
        synthesizer.stopSpeaking(at: .immediate)
        onFinished = nil
        onWatchTick = nil
    }

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            var last = Date()
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(33))
                if Task.isCancelled { return }
                guard let self, self.isPlaying else { return }
                let now = Date()
                let dt = now.timeIntervalSince(last)
                last = now
                self.advance(by: dt)
            }
        }
    }

    private func advance(by dt: Double) {
        watchAccumulator += dt
        if watchAccumulator >= 1 {
            onWatchTick?(watchAccumulator)
            watchAccumulator = 0
        }
        var next = currentTime + dt * rate
        if let loopRange, next >= loopRange.upperBound {
            next = loopRange.lowerBound
            lastSpokenLine = -1
        }
        if next >= duration {
            currentTime = duration
            isPlaying = false
            if let onFinished {
                onFinished()
            } else {
                seek(to: 0)
                play()
            }
            return
        }
        currentTime = next
        narrateIfNeeded()
    }

    private func narrateIfNeeded() {
        guard !isMuted else { return }
        let index = clip.lineIndex(at: currentTime)
        guard index != lastSpokenLine, let line = clip.lines[safe: index],
              currentTime >= line.start, currentTime < line.start + 0.4 else { return }
        lastSpokenLine = index
        let utterance = AVSpeechUtterance(string: line.text)
        utterance.voice = AVSpeechSynthesisVoice(language: "ja-JP")
        utterance.rate = Float(0.46 * rate)
        synthesizer.stopSpeaking(at: .immediate)
        synthesizer.speak(utterance)
    }
}

import Foundation

/// Playback engine for a clip. Two implementations: `SimulatedClipPlayer` (default, no video)
/// and `YouTubeClipPlayer` (WKWebView + official IFrame Player API) for clips with real IDs.
@MainActor
protocol ClipPlayer: AnyObject {
    var clip: Clip { get }
    var currentTime: Double { get }
    var duration: Double { get }
    var isPlaying: Bool { get }
    var rate: Double { get }
    var isMuted: Bool { get }
    var loopRange: ClosedRange<Double>? { get }
    var onFinished: (() -> Void)? { get set }
    /// Called roughly once per second of real playback, with elapsed seconds.
    var onWatchTick: ((Double) -> Void)? { get set }

    func play()
    func pause()
    func seek(to time: Double)
    func setRate(_ rate: Double)
    func setMuted(_ muted: Bool)
    func setLoop(_ range: ClosedRange<Double>?)
    func teardown()
}

extension ClipPlayer {
    func togglePlay() {
        isPlaying ? pause() : play()
    }

    var currentLineIndex: Int { clip.lineIndex(at: currentTime) }

    /// Index of the token currently being spoken in the current line.
    var currentTokenIndex: Int? {
        let line = clip.lines[safe: currentLineIndex]
        guard let line, currentTime >= line.start, currentTime <= line.end + 0.2 else { return nil }
        return line.tokens.lastIndex { $0.start <= currentTime && !$0.isPunctuation }
    }

    /// Cycles 1x → 0.75x → 0.5x → 1x.
    func cycleRate() {
        switch rate {
        case 1: setRate(0.75)
        case 0.75: setRate(0.5)
        default: setRate(1)
        }
    }

    /// Toggles looping the current line.
    func toggleLoopCurrentLine() {
        if loopRange != nil {
            setLoop(nil)
        } else if let line = clip.lines[safe: currentLineIndex] {
            setLoop(max(0, line.start - 0.3)...min(duration, line.end + 0.5))
        }
    }
}

/// Builds the right player for a clip.
@MainActor
enum ClipPlayerFactory {
    static func make(for clip: Clip) -> any ClipPlayer {
        clip.hasRealVideo ? YouTubeClipPlayer(clip: clip) : SimulatedClipPlayer(clip: clip)
    }
}

extension Array {
    nonisolated subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

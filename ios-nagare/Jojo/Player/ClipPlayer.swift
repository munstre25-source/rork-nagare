import Foundation

/// Playback engine for a clip. Implementations: `LocalClipPlayer` (bundled MP4),
/// `YouTubeClipPlayer` (WKWebView IFrame API), and `SimulatedClipPlayer` (poster + TTS).
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
    /// Line under the playhead. Changes only when the line changes.
    var spokenLine: Int { get }
    /// Token under the playhead. Changes only when the spoken word changes.
    var spokenToken: Int? { get }

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

    var currentLineIndex: Int { spokenLine }

    /// Index of the token currently being spoken in the current line.
    var currentTokenIndex: Int? { spokenToken }

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

/// Publishes playhead state without notifying SwiftUI on every audio frame.
/// Not main-actor isolated: the video clock calls it from AVPlayer's time callback.
enum PlaybackUI {
    /// Updates the karaoke markers when they change, and the clock about four times a second.
    static func note(
        time: Double,
        duration: Double,
        clip: Clip,
        uiTime: inout Double,
        line: inout Int,
        token: inout Int?
    ) -> Double {
        let clock = min(max(0, time), duration)
        let nextLine = clip.lineIndex(at: clock)
        if nextLine != line { line = nextLine }
        let nextToken = tokenIndex(clip: clip, line: nextLine, time: clock)
        if nextToken != token { token = nextToken }
        if abs(clock - uiTime) >= 0.25 {
            uiTime = clock
        }
        return clock
    }

    static func jump(
        to time: Double,
        duration: Double,
        clip: Clip,
        uiTime: inout Double,
        line: inout Int,
        token: inout Int?
    ) {
        let clock = min(max(0, time), duration)
        uiTime = clock
        line = clip.lineIndex(at: clock)
        token = tokenIndex(clip: clip, line: line, time: clock)
    }

    /// Word under the playhead. Nil for sentence-timed lines: their token times are the
    /// whole line's window, so picking a word would be a guess.
    static func tokenIndex(clip: Clip, line: Int, time: Double) -> Int? {
        guard let row = clip.lines[safe: line], row.hasWordTiming,
              time >= row.start, time <= row.end + 0.2 else { return nil }
        return row.tokens.lastIndex { $0.start <= time && $0.end > $0.start && !$0.isPunctuation }
    }
}

/// Builds the right player for a clip. Bundled MP4s are preferred in every build so
/// curated offline clips remain playable without a remote embed or network connection.
@MainActor
enum ClipPlayerFactory {
    static func make(for clip: Clip, autoplaysOnLoad: Bool = true) -> any ClipPlayer {
        if clip.hasLocalVideo { return LocalClipPlayer(clip: clip) }
        if clip.hasRealVideo { return YouTubeClipPlayer(clip: clip, autoplaysOnLoad: autoplaysOnLoad) }
        return SimulatedClipPlayer(clip: clip)
    }
}

extension Array {
    nonisolated subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

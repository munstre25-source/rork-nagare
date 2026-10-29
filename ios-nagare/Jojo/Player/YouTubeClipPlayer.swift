import Foundation
import Observation
import WebKit

/// Plays real YouTube clips with the official IFrame Player API inside a WKWebView.
/// Supports seek, playback rate, loop-segment and current-time polling. Video is never re-hosted.
@Observable
@MainActor
final class YouTubeClipPlayer: NSObject, ClipPlayer, WKScriptMessageHandler {
    let clip: Clip
    private(set) var currentTime: Double = 0
    private(set) var isPlaying = false
    private(set) var rate: Double = 1
    private(set) var isMuted = false
    private(set) var loopRange: ClosedRange<Double>?
    private(set) var isReady = false
    /// True after the IFrame API reports an embed/playability error.
    private(set) var embedFailed = false
    private(set) var spokenLine: Int = 0
    private(set) var spokenToken: Int?
    @ObservationIgnored var onFinished: (() -> Void)?
    @ObservationIgnored var onWatchTick: ((Double) -> Void)?

    @ObservationIgnored private var poller: Task<Void, Never>?
    @ObservationIgnored private var wantsPlay = false
    @ObservationIgnored private var watchAccumulator: Double = 0
    @ObservationIgnored private var didFinish = false
    @ObservationIgnored private var didRetryNocookie = false
    @ObservationIgnored private var clock: Double = 0
    @ObservationIgnored private(set) lazy var webView: WKWebView = makeWebView()

    private static let pollMilliseconds = 120

    var duration: Double { clip.durationSec }
    private var sourceStart: Double { clip.sourceStartSec ?? 0 }

    init(clip: Clip) {
        self.clip = clip
        super.init()
    }

    private func makeWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsPictureInPictureMediaPlayback = false
        if #available(iOS 15.4, *) {
            config.preferences.isElementFullscreenEnabled = false
        }
        config.userContentController.add(WeakMessageHandler(self), name: "yt")
        let view = WKWebView(frame: .zero, configuration: config)
        view.isOpaque = false
        view.backgroundColor = .black
        view.scrollView.isScrollEnabled = false
        view.scrollView.contentInsetAdjustmentBehavior = .never
        // Mute-first autoplay is required on iOS WKWebView; we unmute after play starts if desired.
        loadPlayerHTML(in: view, host: "https://www.youtube.com")
        return view
    }

    /// Loads the player wrapper from the project's own https origin (an edge function). The
    /// page's real, verifiable referrer is what YouTube's embed rules require — a synthetic
    /// `https://<bundle id>` origin now fails with errors 150 / 152 / 153.
    private func loadPlayerHTML(in view: WKWebView, host: String) {
        var components = URLComponents(string: "\(Secrets.supabaseURL)/functions/v1/youtube-embed")!
        components.queryItems = [URLQueryItem(name: "v", value: clip.videoId)]
        if host.contains("nocookie") { components.queryItems?.append(URLQueryItem(name: "h", value: "nocookie")) }
        guard let url = components.url else {
            embedFailed = true
            return
        }
        view.load(URLRequest(url: url))
    }

    func play() {
        wantsPlay = true
        didFinish = false
        isPlaying = true
        // Start muted so iOS allows autoplay; unmute once playback actually begins if desired.
        run("player&&player.mute();player&&player.playVideo()")
        startPolling()
    }

    func pause() {
        wantsPlay = false
        isPlaying = false
        run("player&&player.pauseVideo()")
        poller?.cancel()
        poller = nil
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
        run("player&&player.seekTo(\(sourceStart + currentTime),true)")
    }

    func setRate(_ rate: Double) {
        self.rate = rate
        run("player&&player.setPlaybackRate(\(rate))")
    }

    func setMuted(_ muted: Bool) {
        isMuted = muted
        run(muted ? "player&&player.mute()" : "player&&player.unMute()")
    }

    func setLoop(_ range: ClosedRange<Double>?) {
        loopRange = range
        if let range, !range.contains(clock) { seek(to: range.lowerBound) }
    }

    func teardown() {
        pause()
        onFinished = nil
        onWatchTick = nil
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "yt")
    }

    private func run(_ js: String) {
        guard isReady else { return }
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    private func startPolling() {
        poller?.cancel()
        poller = Task { [weak self] in
            while !Task.isCancelled {
                // ~8 Hz keeps the word cursor within a syllable of the audio.
                try? await Task.sleep(for: .milliseconds(Self.pollMilliseconds))
                guard let self else { return }
                self.webView.evaluateJavaScript("nTime()", completionHandler: nil)
                if self.isPlaying {
                    self.watchAccumulator += Double(Self.pollMilliseconds) / 1000
                    if self.watchAccumulator >= 1 {
                        self.onWatchTick?(self.watchAccumulator)
                        self.watchAccumulator = 0
                    }
                }
            }
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let event = body["e"] as? String else { return }
        let value = body["v"]
        let number = (value as? Double) ?? (value as? Int).map(Double.init)
        handle(event: event, value: number)
    }

    private func handle(event: String, value: Double?) {
        switch event {
        case "ready":
            isReady = true
            embedFailed = false
            setRate(rate)
            // Keep muted until we confirm playing, then apply user mute preference.
            run("player&&player.mute()")
            run("player&&player.seekTo(\(sourceStart + currentTime),true)")
            if wantsPlay { play() }
        case "time":
            guard let value else { return }
            let excerptTime = value - sourceStart
            let clock = PlaybackUI.note(
                time: excerptTime,
                duration: duration,
                clip: clip,
                uiTime: &currentTime,
                line: &spokenLine,
                token: &spokenToken
            )
            self.clock = clock
            if let loopRange, clock >= loopRange.upperBound {
                seek(to: loopRange.lowerBound)
            } else if clock >= duration - 0.1, !didFinish, loopRange == nil {
                finish()
            }
        case "state":
            // 0 ended, 1 playing, 2 paused
            if value == 0, !didFinish { finish() }
            if value == 1 {
                isPlaying = true
                if !isMuted { run("player&&player.unMute()") }
            }
        case "error":
            print("[YouTube] player error \(value.map { String(Int($0)) } ?? "?") for \(clip.videoId)")
            // One retry via youtube-nocookie host — helps some embedder-identity failures.
            if !didRetryNocookie {
                didRetryNocookie = true
                embedFailed = false
                isReady = false
                loadPlayerHTML(in: webView, host: "https://www.youtube-nocookie.com")
            } else {
                embedFailed = true
                isPlaying = false
            }
        default:
            break
        }
    }

    private func finish() {
        didFinish = true
        if let onFinished {
            pause()
            onFinished()
        } else {
            seek(to: loopRange?.lowerBound ?? 0)
            play()
        }
    }
}

/// Breaks the WKUserContentController → handler retain cycle.
private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: (any WKScriptMessageHandler)?

    init(_ target: any WKScriptMessageHandler) {
        self.target = target
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}

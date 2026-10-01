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
    @ObservationIgnored var onFinished: (() -> Void)?
    @ObservationIgnored var onWatchTick: ((Double) -> Void)?

    @ObservationIgnored private var poller: Task<Void, Never>?
    @ObservationIgnored private var wantsPlay = false
    @ObservationIgnored private var watchAccumulator: Double = 0
    @ObservationIgnored private var didFinish = false
    @ObservationIgnored private(set) lazy var webView: WKWebView = makeWebView()

    var duration: Double { clip.durationSec }

    init(clip: Clip) {
        self.clip = clip
        super.init()
    }

    private func makeWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.userContentController.add(WeakMessageHandler(self), name: "yt")
        let view = WKWebView(frame: .zero, configuration: config)
        view.isOpaque = false
        view.backgroundColor = .black
        view.scrollView.isScrollEnabled = false
        view.loadHTMLString(html, baseURL: URL(string: "https://www.youtube.com"))
        return view
    }

    private var html: String {
        // `origin` + `widget_referrer` + a real youtube.com baseURL are required to avoid
        // Error 152-4 ("embedder identity") in WKWebView / simulators.
        let origin = "https://www.youtube.com"
        return """
        <!DOCTYPE html><html><head>
        <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1">
        <meta name="referrer" content="strict-origin-when-cross-origin">
        <style>html,body{margin:0;padding:0;background:#000;height:100%;overflow:hidden}#p{position:absolute;inset:0;width:100%;height:100%}</style>
        </head><body><div id="p"></div>
        <script src="https://www.youtube.com/iframe_api"></script>
        <script>
        var player;
        function post(m){window.webkit.messageHandlers.yt.postMessage(m);}
        function onYouTubeIframeAPIReady(){
          player=new YT.Player('p',{
            host:'https://www.youtube.com',
            videoId:'\(clip.videoId)',
            playerVars:{
              playsinline:1,controls:0,rel:0,modestbranding:1,fs:0,
              iv_load_policy:3,cc_load_policy:0,enablejsapi:1,
              origin:'\(origin)',widget_referrer:'\(origin)'
            },
            events:{
              onReady:function(){post({e:'ready'});},
              onStateChange:function(ev){post({e:'state',v:ev.data});},
              onError:function(ev){post({e:'error',v:ev.data});}
            }
          });
        }
        function nTime(){ if(player&&player.getCurrentTime){post({e:'time',v:player.getCurrentTime()});} }
        </script></body></html>
        """
    }

    func play() {
        wantsPlay = true
        didFinish = false
        isPlaying = true
        run("player&&player.playVideo()")
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
        currentTime = min(max(0, time), duration)
        run("player&&player.seekTo(\(currentTime),true)")
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
        if let range, !range.contains(currentTime) { seek(to: range.lowerBound) }
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
                try? await Task.sleep(for: .milliseconds(150))
                guard let self else { return }
                self.webView.evaluateJavaScript("nTime()", completionHandler: nil)
                if self.isPlaying {
                    self.watchAccumulator += 0.15
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
            setRate(rate)
            setMuted(isMuted)
            if currentTime > 0 { seek(to: currentTime) }
            if wantsPlay { play() }
        case "time":
            guard let value else { return }
            currentTime = value
            if let loopRange, value >= loopRange.upperBound {
                seek(to: loopRange.lowerBound)
            } else if value >= duration - 0.1, !didFinish, loopRange == nil {
                finish()
            }
        case "state":
            // 0 ended, 1 playing, 2 paused
            if value == 0, !didFinish { finish() }
            if value == 1 { isPlaying = true }
        case "error":
            // Surface embed failures (e.g. 152) in logs so simulator issues are obvious.
            print("[YouTube] player error \(value.map { String(Int($0)) } ?? "?") for \(clip.videoId)")
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

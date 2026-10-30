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
    /// The last IFrame player error code (2, 5, 100, 101, 150…), for on-screen diagnostics.
    private(set) var embedErrorCode: Int?
    private(set) var spokenLine: Int = 0
    private(set) var spokenToken: Int?
    @ObservationIgnored var onFinished: (() -> Void)?
    @ObservationIgnored var onWatchTick: ((Double) -> Void)?

    @ObservationIgnored private var poller: Task<Void, Never>?
    @ObservationIgnored private var wantsPlay = false
    @ObservationIgnored private var watchAccumulator: Double = 0
    @ObservationIgnored private var didFinish = false
    @ObservationIgnored private var clock: Double = 0
    @ObservationIgnored private var apiLoaded = false
    @ObservationIgnored private var loadWatchdog: Task<Void, Never>?
    @ObservationIgnored private var lastReportedTime: Double = -1
    @ObservationIgnored private var lastProgressAt = Date()
    @ObservationIgnored private(set) lazy var webView: WKWebView = makeWebView()

    private static let pollMilliseconds = 120
    /// How long a video may take to become ready once YouTube's API script has loaded.
    private static let readyTimeout: Duration = .seconds(15)
    /// How long playback may sit at the same time after play was requested.
    private static let stallTimeout: TimeInterval = 15

    /// How the player page is loaded. Some devices (notably certain iOS 26 WebKit builds) reject
    /// the local-HTML embed with error 150 for every video while others play it fine, so on error
    /// we walk down this ladder of loading strategies — each fixes a different known failure:
    /// 1. RMF "local HTML" pattern: bundle-ID baseURL identifies the app.
    /// 2. youtube-nocookie iframe host: some embedder-identity failures.
    /// 3. youtube-nocookie baseURL: the fix reported for device-only error 150.
    /// 4. Direct navigation to the embed URL with an explicit Referer header (RMF pattern 2):
    ///    immune to WebKit dropping the Referer on cross-origin iframe requests.
    private enum EmbedLoad: Equatable {
        case iframeAPI(host: String, baseURL: String)
        case directEmbed
    }

    private static var embedLadder: [EmbedLoad] {
        [
            .iframeAPI(host: "https://www.youtube.com", baseURL: appReferrer),
            .iframeAPI(host: "https://www.youtube-nocookie.com", baseURL: appReferrer),
            .iframeAPI(host: "https://www.youtube-nocookie.com", baseURL: "https://www.youtube-nocookie.com/"),
            .directEmbed,
        ]
    }

    @ObservationIgnored private var loadAttempt = 0
    @ObservationIgnored private var loadMode: EmbedLoad = .iframeAPI(host: "https://www.youtube.com", baseURL: "")
    @ObservationIgnored private var didInstallDirectBridge = false

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
        loadEmbed(in: view)
        return view
    }

    /// YouTube's Required Minimum Functionality for iOS WebViews: load the player page with
    /// `loadHTMLString(_:baseURL:)` where baseURL is `https://<bundle id>` (lowercased). That
    /// becomes the HTTP Referer YouTube uses to identify the app (avoids errors 152/153).
    /// (A page served from a Supabase edge function does not work: Supabase rewrites HTML
    /// responses to text/plain with a sandbox CSP.)
    private static var appReferrer: String {
        "https://\((Bundle.main.bundleIdentifier ?? "com.socialreporthq.jojo").lowercased())"
    }

    private func loadEmbed(in view: WKWebView) {
        let videoId = clip.videoId.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        guard !videoId.isEmpty else {
            embedFailed = true
            return
        }
        apiLoaded = false
        isReady = false
        embedErrorCode = nil
        let attempt = Self.embedLadder[min(loadAttempt, Self.embedLadder.count - 1)]
        loadMode = attempt
        switch attempt {
        case .iframeAPI(let host, let baseURL):
            guard let base = URL(string: baseURL) else {
                embedFailed = true
                return
            }
            view.loadHTMLString(Self.playerHTML(videoId: videoId, host: host, origin: Self.appReferrer), baseURL: base)
        case .directEmbed:
            installDirectBridge()
            // No `origin` param here: the embed page is the top-level document, so a foreign
            // origin would make its postMessage handshake drop every event.
            var components = URLComponents(string: "https://www.youtube.com/embed/\(videoId)")!
            components.queryItems = [
                URLQueryItem(name: "enablejsapi", value: "1"),
                URLQueryItem(name: "playsinline", value: "1"),
                URLQueryItem(name: "autoplay", value: "1"),
                URLQueryItem(name: "mute", value: "1"),
                URLQueryItem(name: "controls", value: "0"),
                URLQueryItem(name: "rel", value: "0"),
                URLQueryItem(name: "modestbranding", value: "1"),
                URLQueryItem(name: "iv_load_policy", value: "3"),
                URLQueryItem(name: "cc_load_policy", value: "0"),
                URLQueryItem(name: "widget_referrer", value: Self.appReferrer),
            ]
            var request = URLRequest(url: components.url!)
            request.setValue(Self.appReferrer, forHTTPHeaderField: "Referer")
            view.load(request)
            // The embed page is YouTube's own player; if it loads at all, the network is fine.
            apiLoaded = true
        }
        startLoadWatchdog()
    }

    /// JS bridge for `.directEmbed`: a user script inside the embed page relays player events to
    /// us and exposes commands through `window.__nagareCmd` (the postMessage player protocol).
    private func installDirectBridge() {
        guard !didInstallDirectBridge else { return }
        didInstallDirectBridge = true
        let source = """
        (function(){
          if (location.pathname.indexOf('/embed/') !== 0) return;
          if (window.__nagare) return; window.__nagare = true;
          function send(m){ try { window.webkit.messageHandlers.yt.postMessage(m); } catch(e) {} }
          function cmd(func, args){
            var msg = {event:'command', func:func, args:args||[]};
            try { window.postMessage(JSON.stringify(msg), '*'); } catch(e) {}
            try { window.postMessage(msg, '*'); } catch(e) {}
          }
          window.__nagareCmd = cmd;
          window.addEventListener('message', function(ev){
            var d = ev.data;
            if (typeof d === 'string') { try { d = JSON.parse(d); } catch(e) { return; } }
            if (!d || typeof d !== 'object') return;
            if (d.event === 'listening' || d.event === 'onReady') { send({e:'ready'}); }
            else if (d.event === 'onStateChange') { send({e:'state', v:d.info}); }
            else if (d.event === 'onError') { send({e:'error', v:d.info}); }
            else if (d.event === 'infoDelivery' && d.info && typeof d.info.currentTime === 'number') {
              send({e:'time', v:d.info.currentTime});
            }
          });
          function announce(){ send({e:'ready'}); }
          if (document.readyState === 'complete') announce();
          else window.addEventListener('load', announce);
          setTimeout(announce, 3000);
          setInterval(function(){ cmd('getCurrentTime'); }, 250);
        })();
        """
        let script = WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        webView.configuration.userContentController.addUserScript(script)
    }

    /// Executes a player command in whichever load mode is active.
    private func runCommand(_ function: String, _ args: String = "") {
        guard isReady else { return }
        let js: String
        switch loadMode {
        case .iframeAPI:
            js = "player&&player.\(function)(\(args))"
        case .directEmbed:
            js = "window.__nagareCmd&&window.__nagareCmd('\(function)',[\(args)])"
        }
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    private func pollTime() {
        switch loadMode {
        case .iframeAPI:
            webView.evaluateJavaScript("nTime()", completionHandler: nil)
        case .directEmbed:
            break // the bridge streams time via infoDelivery
        }
    }

    /// A player that never becomes ready shows an endless spinner. If YouTube's API loaded
    /// but this video didn't, the video is the problem (report it). If the API itself never
    /// loaded, it's the network: fail quietly so the learner can skip, but don't blame the clip.
    private func startLoadWatchdog() {
        loadWatchdog?.cancel()
        loadWatchdog = Task { [weak self] in
            try? await Task.sleep(for: Self.readyTimeout)
            guard !Task.isCancelled, let self, !self.isReady, !self.embedFailed else { return }
            if self.apiLoaded {
                self.fail(code: PlaybackHealth.neverReadyCode)
            } else {
                self.embedFailed = true
                self.isPlaying = false
            }
        }
    }

    /// Terminal failure: stop, surface the code, and tell PlaybackHealth (which hides the clip
    /// on definitive codes and reports it so the catalog retires it for everyone).
    private func fail(code: Int) {
        loadWatchdog?.cancel()
        poller?.cancel()
        poller = nil
        wantsPlay = false
        isPlaying = false
        embedErrorCode = code
        embedFailed = true
        // 152/153 are app-identity errors that would hit every video; never blame a clip for them.
        if PlaybackHealth.definitiveCodes.contains(code) || code < 0 {
            PlaybackHealth.recordFailure(clip: clip, code: code)
        }
    }

    private static func playerHTML(videoId: String, host: String, origin: String) -> String {
        """
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
          post({e:'api'});
          player=new YT.Player('p',{
            host:'\(host)',
            videoId:'\(videoId)',
            playerVars:{
              playsinline:1,controls:0,rel:0,modestbranding:1,fs:0,
              iv_load_policy:3,cc_load_policy:0,enablejsapi:1,autoplay:1,mute:1,
              origin:'\(origin)',widget_referrer:'\(origin)'
            },
            events:{
              onReady:function(){post({e:'ready'});},
              onStateChange:function(ev){post({e:'state',v:ev.data});},
              onError:function(ev){post({e:'error',v:ev.data});}
            }
          });
          var f=document.querySelector('iframe'); if(f){f.setAttribute('referrerpolicy','strict-origin-when-cross-origin');}
        }
        function nTime(){ if(player&&player.getCurrentTime){post({e:'time',v:player.getCurrentTime()});} }
        </script></body></html>
        """
    }

    func play() {
        guard !embedFailed else { return }
        wantsPlay = true
        didFinish = false
        isPlaying = true
        lastProgressAt = Date()
        // Start muted so iOS allows autoplay; unmute once playback actually begins if desired.
        runCommand("mute")
        runCommand("playVideo")
        startPolling()
    }

    func pause() {
        wantsPlay = false
        isPlaying = false
        runCommand("pauseVideo")
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
        runCommand("seekTo", "\(sourceStart + currentTime),true")
    }

    func setRate(_ rate: Double) {
        self.rate = rate
        runCommand("setPlaybackRate", "\(rate)")
    }

    func setMuted(_ muted: Bool) {
        isMuted = muted
        runCommand(muted ? "mute" : "unMute")
    }

    func setLoop(_ range: ClosedRange<Double>?) {
        loopRange = range
        if let range, !range.contains(clock) { seek(to: range.lowerBound) }
    }

    func teardown() {
        loadWatchdog?.cancel()
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
            var lastTick = Date()
            while !Task.isCancelled {
                // ~8 Hz keeps the word cursor within a syllable of the audio.
                try? await Task.sleep(for: .milliseconds(Self.pollMilliseconds))
                guard let self else { return }
                // A long gap means the app was suspended, not that the video stalled.
                if Date().timeIntervalSince(lastTick) > 2 { self.lastProgressAt = Date() }
                lastTick = Date()
                pollTime()
                // Ready and asked to play, but time hasn't moved: a stalled video.
                if self.isReady, self.wantsPlay, !self.embedFailed,
                   Date().timeIntervalSince(self.lastProgressAt) > Self.stallTimeout {
                    self.fail(code: PlaybackHealth.stalledCode)
                    return
                }
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
        case "api":
            apiLoaded = true
        case "ready":
            loadWatchdog?.cancel()
            lastProgressAt = Date()
            isReady = true
            embedFailed = false
            embedErrorCode = nil
            setRate(rate)
            // Keep muted until we confirm playing, then apply user mute preference.
            runCommand("mute")
            runCommand("seekTo", "\(sourceStart + currentTime),true")
            if wantsPlay { play() }
        case "time":
            guard let value else { return }
            if abs(value - lastReportedTime) > 0.05 {
                lastReportedTime = value
                lastProgressAt = Date()
                if isReady { PlaybackHealth.noteSuccessfulPlayback() }
            }
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
                if !isMuted { runCommand("unMute") }
            }
        case "error":
            let code = value.map { Int($0) } ?? 0
            print("[YouTube] player error \(code) for \(clip.videoId) (attempt \(loadAttempt + 1)/\(Self.embedLadder.count))")
            if code == 100 {
                // Removed video: definitive regardless of the embedder, no retry.
                fail(code: code)
            } else if loadAttempt + 1 < Self.embedLadder.count {
                // 101/150 can be embedder-identity or WebKit quirks, not the video: try the
                // next loading strategy before blaming the clip.
                loadAttempt += 1
                embedFailed = false
                isReady = false
                didFinish = false
                loadEmbed(in: webView)
            } else {
                fail(code: code)
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

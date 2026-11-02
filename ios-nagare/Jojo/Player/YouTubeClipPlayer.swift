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
    /// True only once YouTube has actually rendered moving frames (state 1 or advancing time).
    /// Until then the web view stays invisible, so YouTube's own pages — the bot check,
    /// "Sign in", error slates — are never shown inside Jojo.
    private(set) var hasRenderedVideo = false
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
    @ObservationIgnored private var currentWebView: WKWebView?
    /// The YouTubeSession generation the current web view was built in. Observed: the host
    /// view keys on it, so a rebuilt web view (fresh visitor session) is attached at once.
    private(set) var sessionGeneration = -1
    var webView: WKWebView {
        if let currentWebView { return currentWebView }
        let view = makeWebView()
        currentWebView = view
        loadEmbed(in: view)
        return view
    }
    @ObservationIgnored private var autoRetryTask: Task<Void, Never>?
    @ObservationIgnored private var autoRetries = 0
    @ObservationIgnored private var ladderTask: Task<Void, Never>?
    /// Prewarmed (next-clip) players load without autoplaying: two simultaneous playback
    /// sessions from one embedder look abusive to YouTube and can trigger error 150 storms.
    @ObservationIgnored private var autoplaysOnLoad = true

    private static let pollMilliseconds = 120
    /// How long a video may take to become ready once YouTube's API script has loaded.
    private static let readyTimeout: Duration = .seconds(15)
    /// Retries get a shorter leash so a failing device shows the failure card quickly
    /// instead of a long silent wait between strategies.
    private static let retryReadyTimeout: Duration = .seconds(8)
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

    init(clip: Clip, autoplaysOnLoad: Bool = true) {
        self.clip = clip
        self.autoplaysOnLoad = autoplaysOnLoad
        super.init()
        sessionGeneration = YouTubeSession.shared.generation
    }

    private func makeWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsPictureInPictureMediaPlayback = false
        // Present as Mobile Safari (same engine). A bare WKWebView UA gets YouTube's stricter
        // bot screening; the app is still identified to YouTube by the Referer (RMF).
        config.applicationNameForUserAgent = "Version/26.0 Mobile/15E148 Safari/604.1"
        if #available(iOS 15.4, *) {
            config.preferences.isElementFullscreenEnabled = false
        }
        config.userContentController.add(WeakMessageHandler(self), name: "yt")
        // In-memory cookie jar shared by all embeds; see YouTubeSession for why.
        YouTubeSession.shared.purgeLegacyStoreOnce()
        config.websiteDataStore = YouTubeSession.shared.store
        if sessionGeneration != YouTubeSession.shared.generation { sessionGeneration = YouTubeSession.shared.generation }
        didInstallDirectBridge = false
        let view = WKWebView(frame: .zero, configuration: config)
        view.isOpaque = false
        view.backgroundColor = .black
        view.scrollView.isScrollEnabled = false
        view.scrollView.contentInsetAdjustmentBehavior = .never
        // Mute-first autoplay is required on iOS WKWebView; we unmute after play starts if desired.
        return view
    }

    /// Restarts loading from the first ladder strategy. If the shared YouTube session was
    /// reset since this web view was built, the web view is rebuilt in the fresh session —
    /// a web view's cookie jar is fixed at creation.
    private func reloadFromStart() {
        loadWatchdog?.cancel()
        loadAttempt = 0
        embedFailed = false
        embedErrorCode = nil
        isReady = false
        hasRenderedVideo = false
        didFinish = false
        lastProgressAt = Date()
        if let old = currentWebView, sessionGeneration != YouTubeSession.shared.generation {
            old.stopLoading()
            old.configuration.userContentController.removeScriptMessageHandler(forName: "yt")
            old.removeFromSuperview()
            currentWebView = nil
            _ = webView // builds in the new session and loads
        } else {
            loadEmbed(in: webView)
        }
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
        hasRenderedVideo = false
        embedErrorCode = nil
        let attempt = Self.embedLadder[min(loadAttempt, Self.embedLadder.count - 1)]
        loadMode = attempt
        switch attempt {
        case .iframeAPI(let host, let baseURL):
            guard let base = URL(string: baseURL) else {
                embedFailed = true
                return
            }
            view.loadHTMLString(Self.playerHTML(videoId: videoId, host: host, origin: Self.appReferrer, autoplay: autoplaysOnLoad), baseURL: base)
        case .directEmbed:
            installDirectBridge(in: view)
            // No `origin` param here: the embed page is the top-level document, so a foreign
            // origin would make its postMessage handshake drop every event.
            var components = URLComponents(string: "https://www.youtube.com/embed/\(videoId)")!
            components.queryItems = [
                URLQueryItem(name: "enablejsapi", value: "1"),
                URLQueryItem(name: "playsinline", value: "1"),
                URLQueryItem(name: "autoplay", value: autoplaysOnLoad ? "1" : "0"),
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
    private func installDirectBridge(in view: WKWebView) {
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
          // NOTE: no announce-on-load here. A dead embed page (bot check, consent wall,
          // blocked autoplay) must never report ready — that would flip the player to
          // full opacity and show the learner a blank black frame for the whole stall
          // window. Ready is only the 'listening'/'onReady' handshake above, which means
          // YouTube's player is genuinely alive.
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
          setInterval(function(){ cmd('getCurrentTime'); }, 250);
        })();
        """
        let script = WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        view.configuration.userContentController.addUserScript(script)
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
        let timeout: Duration = loadAttempt == 0 ? Self.readyTimeout : Self.retryReadyTimeout
        loadWatchdog = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled, let self, !self.isReady, !self.embedFailed else { return }
            if self.apiLoaded {
                self.fail(code: PlaybackHealth.neverReadyCode)
            } else {
                self.embedFailed = true
                self.isPlaying = false
            }
        }
    }

    /// Manual "Try again": restarts the loading ladder from the first strategy.
    func retry() {
        reloadFromStart()
    }

    /// Failure of this load attempt: stop, surface the code, tell PlaybackHealth (which
    /// gates on environment health before blocking/reporting) — then self-heal. A fresh
    /// embed session shortly after fixes the transient 150s and never-ready sessions that
    /// plague iOS 26.x WebKit, so the learner sees the poster for ~20s instead of a dead
    /// failure card. Only code 100 (video removed) never retries.
    private func fail(code: Int) {
        loadWatchdog?.cancel()
        poller?.cancel()
        poller = nil
        let resumeOnRetry = wantsPlay
        wantsPlay = false
        isPlaying = false
        embedErrorCode = code
        embedFailed = true
        let limited = YouTubeSession.shared.isLimited
        // 152/153 are app-identity errors that would hit every video; never blame a clip for them.
        // Nor while the whole network is limited: then no video is at fault.
        if !limited, PlaybackHealth.definitiveCodes.contains(code) || code < 0 {
            PlaybackHealth.recordFailure(clip: clip, code: code)
        }
        if limited, code != 100 {
            // One slow probe on the clip on screen; the first frame that plays lifts the limit.
            autoRetryTask?.cancel()
            autoRetryTask = Task { [weak self] in
                try? await Task.sleep(for: YouTubeSession.probeInterval)
                guard let self, !Task.isCancelled, self.embedFailed else { return }
                self.wantsPlay = resumeOnRetry
                if resumeOnRetry { self.isPlaying = true }
                self.reloadFromStart()
                if resumeOnRetry { self.startPolling() }
            }
            return
        }
        guard code != 100, autoRetries < 2 else { return }
        autoRetryTask?.cancel()
        autoRetryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(20))
            guard let self, !Task.isCancelled, self.embedFailed else { return }
            self.autoRetries += 1
            self.wantsPlay = resumeOnRetry
            if resumeOnRetry { self.isPlaying = true }
            self.reloadFromStart()
            if resumeOnRetry { self.startPolling() }
        }
    }

    private static func playerHTML(videoId: String, host: String, origin: String, autoplay: Bool) -> String {
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
        function hideSourceCaptions(){try{if(player&&player.getOptions&&player.unloadModule&&player.getOptions().indexOf('captions')>=0){player.unloadModule('captions');}}catch(e){}}
        function onYouTubeIframeAPIReady(){
          post({e:'api'});
          player=new YT.Player('p',{
            host:'\(host)',
            videoId:'\(videoId)',
            playerVars:{
              playsinline:1,controls:0,rel:0,modestbranding:1,fs:0,
              iv_load_policy:3,cc_load_policy:0,enablejsapi:1,autoplay:\(autoplay ? 1 : 0),mute:1,
              origin:'\(origin)',widget_referrer:'\(origin)'
            },
            events:{
              onReady:function(){hideSourceCaptions();post({e:'ready'});},
              onStateChange:function(ev){hideSourceCaptions();post({e:'state',v:ev.data});},
              onApiChange:function(){hideSourceCaptions();},
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
        // A seek can jump the reported clock without decoding a single frame.
        lastReportedTime = -1
        lastProgressAt = Date()
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
        autoRetryTask?.cancel()
        ladderTask?.cancel()
        pause()
        onFinished = nil
        onWatchTick = nil
        currentWebView?.configuration.userContentController.removeScriptMessageHandler(forName: "yt")
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
                if self.isPlaying, self.hasRenderedVideo,
                   Date().timeIntervalSince(self.lastProgressAt) < 1 {
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
            lastReportedTime = -1
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
            // The initial seek and buffering updates can change currentTime while the
            // picture is frozen. Only continuous forward movement confirms playback.
            let advanced = wantsPlay && lastReportedTime >= 0 &&
                value > lastReportedTime + 0.05 && value - lastReportedTime < 2
            lastReportedTime = value
            if advanced {
                lastProgressAt = Date()
                if isReady && !hasRenderedVideo {
                    hasRenderedVideo = true
                    YouTubeSession.shared.noteSuccess()
                    PlaybackHealth.noteSuccessfulPlayback()
                }
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
            // 0 ended, 1 playing, 2 paused, 3 buffering.
            if value == 0, !didFinish { finish() }
            if value == 1 {
                isPlaying = true
                if !isMuted { runCommand("unMute") }
            } else if value == 2 || value == 3 {
                isPlaying = false
            }
        case "error":
            let code = value.map { Int($0) } ?? 0
            print("[YouTube] player error \(code) for \(clip.videoId) (attempt \(loadAttempt + 1)/\(Self.embedLadder.count))")
            // "ready" often fires before the error; the player is not usable, so hide it
            // again and let the ladder advance (it used to stall on a stale isReady).
            isReady = false
            hasRenderedVideo = false
            let failedAttempt = loadAttempt
            if code == 101 || code == 150 {
                YouTubeSession.shared.noteRefusal(videoId: clip.videoId)
            }
            if code == 100 {
                // Removed video: definitive regardless of the embedder, no retry.
                fail(code: code)
            } else if YouTubeSession.shared.isLimited {
                // YouTube is refusing this network. Walking the ladder would only fire more
                // embeds at it and prolong the block; fail quietly and probe slowly instead.
                ladderTask?.cancel()
                fail(code: code)
            } else if sessionGeneration != YouTubeSession.shared.generation
                        || (loadAttempt == 0 && YouTubeSession.shared.resetIfFlagged()) {
                // 150/101 storms are YouTube flagging the visitor session, not the videos
                // (2026-10-30). Retry this clip at once as a brand-new visitor.
                ladderTask?.cancel()
                ladderTask = Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(250))
                    guard let self, !Task.isCancelled else { return }
                    self.reloadFromStart()
                }
            } else if loadAttempt + 1 < Self.embedLadder.count {
                // 101/150 can be embedder-identity or WebKit quirks, not the video: try the
                // next loading strategy before blaming the clip. Pacing matters — reloading
                // embeds in a burst looks abusive to YouTube and deepens any block.
                ladderTask?.cancel()
                ladderTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(2))
                    guard let self, !Task.isCancelled, self.loadAttempt == failedAttempt, !self.isReady else { return }
                    self.loadAttempt += 1
                    self.embedFailed = false
                    self.isReady = false
                    self.didFinish = false
                    self.loadWatchdog?.cancel()
                    if self.sessionGeneration != YouTubeSession.shared.generation {
                        self.reloadFromStart()
                    } else {
                        self.loadEmbed(in: self.webView)
                    }
                }
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

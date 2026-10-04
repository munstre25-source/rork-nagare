import SwiftUI
import UIKit
import WebKit

/// Hosts a `YouTubeClipPlayer`'s web view. The container re-attaches the web view whenever it
/// returns to a window, so the same player can move between the feed and fullscreen.
struct YouTubePlayerView: UIViewRepresentable {
    let player: YouTubeClipPlayer

    func makeUIView(context: Context) -> YouTubeContainerView {
        let view = YouTubeContainerView()
        view.webView = player.webView
        return view
    }

    func updateUIView(_ uiView: YouTubeContainerView, context: Context) {
        uiView.webView = player.webView
        uiView.attachIfNeeded()
    }
}

final class YouTubeContainerView: UIView {
    var webView: WKWebView?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        attachIfNeeded()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        attachIfNeeded()
        webView?.frame = bounds
    }

    func attachIfNeeded() {
        guard window != nil, let webView, webView.superview !== self else { return }
        webView.removeFromSuperview()
        webView.frame = bounds
        webView.isUserInteractionEnabled = false
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(webView)
    }
}

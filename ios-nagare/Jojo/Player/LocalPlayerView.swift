import SwiftUI
import AVFoundation
import UIKit

/// Hosts a `LocalClipPlayer`'s AVPlayerLayer. Re-attaches when the view returns to a window.
struct LocalPlayerView: UIViewRepresentable {
    let player: LocalClipPlayer
    /// `.resizeAspect` shows the whole frame. `.resizeAspectFill` crops to the box.
    var gravity: AVLayerVideoGravity = .resizeAspectFill

    func makeUIView(context: Context) -> LocalPlayerContainerView {
        let view = LocalPlayerContainerView()
        view.gravity = gravity
        view.player = player.avPlayer
        return view
    }

    func updateUIView(_ uiView: LocalPlayerContainerView, context: Context) {
        uiView.gravity = gravity
        uiView.player = player.avPlayer
    }
}

final class LocalPlayerContainerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    var gravity: AVLayerVideoGravity = .resizeAspectFill {
        didSet { playerLayer.videoGravity = gravity }
    }

    var player: AVPlayer? {
        get { playerLayer.player }
        set {
            playerLayer.player = newValue
            playerLayer.videoGravity = gravity
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        layer.masksToBounds = true
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        layer.masksToBounds = true
    }
}

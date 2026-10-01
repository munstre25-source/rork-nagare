import SwiftUI
import AVFoundation
import UIKit

/// Hosts a `LocalClipPlayer`'s AVPlayerLayer. Re-attaches when the view returns to a window.
struct LocalPlayerView: UIViewRepresentable {
    let player: LocalClipPlayer

    func makeUIView(context: Context) -> LocalPlayerContainerView {
        let view = LocalPlayerContainerView()
        view.player = player.avPlayer
        return view
    }

    func updateUIView(_ uiView: LocalPlayerContainerView, context: Context) {
        uiView.player = player.avPlayer
    }
}

final class LocalPlayerContainerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    var player: AVPlayer? {
        get { playerLayer.player }
        set {
            playerLayer.player = newValue
            playerLayer.videoGravity = .resizeAspectFill
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
}

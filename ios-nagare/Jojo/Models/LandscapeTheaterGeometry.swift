import Foundation

/// Safe-area-relative placement for a complete landscape picture with a separate karaoke panel.
nonisolated struct LandscapeTheaterGeometry {
    let videoSize: CGSize
    let videoTop: CGFloat
    let captionHeight: CGFloat
    let controlsHeight: CGFloat
    static let spacing: CGFloat = 6

    static func make(in size: CGSize, preferredCaptionHeight: CGFloat, controlsHeight: CGFloat) -> Self {
        let height = max(0, size.height)
        let captions = min(max(0, preferredCaptionHeight), height * 0.32)
        let controls = max(0, controlsHeight)
        let gaps = spacing * CGFloat((captions > 0 ? 1 : 0) + (controls > 0 ? 1 : 0))
        let available = max(0, height - captions - controls - gaps - 24)
        let width = min(max(0, size.width - 24), 1100, available * 16 / 9)
        let video = CGSize(width: width, height: width * 9 / 16)
        let latestTop = max(0, height - 12 - video.height - captions - controls - gaps)
        // Lift the picture gently above center without changing its full-frame size.
        let upwardOffset = min(56, height * 0.06)
        let preferredTop = max(12, height / 2 - video.height / 2 - upwardOffset)
        return Self(videoSize: video, videoTop: min(preferredTop, latestTop),
                    captionHeight: captions, controlsHeight: controls)
    }
}

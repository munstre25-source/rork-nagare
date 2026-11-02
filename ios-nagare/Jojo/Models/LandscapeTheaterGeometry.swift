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
        // Reserve reading room while fitting the video, then give captions all
        // remaining space below it instead of capping their final height.
        let captionReserve = min(max(0, preferredCaptionHeight), height * 0.32)
        let controls = max(0, controlsHeight)
        let gaps = spacing * CGFloat((captionReserve > 0 ? 1 : 0) + (controls > 0 ? 1 : 0))
        let available = max(0, height - captionReserve - controls - gaps - 24)
        let width = min(max(0, size.width - 24), 1100, available * 16 / 9)
        let video = CGSize(width: width, height: width * 9 / 16)
        let latestTop = max(0, height - 12 - video.height - captionReserve - controls - gaps)
        // Anchor the picture around the upper third, leaving words comfortably below.
        let preferredTop = max(12, height * 0.34 - video.height / 2)
        let videoTop = min(preferredTop, latestTop)
        let captions = captionReserve > 0
            ? max(0, height - 12 - videoTop - video.height - controls - gaps)
            : 0
        return Self(videoSize: video, videoTop: videoTop,
                    captionHeight: captions, controlsHeight: controls)
    }
}

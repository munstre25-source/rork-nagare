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
        let widthAvailable = max(0, size.width)
        let isPortrait = height >= widthAvailable
        // Reserve reading room while fitting the video, then give captions all
        // remaining space below it instead of capping their final height.
        let captionReserve = min(max(0, preferredCaptionHeight), height * (isPortrait ? 0.38 : 0.32))
        let controls = max(0, controlsHeight)
        let gaps = spacing * CGFloat((captionReserve > 0 ? 1 : 0) + (controls > 0 ? 1 : 0))
        let topPad: CGFloat = isPortrait ? 8 : 24
        let available = max(0, height - captionReserve - controls - gaps - topPad)
        // Portrait phones: use the full stage width so maximize actually enlarges the picture.
        // Landscape: keep a small side inset so the frame doesn't kiss the edges.
        let sideInset: CGFloat = isPortrait ? 0 : 24
        let width = min(max(0, widthAvailable - sideInset), 1100, available * 16 / 9)
        let video = CGSize(width: width, height: width * 9 / 16)
        let latestTop = max(0, height - 12 - video.height - captionReserve - controls - gaps)
        // Portrait: pin near the top. Landscape: sit around the upper third.
        let preferredTop = isPortrait
            ? topPad
            : max(12, height * 0.34 - video.height / 2)
        let videoTop = min(preferredTop, latestTop)
        let captions = captionReserve > 0
            ? max(0, height - 12 - videoTop - video.height - controls - gaps)
            : 0
        return Self(videoSize: video, videoTop: videoTop,
                    captionHeight: captions, controlsHeight: controls)
    }
}

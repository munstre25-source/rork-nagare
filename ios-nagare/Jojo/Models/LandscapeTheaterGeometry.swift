import Foundation

/// Safe-area-relative placement for a complete landscape picture with a separate karaoke panel.
nonisolated struct LandscapeTheaterGeometry {
    let videoSize: CGSize
    let videoTop: CGFloat
    let captionHeight: CGFloat
    let controlsHeight: CGFloat
    static let spacing: CGFloat = 6

    static func make(in size: CGSize, preferredCaptionHeight: CGFloat, controlsHeight: CGFloat, videoAspect: CGFloat = 16 / 9) -> Self {
        let height = max(0, size.height)
        let widthAvailable = max(0, size.width)
        let isPortrait = height >= widthAvailable
        let aspect = videoAspect.isFinite && videoAspect > 0 ? videoAspect : 16 / 9
        let portraitVideo = aspect < 1
        // Wide videos retain the separate reading area. Portrait videos use a
        // compact caption strip so maximize gives the picture most of the height.
        let captionReserve = min(max(0, preferredCaptionHeight), height * (portraitVideo ? 0.22 : (isPortrait ? 0.38 : 0.32)))
        let controls = max(0, controlsHeight)
        let gaps = spacing * CGFloat((captionReserve > 0 ? 1 : 0) + (controls > 0 ? 1 : 0))
        let topPad: CGFloat = isPortrait
            ? (portraitVideo ? 28 : min(96, max(48, height * 0.11)))
            : 24
        let available = max(0, height - captionReserve - controls - gaps - topPad)
        // Portrait phones: use the full stage width so maximize actually enlarges the picture.
        // Landscape: keep a small side inset so the frame doesn't kiss the edges.
        let sideInset: CGFloat = isPortrait ? 0 : 24
        let width = min(max(0, widthAvailable - sideInset), 1100, available * aspect)
        let video = CGSize(width: width, height: width / aspect)
        let latestTop = max(0, height - 12 - video.height - captionReserve - controls - gaps)
        // Leave breathing room above the maximized picture; keep captions inside the viewport.
        let preferredTop = isPortrait
            ? topPad
            : max(topPad, height * 0.34 - video.height / 2)
        let videoTop = min(preferredTop, latestTop)
        let captions = captionReserve > 0
            ? (portraitVideo ? captionReserve : max(0, height - 12 - videoTop - video.height - controls - gaps))
            : 0
        return Self(videoSize: video, videoTop: videoTop,
                    captionHeight: captions, controlsHeight: controls)
    }
}

/// A video-first Shorts stack with a compact, fixed caption budget below the picture.
nonisolated struct ShortsStageGeometry {
    let cardSize: CGSize
    let videoHeight: CGFloat
    let captionHeight: CGFloat

    static func make(in size: CGSize, preferredCaptionHeight: CGFloat, controlsHeight: CGFloat) -> Self {
        let card = CGSize(width: max(0, min(size.width - 12, 620)), height: max(0, size.height - 6))
        let controls = max(0, controlsHeight)
        let gaps: CGFloat = preferredCaptionHeight > 0 ? 12 : 6
        let available = max(0, card.height - controls - gaps)
        let captions = min(max(0, preferredCaptionHeight), card.height * 0.22, available)
        let video = min(card.width * 16 / 9, max(0, available - captions))
        return Self(cardSize: card, videoHeight: video, captionHeight: captions)
    }
}

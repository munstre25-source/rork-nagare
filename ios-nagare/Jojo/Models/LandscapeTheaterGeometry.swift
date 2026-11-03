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
        let controls = max(0, controlsHeight)
        let topPad: CGFloat = isPortrait
            ? (portraitVideo ? 28 : min(96, max(48, height * 0.11)))
            : 24
        // Honor the requested reading height before fitting the video. On very short
        // viewports retain a usable picture and let the transcript scroll vertically.
        let videoFloor = min(120, height * 0.25)
        let readingRoom = max(0, height - controls - topPad - 24 - videoFloor)
        let captionReserve = min(max(0, preferredCaptionHeight), readingRoom)
        let gaps = spacing * CGFloat((captionReserve > 0 ? 1 : 0) + (controls > 0 ? 1 : 0))
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

/// Fit the picture above a reading viewport large enough for the requested subtitle rows.
nonisolated struct ShortsStageGeometry {
    let cardSize: CGSize
    let videoHeight: CGFloat
    let captionHeight: CGFloat

    static func make(in size: CGSize, preferredCaptionHeight: CGFloat, controlsHeight: CGFloat) -> Self {
        let card = CGSize(width: max(0, min(size.width - 12, 620)), height: max(0, size.height - 6))
        let controls = max(0, controlsHeight)
        let gaps: CGFloat = preferredCaptionHeight > 0 ? 12 : 6
        let available = max(0, card.height - controls - gaps)
        let videoFloor = min(120, available * 0.4)
        let captions = min(max(0, preferredCaptionHeight), max(0, available - videoFloor))
        let video = min(card.width * 16 / 9, max(0, available - captions))
        return Self(cardSize: card, videoHeight: video, captionHeight: captions)
    }
}

/// Default wide-video feed: budget using measured chrome and give every remaining point to karaoke.
nonisolated struct RestingFeedGeometry {
    let videoSize: CGSize
    let captionHeight: CGFloat

    static func make(in size: CGSize, preferredCaptionHeight: CGFloat,
                     channelHeight: CGFloat, controlsHeight: CGFloat) -> Self {
        let chrome = max(0, channelHeight) + max(0, controlsHeight) + 4
        let available = max(0, size.height - chrome)
        let videoFloor = min(90, available * 0.3)
        let height = min(max(0, size.height * 0.5),
                         max(videoFloor, available - max(0, preferredCaptionHeight)))
        let width = min(max(0, size.width), 640, height * 16 / 9)
        let video = CGSize(width: width, height: width * 9 / 16)
        return Self(videoSize: video, captionHeight: max(0, available - video.height))
    }
}

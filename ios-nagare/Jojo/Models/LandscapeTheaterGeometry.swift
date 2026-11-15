import Foundation

/// Safe-area-relative placement for a complete landscape picture with a separate karaoke panel.
nonisolated struct LandscapeTheaterGeometry {
    let videoSize: CGSize
    let videoTop: CGFloat
    let captionHeight: CGFloat
    let controlsHeight: CGFloat
    static let spacing: CGFloat = 6

    static func make(
        in size: CGSize,
        preferredCaptionHeight: CGFloat,
        controlsHeight: CGFloat,
        videoAspect: CGFloat = 16 / 9
    ) -> Self {
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
        let captionLimit = portraitVideo ? readingRoom : min(readingRoom, height * 0.36)
        let captionReserve = min(max(0, preferredCaptionHeight), captionLimit)
        let gaps = spacing * CGFloat((captionReserve > 0 ? 1 : 0) + (controls > 0 ? 1 : 0))
        let available = max(0, height - captionReserve - controls - gaps - topPad)
        // Portrait phones: use the full stage width so maximize actually enlarges the picture.
        // Landscape: keep a small side inset so the frame doesn't kiss the edges.
        let sideInset: CGFloat = isPortrait ? 0 : 24
        let width = min(max(0, widthAvailable - sideInset), 1100, available * aspect)
        let video = CGSize(width: width, height: width / aspect)
        let latestTop = max(0, height - 12 - video.height - captionReserve - controls - gaps)
        // Leave breathing room above the maximized picture; keep captions inside the viewport.
        let preferredTop: CGFloat
        if isPortrait && !portraitVideo {
            // On a portrait screen, keep a wide video just above center and leave
            // the lower portion of the page for its separate karaoke panel.
            preferredTop = max(topPad, height * 0.42 - video.height / 2)
        } else if isPortrait {
            preferredTop = topPad
        } else {
            preferredTop = max(topPad, height * 0.34 - video.height / 2)
        }
        let videoTop = min(preferredTop, latestTop)
        return Self(videoSize: video, videoTop: videoTop,
                    captionHeight: captionReserve, controlsHeight: controls)
    }
}

/// Portrait short: the picture fills the page above the controls; karaoke floats on a bottom band.
nonisolated struct ShortsStageGeometry {
    let cardSize: CGSize
    let videoHeight: CGFloat
    /// Max height for the on-picture caption band. Overlay; does not shrink the video.
    let captionHeight: CGFloat

    static func make(in size: CGSize, preferredCaptionHeight: CGFloat, controlsHeight: CGFloat) -> Self {
        // Exact page fill — any shortfall shows the next clip peeping under the dock.
        let card = CGSize(width: max(0, min(size.width, 620)), height: max(0, size.height))
        let controls = max(0, controlsHeight)
        let gaps: CGFloat = controls > 0 ? 6 : 0
        let available = max(0, card.height - controls - gaps)
        // Cap near a third of the picture so the subject stays clear, while still fitting
        // about two complete subtitle rows plus readings when Beginner aids are on.
        let captions = min(max(0, preferredCaptionHeight), available * 0.34)
        let video = max(0, available)
        return Self(cardSize: card, videoHeight: video, captionHeight: captions)
    }
}

/// Default portrait-feed stack: video, karaoke, then the playback clock at the bottom.
/// Keeping the clock in its own footer prevents it from sitting between the picture and words.
nonisolated struct ShortsFeedGeometry {
    let videoHeight: CGFloat
    let karaokeHeight: CGFloat
    let footerHeight: CGFloat

    static func make(
        in size: CGSize,
        preferredCaptionHeight: CGFloat,
        captionsVisible: Bool,
        focused: Bool,
        footerHeight: CGFloat = 34
    ) -> Self {
        let height = max(0, size.height)
        let footer = min(max(0, footerHeight), height)
        _ = captionsVisible // Visibility changes content, not normal-mode geometry.
        guard !focused else {
            return Self(videoHeight: max(0, height - footer), karaokeHeight: 0, footerHeight: footer)
        }

        // Keep the normal reading well stable whether captions are visible or hidden. CC only
        // changes subtitle visibility; the dedicated focus control is the sole size toggle.
        // The slightly shorter well gives portrait video a little more room without crowding
        // complete subtitle rows. The footer is included in this lower-area budget.
        let lowerArea = min(
            max(footer + 200, height * 0.45, preferredCaptionHeight),
            height * 0.53
        )
        let karaoke = max(0, lowerArea - footer)
        return Self(
            videoHeight: max(0, height - lowerArea),
            karaokeHeight: karaoke,
            footerHeight: footer
        )
    }
}

/// A stable three-position reading window: previous, active, upcoming.
nonisolated struct KaraokeReadingWindow {
    static let maxLines = 3

    /// Always returns three slots. Out-of-range sentinel indices keep the active sentence in
    /// the middle at the beginning and end of a clip. Measurements remain in the signature so
    /// callers can share this geometry API, but sentence height never removes a slot.
    static func indices(
        current: Int,
        lineCount: Int,
        heights: [Int: CGFloat],
        spacing: CGFloat,
        viewportHeight: CGFloat,
        visualRows: [Int: Int]? = nil
    ) -> [Int] {
        guard lineCount > 0 else { return [] }
        let currentIndex = min(max(0, current), lineCount - 1)
        _ = heights
        _ = spacing
        _ = viewportHeight
        _ = visualRows
        return [currentIndex - 1, currentIndex, currentIndex + 1]
    }
}

/// Default wide-video feed: the picture is sized so the karaoke keeps a minimum reading well;
/// on screen the karaoke then fills everything below the controls.
nonisolated struct RestingFeedGeometry {
    let videoSize: CGSize
    let captionHeight: CGFloat

    static func make(in size: CGSize, preferredCaptionHeight: CGFloat,
                     channelHeight: CGFloat, controlsHeight: CGFloat) -> Self {
        let chrome = max(0, channelHeight) + max(0, controlsHeight) + 4
        let available = max(0, size.height - chrome)
        // Cap the reading well so growing subtitle aids never steal the picture.
        let caption = min(max(0, preferredCaptionHeight), max(120, available * 0.32), 200)
        let videoBudget = max(0, available - caption)
        let width = min(max(0, size.width), 640, videoBudget * 16 / 9)
        let video = CGSize(width: width, height: width * 9 / 16)
        return Self(videoSize: video, captionHeight: caption)
    }
}

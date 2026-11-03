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

/// At most three complete subtitle lines that fit inside a karaoke band or reading well.
nonisolated struct KaraokeReadingWindow {
    /// Indices into `clip.lines`, in ascending order. Always includes the current line when
    /// the transcript is non-empty. Drops previous first, then next, when heights overflow.
    static func indices(
        current: Int,
        lineCount: Int,
        heights: [Int: CGFloat],
        spacing: CGFloat,
        viewportHeight: CGFloat
    ) -> [Int] {
        guard lineCount > 0 else { return [] }
        let currentIndex = min(max(0, current), lineCount - 1)
        let previous = currentIndex > 0 ? currentIndex - 1 : nil
        let next = currentIndex + 1 < lineCount ? currentIndex + 1 : nil

        func height(of index: Int) -> CGFloat? {
            guard let value = heights[index], value.isFinite, value > 0 else { return nil }
            return value
        }

        // Until the current line has been measured, mount it alone so the first frame is
        // not a clipped bundle of unknown heights.
        guard let currentHeight = height(of: currentIndex) else { return [currentIndex] }

        var chosen = [currentIndex]
        var used = currentHeight

        if let next, let nextHeight = height(of: next) {
            let needed = used + spacing + nextHeight
            if needed <= viewportHeight + 0.5 {
                chosen.append(next)
                used = needed
            }
        }

        if let previous, let previousHeight = height(of: previous) {
            let needed = used + spacing + previousHeight
            if needed <= viewportHeight + 0.5 {
                chosen.insert(previous, at: 0)
            }
        }

        return chosen
    }
}

/// Default wide-video feed: the picture owns the page; karaoke gets a fixed leftover well.
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

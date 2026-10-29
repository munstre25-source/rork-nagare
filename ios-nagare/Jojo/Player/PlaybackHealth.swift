import Foundation

/// Real-device playback verification.
///
/// YouTube's Data API says `embeddable=true` for videos that rights holders still block in
/// app players (IFrame error 150/101), and some videos never become ready at all. Only the
/// phone can see that, so failures are remembered here (definitive ones hide the clip on this
/// device right away) and reported to the server, which retires the clip for everyone.
@MainActor
enum PlaybackHealth {
    /// IFrame codes that mean "this video will never play here": removed (100), embed blocked (101/150).
    static let definitiveCodes: Set<Int> = [100, 101, 150]
    /// The player page loaded YouTube's API, but this video never became ready.
    static let neverReadyCode = -1
    /// The player was ready and asked to play, but time never moved.
    static let stalledCode = -2

    private static let blockedKey = "jojo.playback.blockedVideoIds"
    private static let reportedKey = "jojo.playback.reportedVideoIds"
    private static let publishedKey = "jojo.catalog.publishedVideoIds"
    private static let playedKey = "jojo.playback.hasPlayedSuccessfully"

    /// True once any YouTube clip actually played on this device. Until then a failure may be
    /// the device's network or YouTube blocking it entirely, so nothing is blamed on the video.
    private static var hasPlayedSuccessfully = UserDefaults.standard.bool(forKey: playedKey)

    static func noteSuccessfulPlayback() {
        guard !hasPlayedSuccessfully else { return }
        hasPlayedSuccessfully = true
        UserDefaults.standard.set(true, forKey: playedKey)
    }

    /// Video ids this device saw fail definitively. Filtered out of every feed.
    static var blockedVideoIds: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: blockedKey) ?? [])
    }

    /// Video ids the server currently publishes; nil until the first successful catalog sync.
    /// Bundled starter clips whose video the server retired are hidden with it.
    static var publishedVideoIds: Set<String>? {
        UserDefaults.standard.stringArray(forKey: publishedKey).map(Set.init)
    }

    static func notePublished(videoIds: Set<String>) {
        guard !videoIds.isEmpty else { return }
        UserDefaults.standard.set(Array(videoIds), forKey: publishedKey)
    }

    /// Records a playback failure. Returns true when the clip should leave this device's feed.
    @discardableResult
    static func recordFailure(clip: Clip, code: Int) -> Bool {
        guard hasPlayedSuccessfully else { return false }
        let definitive = definitiveCodes.contains(code)
        if definitive {
            var blocked = blockedVideoIds
            blocked.insert(clip.videoId)
            UserDefaults.standard.set(Array(blocked), forKey: blockedKey)
        }
        report(clip: clip, code: code)
        return definitive
    }

    private static func report(clip: Clip, code: Int) {
        var reported = Set(UserDefaults.standard.stringArray(forKey: reportedKey) ?? [])
        let key = "\(clip.videoId):\(code)"
        guard !reported.contains(key) else { return }
        reported.insert(key)
        UserDefaults.standard.set(Array(reported), forKey: reportedKey)
        let appUserId = PurchaseManager.currentAppUserId
        let videoId = clip.videoId
        let clipId = clip.id
        Task.detached(priority: .utility) {
            _ = await InsightsService.shared.reportPlaybackFailure(
                videoId: videoId, clipId: clipId, code: code, appUserId: appUserId
            )
        }
    }
}

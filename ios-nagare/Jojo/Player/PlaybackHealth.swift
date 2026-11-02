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

    /// v2: the 2026-10-30 incident poisoned this list during a flaky session (see recordFailure);
    /// bumping the key cleared every device's stale blocks.
    private static let blockedKey = "jojo.playback.blockedVideoIds.v2"
    private static let reportedKey = "jojo.playback.reportedVideoIds"
    private static let publishedClipKey = "jojo.catalog.publishedClipIds"
    private static let publishedKey = "jojo.catalog.publishedVideoIds"
    private static let playedKey = "jojo.playback.hasPlayedSuccessfully"

    /// True once any YouTube clip actually played on this device. Until then a failure may be
    /// the device's network or YouTube blocking it entirely, so nothing is blamed on the video.
    private static var hasPlayedSuccessfully = UserDefaults.standard.bool(forKey: playedKey)

    /// Last time any player advanced. Fresh success = the environment works right now.
    private static var lastSuccessAt: Date?
    /// Distinct videos that failed on this device recently (videoId → last attempt).
    private static var recentFailures: [String: Date] = [:]

    static func noteSuccessfulPlayback() {
        lastSuccessAt = Date()
        recentFailures.removeAll()
        guard !hasPlayedSuccessfully else { return }
        hasPlayedSuccessfully = true
        UserDefaults.standard.set(true, forKey: playedKey)
    }

    /// A storm of distinct failing videos with no successful playback in between means the
    /// environment is broken (network, WebKit bug, simulator) — never the videos. Added after
    /// the 2026-10-30 incident where one flaky session helped retire 39 of 41 catalog clips.
    private static var environmentIsBroken: Bool {
        let window = Date().addingTimeInterval(-600)
        let recent = recentFailures.filter { $0.value > window }
        guard recent.count >= 3 else { return false }
        guard let lastSuccessAt else { return true }
        return lastSuccessAt < (recent.values.min() ?? .distantFuture)
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

    static var publishedClipIds: Set<String>? {
        UserDefaults.standard.stringArray(forKey: publishedClipKey).map(Set.init)
    }

    static func notePublished(videoIds: Set<String>, clipIds: Set<String>? = nil) {
        // A successful empty response is authoritative too; failure never calls this.
        UserDefaults.standard.set(Array(videoIds), forKey: publishedKey)
        if let clipIds { UserDefaults.standard.set(Array(clipIds), forKey: publishedClipKey) }
    }

    /// Records a playback failure. Returns true when the clip should leave this device's feed.
    /// A broken environment (many distinct failures, no success in between) is kept for the
    /// audit trail but never blocks a video locally and never reports it for global retirement.
    @discardableResult
    static func recordFailure(clip: Clip, code: Int) -> Bool {
        guard hasPlayedSuccessfully else { return false }
        recentFailures[clip.videoId] = Date()
        let environmentBroken = environmentIsBroken
        let definitive = definitiveCodes.contains(code) && !environmentBroken
        if definitive {
            var blocked = blockedVideoIds
            blocked.insert(clip.videoId)
            UserDefaults.standard.set(Array(blocked), forKey: blockedKey)
        }
        if !environmentBroken {
            report(clip: clip, code: code)
        }
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

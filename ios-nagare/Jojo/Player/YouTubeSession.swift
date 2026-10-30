import Foundation
import Observation
import WebKit

/// The cookie jar every YouTube embed shares, and the network-level health of YouTube playback.
///
/// 2026-10-30 incident: the same build played ~35 clips flawlessly, then every embed began
/// failing with error 150 ("Sign in to confirm you're not a bot") for every video. A fresh
/// in-memory visitor session did NOT clear it: YouTube was limiting the *network* (the cloud
/// simulator's datacenter IP). What made it worse was us: each failing clip fired 4-5 embed
/// loads (ladder + self-heal), and the feed auto-skipped to the next clip after 1.8s — a
/// machine-gun of embeds that looks exactly like the bot YouTube is guarding against.
///
/// So now: one storm signal (2+ distinct videos refused with no playback in between) puts
/// playback into `isLimited` mode — no ladder, no auto-skip, no session churn — and a single
/// slow probe on the clip on screen detects recovery. The first frame that plays clears it.
@Observable
@MainActor
final class YouTubeSession {
    static let shared = YouTubeSession()

    /// True while YouTube is refusing every embed from this network.
    private(set) var isLimited = false

    @ObservationIgnored private(set) var store: WKWebsiteDataStore = .nonPersistent()
    /// Bumped on every reset; players built on an older generation rebuild their web view.
    @ObservationIgnored private(set) var generation = 0
    @ObservationIgnored private var lastResetAt: Date = .distantPast
    @ObservationIgnored private var lastSuccessAt: Date = .distantPast
    @ObservationIgnored private var refusedSinceSuccess: Set<String> = []
    @ObservationIgnored private var didPurgeLegacyStore = false

    /// How often the on-screen clip re-probes YouTube while limited.
    static let probeInterval: Duration = .seconds(30)

    func noteSuccess() {
        lastSuccessAt = Date()
        refusedSinceSuccess.removeAll()
        if isLimited {
            isLimited = false
            print("[YouTube] playback restored")
        }
    }

    /// An embed-identity refusal (150/101) for `videoId`. Two distinct videos refused with no
    /// playback in between is a network-level block, not the videos.
    func noteRefusal(videoId: String) {
        refusedSinceSuccess.insert(videoId)
        if refusedSinceSuccess.count >= 2, !isLimited {
            isLimited = true
            print("[YouTube] network limited: every embed refused — pausing retries")
        }
    }

    /// Starts a fresh visitor session once per storm (a flagged cookie is the cheap case to
    /// rule out), never more than once every 10 minutes otherwise.
    /// - Returns: true when a new session was created and the load should be retried in it.
    @discardableResult
    func resetIfFlagged() -> Bool {
        guard !isLimited else { return false }
        let now = Date()
        let playedSinceReset = lastSuccessAt > lastResetAt
        let cooledDown = now.timeIntervalSince(lastResetAt) > 600
        guard playedSinceReset || cooledDown else { return false }
        lastResetAt = now
        generation += 1
        store = .nonPersistent()
        print("[YouTube] fresh visitor session #\(generation)")
        return true
    }

    /// Builds earlier than 2026-10-30 kept YouTube cookies in the persistent store; a flagged
    /// visitor from those builds must not follow the user into this one.
    func purgeLegacyStoreOnce() {
        guard !didPurgeLegacyStore else { return }
        didPurgeLegacyStore = true
        let store = WKWebsiteDataStore.default()
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        store.fetchDataRecords(ofTypes: types) { records in
            let youtube = records.filter { record in
                let name = record.displayName.lowercased()
                return name.contains("youtube") || name.contains("google") || name.contains("ytimg")
                    || name.contains("doubleclick") || name.contains("ggpht")
            }
            guard !youtube.isEmpty else { return }
            store.removeData(ofTypes: types, for: youtube) {}
        }
    }
}

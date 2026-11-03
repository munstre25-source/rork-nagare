import Foundation

/// Per-category starting rate and whether line-loop fits the clip type.
enum PlaybackDefaults {
    static let quickChecksKey = "jojo.quickChecksEnabled"

    /// Read at clip completion, including from callbacks created before a setting changed.
    static func quickChecksEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: quickChecksKey) as? Bool ?? true
    }

    struct Profile: Sendable {
        var rate: Double
        var preferLineLoop: Bool
    }

    static func profile(for category: ClipCategory) -> Profile {
        switch category {
        case .anime, .kids:
            return Profile(rate: 0.75, preferLineLoop: true)
        case .drama, .interview, .learning, .podcast:
            return Profile(rate: 1.0, preferLineLoop: false)
        case .variety, .vtuber, .gaming:
            return Profile(rate: 0.75, preferLineLoop: false)
        }
    }

    private static let rateKey = "jojo.playback.preferredRate"
    private static let loopKey = "jojo.playback.preferLineLoop"
    private static let categoryKey = "jojo.playback.lastCategory"

    static var storedRate: Double {
        get {
            let value = UserDefaults.standard.double(forKey: rateKey)
            return value > 0 ? value : 1
        }
        set { UserDefaults.standard.set(newValue, forKey: rateKey) }
    }

    static var storedPreferLineLoop: Bool {
        get { UserDefaults.standard.bool(forKey: loopKey) }
        set { UserDefaults.standard.set(newValue, forKey: loopKey) }
    }

    static var lastCategory: String? {
        get { UserDefaults.standard.string(forKey: categoryKey) }
        set { UserDefaults.standard.set(newValue, forKey: categoryKey) }
    }

    /// Applies category defaults when the learner has not manually locked a rate this session.
    static func applyCategoryDefaults(for clip: Clip, hasManualRate: Bool) -> Profile {
        let base = profile(for: clip.categoryKind)
        lastCategory = clip.category
        if hasManualRate {
            return Profile(rate: storedRate, preferLineLoop: storedPreferLineLoop || base.preferLineLoop)
        }
        storedRate = base.rate
        storedPreferLineLoop = base.preferLineLoop
        return base
    }
}

/// Cross-launch resume: last clip + playback time.
enum ResumePlaybackStore {
    private static let clipKey = "jojo.resume.clipId"
    private static let timeKey = "jojo.resume.time"
    private static let lineKey = "jojo.resume.line"
    private static let titleKey = "jojo.resume.title"
    private static let channelKey = "jojo.resume.channel"

    static func save(clip: Clip, time: Double, lineIndex: Int) {
        guard !clip.id.isEmpty, time > 1 else { return }
        UserDefaults.standard.set(clip.id, forKey: clipKey)
        UserDefaults.standard.set(time, forKey: timeKey)
        UserDefaults.standard.set(lineIndex, forKey: lineKey)
        UserDefaults.standard.set(clip.title, forKey: titleKey)
        UserDefaults.standard.set(clip.channelName, forKey: channelKey)
    }

    static func clear() {
        [clipKey, timeKey, lineKey, titleKey, channelKey].forEach {
            UserDefaults.standard.removeObject(forKey: $0)
        }
    }

    static var snapshot: (clipId: String, time: Double, line: Int, title: String, channel: String)? {
        guard let id = UserDefaults.standard.string(forKey: clipKey), !id.isEmpty else { return nil }
        let time = UserDefaults.standard.double(forKey: timeKey)
        guard time > 1 else { return nil }
        return (
            id,
            time,
            UserDefaults.standard.integer(forKey: lineKey),
            UserDefaults.standard.string(forKey: titleKey) ?? "",
            UserDefaults.standard.string(forKey: channelKey) ?? ""
        )
    }
}

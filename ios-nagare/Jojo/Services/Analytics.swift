import Foundation

/// Event tracking: console + local ring buffer, first-party upload (see `AnalyticsUploader`;
/// sanitized props only, respects `AnalyticsConsent`), and a narrow Meta event allowlist.
///
/// Meta ad-SDK rules (do not violate in future call sites):
/// - Only the RevenueCat Conversions API receives purchase/subscription events.
/// - Meta events carry only an allowlisted event name; no event parameters are forwarded.
///   Never send user-typed text, word/sentence content, or free-text feedback to Meta.
nonisolated enum Analytics {
    private static let storageKey = "nagare.analytics.log"
    private static let maxEvents = 500

    static func track(_ event: String, props: [String: String] = [:]) {
        let propsText = props.isEmpty ? "" : " " + props.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
        print("[track] \(event)\(propsText)")
        let defaults = UserDefaults.standard
        var log = defaults.array(forKey: storageKey) as? [[String: String]] ?? []
        var entry = props
        entry["event"] = event
        entry["ts"] = ISO8601DateFormatter().string(from: Date())
        log.append(entry)
        if log.count > maxEvents { log.removeFirst(log.count - maxEvents) }
        defaults.set(log, forKey: storageKey)

        if AnalyticsConsent.isEnabled {
            let date = Date()
            Task { await AnalyticsUploader.shared.enqueue(name: event, props: props, at: date) }
        }

        MetaAttribution.logAllowedEvent(named: event)

        if event == "word_tapped" || event == "word_heard" {
            Task { @MainActor in GuidanceCenter.shared.observe(event) }
        }
    }
}

/// Top-level convenience matching the spec's `track(_:props:)` helper.
nonisolated func track(_ event: String, props: [String: String] = [:]) {
    Analytics.track(event, props: props)
}

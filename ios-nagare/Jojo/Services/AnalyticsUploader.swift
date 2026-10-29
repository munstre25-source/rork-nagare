import Foundation

/// First-party, privacy-conscious analytics transport.
///
/// - Identity is a random install UUID (never the RevenueCat id, device id or advertising id).
///   When an anonymous Supabase session already exists, its JWT is sent so the server can attach
///   the verified user id; analytics never creates a session on its own.
/// - Props are sanitized here and again on the server: identifiers and enums only. Words,
///   sentences, transcripts, messages, names and any free text are dropped.
/// - Events queue on disk, upload in batches, dedupe by event UUID, and retry with backoff.

/// The learner's analytics choice. Default on (first-party, disclosed in the privacy policy),
/// switchable in Profile → Privacy.
nonisolated enum AnalyticsConsent {
    static let key = "jojo.analytics.enabled"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? true
    }

    static func set(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: key)
        if !enabled {
            Task { await AnalyticsUploader.shared.purge() }
        }
    }
}

/// Random per-install identifier. Reset with "Delete my data".
nonisolated enum InstallIdentity {
    private static let key = "jojo.analytics.installId"

    static var id: String {
        if let existing = UserDefaults.standard.string(forKey: key), UUID(uuidString: existing) != nil {
            return existing
        }
        let fresh = UUID().uuidString.lowercased()
        UserDefaults.standard.set(fresh, forKey: key)
        return fresh
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

/// App/OS context attached to events and sessions. Contains no device identifiers.
nonisolated enum AnalyticsContext {
    static let appVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    static let build: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    static let osVersion: String = {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion)"
    }()
}

/// Mirrors the server rules in `_shared/analytics.ts` so nothing sensitive ever leaves the phone.
nonisolated enum AnalyticsSanitizer {
    static let blockedKeys: Set<String> = [
        "word", "surface", "text", "sentence", "line_text", "transcript", "message", "body",
        "title", "query", "email", "name", "phone", "ip", "url", "audio",
    ]
    static let maxProps = 12
    static let maxValueLength = 64

    static func isValidName(_ name: String) -> Bool {
        name.range(of: "^[a-z][a-z0-9_]{1,63}$", options: .regularExpression) != nil
    }

    static func props(_ raw: [String: String]) -> [String: String] {
        var out: [String: String] = [:]
        for key in raw.keys.sorted() {
            guard out.count < maxProps, let value = raw[key] else { continue }
            guard key.range(of: "^[a-z][a-z0-9_]{0,31}$", options: .regularExpression) != nil,
                  !blockedKeys.contains(key) else { continue }
            let trimmed = String(value.trimmingCharacters(in: .whitespaces).prefix(maxValueLength))
            // Identifiers and enums only: spaces or non-ASCII mean free text, which is dropped.
            guard trimmed.range(of: "^[A-Za-z0-9_.:\\-]*$", options: .regularExpression) != nil else { continue }
            out[key] = trimmed
        }
        return out
    }
}

nonisolated struct QueuedEvent: Codable, Sendable, Equatable {
    var id: String
    var name: String
    var props: [String: String]
    var occurredAt: Date
    var sessionId: String?
}

nonisolated struct SessionSnapshot: Codable, Sendable, Equatable {
    var id: String
    var startedAt: Date
    var lastSeenAt: Date
    var activeSeconds: Int
    var deviceClass: String
}

private nonisolated struct QueueFile: Codable {
    var events: [QueuedEvent]
    var sessions: [SessionSnapshot]
}

actor AnalyticsUploader {
    static let shared = AnalyticsUploader()

    static let maxQueued = 3000
    static let batchSize = 200
    static let flushThreshold = 20
    static let flushInterval: TimeInterval = 30

    private var events: [QueuedEvent] = []
    private var sessions: [String: SessionSnapshot] = [:]
    private var currentSessionId: String?
    private var flushing = false
    private var failures = 0
    private var nextAttempt = Date.distantPast
    private var lastFlush = Date.distantPast
    private let fileURL: URL?
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    init(fileURL: URL? = AnalyticsUploader.defaultFileURL) {
        self.fileURL = fileURL
        if let fileURL, let data = try? Data(contentsOf: fileURL),
           let file = try? Self.coder.decoder.decode(QueueFile.self, from: data) {
            events = file.events
            sessions = Dictionary(file.sessions.map { ($0.id, $0) }, uniquingKeysWith: { $1 })
        }
    }

    static var defaultFileURL: URL? {
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "analytics-queue.json")
    }

    // MARK: Queue

    var queuedEvents: [QueuedEvent] { events }

    func setCurrentSession(_ id: String?) { currentSessionId = id }

    func enqueue(name: String, props: [String: String], at date: Date = Date()) {
        guard AnalyticsSanitizer.isValidName(name) else { return }
        let event = QueuedEvent(
            id: UUID().uuidString.lowercased(),
            name: name,
            props: AnalyticsSanitizer.props(props),
            occurredAt: date,
            sessionId: currentSessionId
        )
        events.append(event)
        if events.count > Self.maxQueued { events.removeFirst(events.count - Self.maxQueued) }
        persist()
        if events.count >= Self.flushThreshold {
            Task { await self.flush() }
        }
    }

    func upsertSession(_ snapshot: SessionSnapshot) {
        sessions[snapshot.id] = snapshot
        persist()
    }

    /// Opt-out or data deletion: forget everything not yet uploaded.
    func purge() {
        events.removeAll()
        sessions.removeAll()
        currentSessionId = nil
        persist()
    }

    /// Called from the session tick; uploads at most every `flushInterval`.
    func flushIfDue() async {
        guard Date().timeIntervalSince(lastFlush) >= Self.flushInterval else { return }
        await flush()
    }

    func flush() async {
        guard AnalyticsConsent.isEnabled else { purge(); return }
        guard !flushing, Date() >= nextAttempt, !(events.isEmpty && sessions.isEmpty) else { return }
        guard Secrets.isSupabaseConfigured, let base = URL(string: Secrets.supabaseURL) else { return }
        flushing = true
        defer { flushing = false }
        lastFlush = Date()

        let batch = Array(events.prefix(Self.batchSize))
        let sessionBatch = Array(sessions.values.sorted { $0.lastSeenAt > $1.lastSeenAt }.prefix(20))
        let token = await SupabaseAuth.shared.existingSession()?.accessToken ?? Secrets.supabaseAnonKey

        var request = URLRequest(url: base.appending(path: "functions/v1/analytics-ingest"))
        request.httpMethod = "POST"
        request.setValue(Secrets.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.body(installId: InstallIdentity.id, events: batch, sessions: sessionBatch)

        let status: Int
        do {
            let (_, response) = try await session.data(for: request)
            status = (response as? HTTPURLResponse)?.statusCode ?? 0
        } catch {
            status = 0
        }

        if (200..<300).contains(status) || status == 400 {
            // 400 means the batch itself is unusable: drop it rather than retry forever.
            let sent = Set(batch.map(\.id))
            events.removeAll { sent.contains($0.id) }
            for snap in sessionBatch where sessions[snap.id] == snap {
                sessions[snap.id] = nil
            }
            failures = 0
            nextAttempt = .distantPast
            persist()
            if events.count >= Self.flushThreshold {
                Task { await self.flush() }
            }
        } else {
            failures += 1
            let delay = min(pow(2, Double(failures)) * 5, 600)
            nextAttempt = Date().addingTimeInterval(delay)
        }
    }

    // MARK: Encoding

    static func body(installId: String, events: [QueuedEvent], sessions: [SessionSnapshot]) -> Data {
        let iso = ISO8601DateFormatter()
        let payload: [String: Any] = [
            "install_id": installId,
            "events": events.map { e -> [String: Any] in
                var row: [String: Any] = [
                    "id": e.id,
                    "name": e.name,
                    "props": e.props,
                    "occurred_at": iso.string(from: e.occurredAt),
                    "app_version": AnalyticsContext.appVersion,
                    "os_version": AnalyticsContext.osVersion,
                ]
                if let sid = e.sessionId { row["session_id"] = sid }
                return row
            },
            "sessions": sessions.map { s -> [String: Any] in
                [
                    "id": s.id,
                    "started_at": iso.string(from: s.startedAt),
                    "last_seen_at": iso.string(from: s.lastSeenAt),
                    "active_seconds": s.activeSeconds,
                    "app_version": AnalyticsContext.appVersion,
                    "build": AnalyticsContext.build,
                    "os_version": AnalyticsContext.osVersion,
                    "device_class": s.deviceClass,
                ]
            },
        ]
        return (try? JSONSerialization.data(withJSONObject: payload)) ?? Data("{}".utf8)
    }

    private func persist() {
        guard let fileURL else { return }
        let file = QueueFile(events: events, sessions: Array(sessions.values))
        guard let data = try? Self.coder.encoder.encode(file) else { return }
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private static var coder: (encoder: JSONEncoder, decoder: JSONDecoder) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (encoder, decoder)
    }
}

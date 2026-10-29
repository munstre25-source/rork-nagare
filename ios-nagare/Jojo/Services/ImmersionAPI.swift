import Foundation

/// Server-side state of a "turn this YouTube video into a lesson" request.
nonisolated struct ImmersionJob: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var videoId: String
    var status: String
    var stage: String
    var attempts: Int
    var maxAttempts: Int
    var errorCode: String?
    var errorMessage: String?
    var title: String?
    var channelName: String?
    var videoDurationSec: Double?
    var clipId: String?
    var timingMode: String?
    var createdAt: String?
    var updatedAt: String?
    var nextAttemptAt: String?
    /// The finished lesson, embedded by PostgREST through the `clip_id` foreign key.
    var clip: Clip?

    enum CodingKeys: String, CodingKey {
        case id, status, stage, attempts, title, clip
        case videoId = "video_id"
        case maxAttempts = "max_attempts"
        case errorCode = "error_code"
        case errorMessage = "error_message"
        case channelName = "channel_name"
        case videoDurationSec = "video_duration_sec"
        case clipId = "clip_id"
        case timingMode = "timing_mode"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case nextAttemptAt = "next_attempt_at"
        case clipsEmbed = "clips"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        videoId = try c.decode(String.self, forKey: .videoId)
        status = try c.decode(String.self, forKey: .status)
        stage = try c.decodeIfPresent(String.self, forKey: .stage) ?? "queued"
        attempts = try c.decodeIfPresent(Int.self, forKey: .attempts) ?? 0
        maxAttempts = try c.decodeIfPresent(Int.self, forKey: .maxAttempts) ?? 3
        errorCode = try c.decodeIfPresent(String.self, forKey: .errorCode)
        errorMessage = try c.decodeIfPresent(String.self, forKey: .errorMessage)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        channelName = try c.decodeIfPresent(String.self, forKey: .channelName)
        videoDurationSec = try c.decodeIfPresent(Double.self, forKey: .videoDurationSec)
        clipId = try c.decodeIfPresent(String.self, forKey: .clipId)
        timingMode = try c.decodeIfPresent(String.self, forKey: .timingMode)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt)
        nextAttemptAt = try c.decodeIfPresent(String.self, forKey: .nextAttemptAt)
        // Server rows embed `clips` (a ClipRow); the local cache stores the decoded `clip`.
        if let row = try? c.decodeIfPresent(ClipRow.self, forKey: .clipsEmbed), !row.lines.isEmpty {
            clip = row.clip
        } else {
            clip = try? c.decodeIfPresent(Clip.self, forKey: .clip)
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(videoId, forKey: .videoId)
        try c.encode(status, forKey: .status)
        try c.encode(stage, forKey: .stage)
        try c.encode(attempts, forKey: .attempts)
        try c.encode(maxAttempts, forKey: .maxAttempts)
        try c.encodeIfPresent(errorCode, forKey: .errorCode)
        try c.encodeIfPresent(errorMessage, forKey: .errorMessage)
        try c.encodeIfPresent(title, forKey: .title)
        try c.encodeIfPresent(channelName, forKey: .channelName)
        try c.encodeIfPresent(videoDurationSec, forKey: .videoDurationSec)
        try c.encodeIfPresent(clipId, forKey: .clipId)
        try c.encodeIfPresent(timingMode, forKey: .timingMode)
        try c.encodeIfPresent(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(updatedAt, forKey: .updatedAt)
        try c.encodeIfPresent(nextAttemptAt, forKey: .nextAttemptAt)
        try c.encodeIfPresent(clip, forKey: .clip)
    }

    var phase: Phase {
        switch status {
        case "succeeded": clip == nil ? .working : .ready
        case "failed": .failed
        case "unprocessable": .unprocessable
        case "processing": .working
        default: .queued
        }
    }

    enum Phase: Sendable { case queued, working, ready, failed, unprocessable }

    var isActive: Bool { phase == .queued || phase == .working }

    /// Plain-language progress for the current pipeline stage.
    var stageLabel: String {
        switch phase {
        case .ready: return "Ready to watch"
        case .failed: return "Couldn't finish"
        case .unprocessable: return "Can't be used"
        case .queued:
            if attempts > 0 { return errorCode == "model_unavailable" || errorCode == "quota_exhausted" ? "Waiting to retry" : "Retrying soon" }
            return "In line"
        case .working:
            switch stage {
            case "checking": return "Checking the video"
            case "transcribing": return "Listening for Japanese"
            case "validating": return "Checking the timing"
            case "enriching": return "Adding readings and meanings"
            case "publishing": return "Almost done"
            default: return "Working"
            }
        }
    }

    /// 0…1 for the progress bar. Stage-based, never time-faked.
    var stageProgress: Double {
        switch phase {
        case .ready: return 1
        case .failed, .unprocessable: return 0
        case .queued: return 0.05
        case .working:
            switch stage {
            case "checking": return 0.15
            case "transcribing": return 0.4
            case "validating": return 0.65
            case "enriching": return 0.8
            case "publishing": return 0.95
            default: return 0.1
            }
        }
    }

    /// Resubmitting is the manual retry; the server enforces its own cool-down.
    var canRetry: Bool {
        switch phase {
        case .failed: return true
        case .unprocessable:
            return ["live_stream", "private_video", "not_embeddable", "video_not_found"].contains(errorCode ?? "")
        default: return false
        }
    }

    var displayTitle: String { clip?.title ?? title ?? "YouTube video" }
    var watchURL: URL? { URL(string: "https://www.youtube.com/watch?v=\(videoId)") }
}

nonisolated enum ImmersionAPIError: Error, Equatable {
    case notConfigured
    case offline
    case invalidURL(String)
    case dailyLimit(String)
    case unauthorized
    case server(String)

    var message: String {
        switch self {
        case .notConfigured: "Video lessons aren't available in this build."
        case .offline: "You're offline. Connect to the internet and try again."
        case .invalidURL(let message), .dailyLimit(let message), .server(let message): message
        case .unauthorized: "Couldn't start a secure session. Please try again."
        }
    }
}

/// A row of `user_vocab`. Mirrors a `SavedWord`; the device stays the source of truth for SRS.
nonisolated struct RemoteVocabRow: Codable, Sendable, Equatable {
    var userId: String?
    var term: String
    var reading: String
    var surface: String?
    var romaji: String?
    var pos: String?
    var jlpt: String?
    var definitions: [String]
    var contextSentence: String?
    var contextNote: String?
    var clipId: String?
    var lineIndex: Int?
    var encounterCount: Int
    var srsState: String

    enum CodingKeys: String, CodingKey {
        case term, reading, surface, romaji, pos, jlpt, definitions
        case userId = "user_id"
        case contextSentence = "context_sentence"
        case contextNote = "context_note"
        case clipId = "clip_id"
        case lineIndex = "line_index"
        case encounterCount = "encounter_count"
        case srsState = "srs_state"
    }
}

/// A row of `practice_attempts`.
nonisolated struct PracticeAttemptRow: Codable, Sendable, Identifiable, Equatable {
    var id: String?
    var clipId: String
    var lineIndex: Int
    var targetText: String
    var recognizedText: String
    var similarity: Int
    var scoringMethod: String
    var locale: String
    var onDevice: Bool
    var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, similarity, locale
        case clipId = "clip_id"
        case lineIndex = "line_index"
        case targetText = "target_text"
        case recognizedText = "recognized_text"
        case scoringMethod = "scoring_method"
        case onDevice = "on_device"
        case createdAt = "created_at"
    }
}

/// Requests made as the learner's anonymous Supabase user, so RLS scopes every row to them.
nonisolated struct UserDataAPI: Sendable {
    let api: SupabaseAPI
    let auth: SupabaseAuth

    static let shared = UserDataAPI(api: .shared, auth: .shared)

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    var isConfigured: Bool { api.isConfigured }

    // MARK: Immersion

    /// POST /functions/v1/immersion-submit
    func submitVideo(_ link: String) async throws -> ImmersionJob {
        let (data, status) = try await send(
            method: "POST",
            path: "functions/v1/immersion-submit",
            body: try JSONSerialization.data(withJSONObject: ["url": link])
        )
        if (200..<300).contains(status) {
            struct Envelope: Decodable { let job: ImmersionJob }
            return try JSONDecoder().decode(Envelope.self, from: data).job
        }
        let message = (try? JSONDecoder().decode(ServerError.self, from: data))?.message
            ?? "Something went wrong. Please try again."
        switch status {
        case 400: throw ImmersionAPIError.invalidURL(message)
        case 429: throw ImmersionAPIError.dailyLimit(message)
        case 401: throw ImmersionAPIError.unauthorized
        default: throw ImmersionAPIError.server(message)
        }
    }

    /// The learner's jobs with any finished clip embedded. RLS returns only their requests.
    func fetchJobs(ids: [String]? = nil) async throws -> [ImmersionJob] {
        var query = [
            URLQueryItem(name: "select", value: "id,video_id,status,stage,attempts,max_attempts,error_code,error_message,title,channel_name,video_duration_sec,clip_id,timing_mode,created_at,updated_at,next_attempt_at,clips(*)"),
            URLQueryItem(name: "order", value: "created_at.desc"),
            URLQueryItem(name: "limit", value: "50"),
        ]
        if let ids, !ids.isEmpty {
            query.append(URLQueryItem(name: "id", value: "in.(\(ids.joined(separator: ",")))"))
        }
        let (data, status) = try await send(method: "GET", path: "rest/v1/immersion_jobs", query: query)
        guard (200..<300).contains(status) else { throw ImmersionAPIError.server("Couldn't refresh your videos.") }
        return try JSONDecoder().decode([LossyJob].self, from: data).compactMap(\.value)
    }

    // MARK: Vocab

    func upsertVocab(_ rows: [RemoteVocabRow]) async throws {
        guard !rows.isEmpty else { return }
        let userId = try await auth.validSession().userId
        let stamped = rows.map { row -> RemoteVocabRow in
            var copy = row
            copy.userId = userId
            return copy
        }
        let (_, status) = try await send(
            method: "POST",
            path: "rest/v1/user_vocab",
            query: [URLQueryItem(name: "on_conflict", value: "user_id,term,reading")],
            body: try JSONEncoder().encode(stamped),
            prefer: "resolution=merge-duplicates,return=minimal"
        )
        guard (200..<300).contains(status) else { throw ImmersionAPIError.server("vocab upsert \(status)") }
    }

    func deleteVocab(term: String, reading: String) async throws {
        let (_, status) = try await send(
            method: "DELETE",
            path: "rest/v1/user_vocab",
            query: [
                URLQueryItem(name: "term", value: "eq.\(term)"),
                URLQueryItem(name: "reading", value: "eq.\(reading)"),
            ],
            prefer: "return=minimal"
        )
        guard (200..<300).contains(status) else { throw ImmersionAPIError.server("vocab delete \(status)") }
    }

    func fetchVocab() async throws -> [RemoteVocabRow] {
        let (data, status) = try await send(
            method: "GET",
            path: "rest/v1/user_vocab",
            query: [
                URLQueryItem(name: "select", value: "term,reading,surface,romaji,pos,jlpt,definitions,context_sentence,context_note,clip_id,line_index,encounter_count,srs_state"),
                URLQueryItem(name: "order", value: "updated_at.desc"),
                URLQueryItem(name: "limit", value: "5000"),
            ]
        )
        guard (200..<300).contains(status) else { throw ImmersionAPIError.server("vocab fetch \(status)") }
        return try JSONDecoder().decode([RemoteVocabRow].self, from: data)
    }

    // MARK: Practice

    func recordPractice(_ attempt: PracticeAttemptRow) async throws {
        var row = attempt
        row.id = nil
        row.createdAt = nil
        let (_, status) = try await send(
            method: "POST",
            path: "rest/v1/practice_attempts",
            body: try JSONEncoder().encode(row),
            prefer: "return=minimal"
        )
        guard (200..<300).contains(status) else { throw ImmersionAPIError.server("practice insert \(status)") }
    }

    func practiceHistory(clipId: String, lineIndex: Int, limit: Int = 5) async throws -> [PracticeAttemptRow] {
        let (data, status) = try await send(
            method: "GET",
            path: "rest/v1/practice_attempts",
            query: [
                URLQueryItem(name: "select", value: "id,clip_id,line_index,target_text,recognized_text,similarity,scoring_method,locale,on_device,created_at"),
                URLQueryItem(name: "clip_id", value: "eq.\(clipId)"),
                URLQueryItem(name: "line_index", value: "eq.\(lineIndex)"),
                URLQueryItem(name: "order", value: "created_at.desc"),
                URLQueryItem(name: "limit", value: String(limit)),
            ]
        )
        guard (200..<300).contains(status) else { throw ImmersionAPIError.server("practice fetch \(status)") }
        return try JSONDecoder().decode([PracticeAttemptRow].self, from: data)
    }

    // MARK: Account data

    /// POST /functions/v1/delete-my-data. Deletes the anonymous user; rows cascade. The previous
    /// analytics install id is sent too so its usage rows are removed with it.
    func deleteMyData(installId: String? = nil) async throws {
        var payload: [String: String] = [:]
        if let installId { payload["install_id"] = installId }
        let body = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data("{}".utf8)
        let (_, status) = try await send(
            method: "POST", path: "functions/v1/delete-my-data", body: body, retryingAuth: false
        )
        if status == 401 { throw ImmersionAPIError.unauthorized }
        guard (200..<300).contains(status) else { throw ImmersionAPIError.server("delete \(status)") }
    }

    // MARK: Transport

    private func send(
        method: String,
        path: String,
        query: [URLQueryItem]? = nil,
        body: Data? = nil,
        prefer: String? = nil,
        retryingAuth: Bool = true
    ) async throws -> (Data, Int) {
        guard let baseURL = api.baseURL else { throw ImmersionAPIError.notConfigured }
        let session: AuthSession
        do {
            session = try await auth.validSession()
        } catch AuthError.offline {
            throw ImmersionAPIError.offline
        } catch {
            throw ImmersionAPIError.unauthorized
        }
        guard var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false) else {
            throw ImmersionAPIError.notConfigured
        }
        components.queryItems = query
        // `+` is literal in PostgREST filters; URLComponents leaves it unescaped.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        guard let url = components.url else { throw ImmersionAPIError.notConfigured }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(api.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let prefer { request.setValue(prefer, forHTTPHeaderField: "Prefer") }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await Self.session.data(for: request)
        } catch {
            throw ImmersionAPIError.offline
        }
        guard let http = response as? HTTPURLResponse else { throw ImmersionAPIError.server("Invalid response") }
        if http.statusCode == 401, retryingAuth {
            // Access token revoked early (e.g. user deleted server-side): start a fresh session once.
            await auth.reset()
            return try await send(method: method, path: path, query: query, body: body, prefer: prefer, retryingAuth: false)
        }
        return (data, http.statusCode)
    }
}

private nonisolated struct ServerError: Decodable {
    let error: String?
    let message: String?
}

private nonisolated struct LossyJob: Decodable {
    let value: ImmersionJob?
    init(from decoder: Decoder) throws {
        value = try? ImmersionJob(from: decoder)
    }
}

/// Client-side YouTube link check, so obvious typos fail instantly. The server re-validates.
nonisolated enum YouTubeLink {
    /// The 11-character video id in a YouTube URL or a bare id, or nil.
    static func videoId(from raw: String) -> String? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if isVideoId(text) { return text }
        let candidate = text.contains("://") ? text : "https://\(text)"
        guard let components = URLComponents(string: candidate), let host = components.host?.lowercased() else { return nil }
        let bareHost = host.hasPrefix("www.") ? String(host.dropFirst(4)) : (host.hasPrefix("m.") ? String(host.dropFirst(2)) : host)
        let parts = components.path.split(separator: "/").map(String.init)
        if bareHost == "youtu.be" {
            return parts.first.flatMap { isVideoId($0) ? $0 : nil }
        }
        guard bareHost == "youtube.com" || bareHost == "music.youtube.com" || bareHost == "youtube-nocookie.com" else { return nil }
        if parts.first == "watch", let v = components.queryItems?.first(where: { $0.name == "v" })?.value, isVideoId(v) {
            return v
        }
        if parts.count >= 2, ["shorts", "embed", "live", "v", "e"].contains(parts[0]), isVideoId(parts[1]) {
            return parts[1]
        }
        return nil
    }

    static func isVideoId(_ text: String) -> Bool {
        text.count == 11 && text.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }
}

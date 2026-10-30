import Foundation

nonisolated enum SupabaseError: Error {
    case notConfigured
    case http(Int)
    case invalidResponse
}

/// Minimal Supabase REST client over URLSession. No SDK.
nonisolated struct SupabaseAPI: Sendable {
    let baseURL: URL?
    let anonKey: String

    static let shared = SupabaseAPI(
        baseURL: Secrets.isSupabaseConfigured ? URL(string: Secrets.supabaseURL) : nil,
        anonKey: Secrets.supabaseAnonKey
    )

    /// Session budget for Gemini word explanations. Local dictionary still answers first.
    private static let explainSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 12
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    private static let librarySession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    var isConfigured: Bool { baseURL != nil }

    private func authorized(_ request: inout URLRequest) {
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
    }

    /// POST /functions/v1/explain-word. Returns the raw payload for caching.
    func explainWord(kind: String, word: String, sentence: String, appUserId: String) async throws -> Data {
        guard let baseURL else { throw SupabaseError.notConfigured }
        var request = URLRequest(url: baseURL.appending(path: "functions/v1/explain-word"))
        request.httpMethod = "POST"
        authorized(&request)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(appUserId, forHTTPHeaderField: "x-app-user-id")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["kind": kind, "word": word, "sentence": sentence])
        let (data, response) = try await Self.explainSession.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SupabaseError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw SupabaseError.http(http.statusCode) }
        return data
    }

    /// POST /rest/v1/rpc/<name>. Word and grammar search over the whole catalog.
    func rpcLineHits(_ name: String, _ params: [String: Any]) async throws -> [LineHitRow] {
        guard let baseURL else { throw SupabaseError.notConfigured }
        var request = URLRequest(url: baseURL.appending(path: "rest/v1/rpc/\(name)"))
        request.httpMethod = "POST"
        authorized(&request)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: params)
        let (data, response) = try await Self.librarySession.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SupabaseError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw SupabaseError.http(http.statusCode) }
        return try JSONDecoder().decode([LineHitRow].self, from: data)
    }

    /// Kiku-style search: every published clip's transcript, not just what's on the phone.
    func searchLines(query: String, maxResults: Int = 24) async throws -> [SearchHit] {
        let rows = try await rpcLineHits("search_clip_lines", [
            "p_query": query,
            "p_max_results": maxResults,
            "p_offset": 0,
        ])
        return rows.compactMap { row in
            guard let clip = row.clip?.clip, !clip.lines.isEmpty else { return nil }
            return SearchHit(clip: clip, lineIndex: row.lineIndex)
        }
    }

    /// Grammar-pattern search: lines that use e.g. 〜たい or 〜てしまう.
    func searchGrammar(patternId: String, maxResults: Int = 24) async throws -> [SearchHit] {
        let rows = try await rpcLineHits("search_grammar_lines", [
            "p_pattern_id": patternId,
            "p_max_results": maxResults,
            "p_offset": 0,
        ])
        return rows.compactMap { row in
            guard let clip = row.clip?.clip, !clip.lines.isEmpty else { return nil }
            return SearchHit(clip: clip, lineIndex: row.lineIndex)
        }
    }

    /// GET /rest/v1/clips?published=eq.true&select=*
    func fetchPublishedClips() async throws -> [(clip: Clip, json: Data)] {
        guard let baseURL else { throw SupabaseError.notConfigured }
        guard var components = URLComponents(url: baseURL.appending(path: "rest/v1/clips"), resolvingAgainstBaseURL: false) else {
            throw SupabaseError.invalidResponse
        }
        components.queryItems = [URLQueryItem(name: "published", value: "eq.true"), URLQueryItem(name: "select", value: "*")]
        guard let url = components.url else { throw SupabaseError.invalidResponse }
        var request = URLRequest(url: url)
        authorized(&request)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await Self.librarySession.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SupabaseError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw SupabaseError.http(http.statusCode) }
        let rows = try JSONDecoder().decode([LossyRow].self, from: data)
        let encoder = JSONEncoder()
        return rows.compactMap { row -> (clip: Clip, json: Data)? in
            guard let clip = row.value?.clip, !clip.lines.isEmpty, let json = try? encoder.encode(clip) else { return nil }
            return (clip, json)
        }
    }
}

/// A row of the Supabase `clips` table.
nonisolated struct ClipRow: Decodable, Sendable {
    var id: String
    var videoId: String?
    var title: String
    var channelName: String?
    var category: String?
    var difficulty: String?
    var sourceStartSec: Double?
    var durationSec: Double?
    var lines: [Line]
    var published: Bool?
    var channelAvatarColor: String?
    var thumbnailGradient: [String]?
    var videoOrientation: String?

    enum CodingKeys: String, CodingKey {
        case id, title, category, difficulty, lines, published
        case videoId = "video_id"
        case channelName = "channel_name"
        case sourceStartSec = "source_start_sec"
        case durationSec = "duration_sec"
        case channelAvatarColor = "channel_avatar_color"
        case thumbnailGradient = "thumbnail_gradient"
        case videoOrientation = "video_orientation"
    }

    var clip: Clip {
        let palette: [[String]] = [["#0B1030", "#2B2F7A", "#F29E4C"], ["#10261A", "#2E7D4F", "#F6E27F"], ["#2B1405", "#9C3D10", "#F2B134"]]
        let index = abs(id.hashValue) % palette.count
        return Clip(
            id: id,
            videoId: videoId ?? "PLACEHOLDER_remote",
            title: title,
            channelName: channelName ?? "Jojo",
            channelAvatarColor: channelAvatarColor ?? "#8E5C9C",
            category: category ?? ClipCategory.drama.rawValue,
            difficulty: difficulty ?? Difficulty.beginner.rawValue,
            sourceStartSec: sourceStartSec ?? 0,
            durationSec: durationSec ?? (lines.last?.end ?? 20) + 1.5,
            lines: lines,
            thumbnailGradient: thumbnailGradient ?? palette[index],
            videoOrientation: videoOrientation
        )
    }
}

/// One row of a search RPC: the clip plus which transcript line matched.
nonisolated struct LineHitRow: Decodable, Sendable {
    let clip: ClipRow?
    let lineIndex: Int

    enum CodingKeys: String, CodingKey {
        case clip = "clip_row"
        case lineIndex = "line_index"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        clip = try? c.decode(ClipRow.self, forKey: .clip)
        lineIndex = (try? c.decodeIfPresent(Int.self, forKey: .lineIndex)) ?? 0
    }
}

/// Skips malformed rows instead of failing the whole library fetch.
nonisolated struct LossyRow: Decodable, Sendable {
    let value: ClipRow?
    init(from decoder: Decoder) throws {
        value = try? ClipRow(from: decoder)
    }
}

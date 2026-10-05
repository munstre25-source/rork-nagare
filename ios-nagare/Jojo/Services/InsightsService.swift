import Foundation

/// Client for acquisition + feedback Edge Functions. Failures are silent — never block the UI.
actor InsightsService {
    static let shared = InsightsService()

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    func submitAcquisition(source: String, detail: String?, appUserId: String) async {
        var body: [String: Any] = ["source": source]
        if let detail {
            let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { body["source_detail"] = trimmed }
        }
        _ = await send(method: "POST", path: "functions/v1/submit-acquisition", appUserId: appUserId, body: body)
    }

    func submitFeedback(
        enjoyed: Bool?,
        category: String?,
        message: String,
        appUserId: String
    ) async -> Bool {
        var body: [String: Any] = ["message": message]
        if let enjoyed { body["enjoyed"] = enjoyed }
        if let category, !category.isEmpty { body["category"] = category }
        return await send(method: "POST", path: "functions/v1/submit-feedback", appUserId: appUserId, body: body) != nil
    }

    func loadFeedbackBoard(appUserId: String) async -> [FeedbackPost]? {
        guard let data = await send(method: "GET", path: "functions/v1/feedback-board", appUserId: appUserId, body: nil) else {
            return nil
        }
        return try? Self.decoder.decode(FeedbackBoardList.self, from: data).posts
    }

    func loadFeedbackPost(id: Int, appUserId: String) async -> FeedbackPostDetail? {
        guard let data = await send(
            method: "GET",
            path: "functions/v1/feedback-board",
            appUserId: appUserId,
            query: [URLQueryItem(name: "id", value: String(id))],
            body: nil
        ) else { return nil }
        return try? Self.decoder.decode(FeedbackPostDetail.self, from: data)
    }

    func createFeedbackPost(category: String, title: String, body: String, appUserId: String) async -> FeedbackPost? {
        guard let data = await send(
            method: "POST",
            path: "functions/v1/feedback-board",
            appUserId: appUserId,
            body: ["action": "create", "category": category, "title": title, "body": body]
        ) else { return nil }
        return try? Self.decoder.decode(FeedbackPostEnvelope.self, from: data).post
    }

    func toggleFeedbackVote(id: Int, appUserId: String) async -> (count: Int, voted: Bool)? {
        guard let data = await send(
            method: "POST",
            path: "functions/v1/feedback-board",
            appUserId: appUserId,
            body: ["action": "vote", "id": id]
        ) else { return nil }
        guard let payload = try? Self.decoder.decode(FeedbackVoteResult.self, from: data) else { return nil }
        return (payload.voteCount, payload.voted)
    }

    func addFeedbackComment(postId: Int, body: String, appUserId: String) async -> (comment: FeedbackComment, count: Int)? {
        guard let data = await send(
            method: "POST",
            path: "functions/v1/feedback-board",
            appUserId: appUserId,
            body: ["action": "comment", "id": postId, "body": body]
        ) else { return nil }
        guard let payload = try? Self.decoder.decode(FeedbackCommentResult.self, from: data) else { return nil }
        return (payload.comment, payload.commentCount)
    }

    func loadDirectMessages(appUserId: String) async -> [DirectMessage]? {
        guard let data = await send(method: "GET", path: "functions/v1/direct-messages", appUserId: appUserId, body: nil) else {
            return nil
        }
        return try? Self.decoder.decode(DirectMessageList.self, from: data).messages
    }

    func sendDirectMessage(body: String, appUserId: String) async -> DirectMessage? {
        guard let data = await send(
            method: "POST",
            path: "functions/v1/direct-messages",
            appUserId: appUserId,
            body: ["body": body]
        ) else { return nil }
        return try? Self.decoder.decode(DirectMessageEnvelope.self, from: data).message
    }

    private func send(
        method: String,
        path: String,
        appUserId: String,
        query: [URLQueryItem] = [],
        body: [String: Any]?
    ) async -> Data? {
        guard Secrets.isSupabaseConfigured,
              let base = URL(string: Secrets.supabaseURL) else { return nil }
        guard var components = URLComponents(url: base.appending(path: path), resolvingAgainstBaseURL: false) else {
            return nil
        }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(Secrets.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(Secrets.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(appUserId, forHTTPHeaderField: "x-app-user-id")
        do {
            if let body {
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
            }
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
            return data
        } catch {
            return nil
        }
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

struct FeedbackPost: Identifiable, Codable, Hashable, Sendable {
    var id: Int
    var category: String
    var title: String
    var body: String
    var voteCount: Int
    var commentCount: Int
    var createdAt: Date
    var voted: Bool
}

struct FeedbackComment: Identifiable, Codable, Hashable, Sendable {
    var id: Int
    var body: String
    var createdAt: Date
}

struct FeedbackPostDetail: Codable, Sendable {
    var post: FeedbackPost
    var comments: [FeedbackComment]
}

private struct FeedbackBoardList: Codable {
    var posts: [FeedbackPost]
}

private struct FeedbackPostEnvelope: Codable {
    var post: FeedbackPost
}

private struct FeedbackVoteResult: Codable {
    var voteCount: Int
    var voted: Bool
}

private struct FeedbackCommentResult: Codable {
    var comment: FeedbackComment
    var commentCount: Int
}

struct DirectMessage: Identifiable, Codable, Hashable, Sendable {
    var id: Int
    var sender: String
    var body: String
    var createdAt: Date
}

private struct DirectMessageList: Codable {
    var messages: [DirectMessage]
}

private struct DirectMessageEnvelope: Codable {
    var message: DirectMessage
}

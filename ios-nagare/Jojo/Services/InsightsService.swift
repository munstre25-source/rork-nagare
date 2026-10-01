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
        _ = await post(path: "functions/v1/submit-acquisition", appUserId: appUserId, body: body)
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
        return await post(path: "functions/v1/submit-feedback", appUserId: appUserId, body: body)
    }

    @discardableResult
    private func post(path: String, appUserId: String, body: [String: Any]) async -> Bool {
        guard Secrets.isSupabaseConfigured,
              let base = URL(string: Secrets.supabaseURL) else { return false }
        var request = URLRequest(url: base.appending(path: path))
        request.httpMethod = "POST"
        request.setValue(Secrets.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(Secrets.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(appUserId, forHTTPHeaderField: "x-app-user-id")
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return (200..<300).contains(http.statusCode)
        } catch {
            return false
        }
    }
}

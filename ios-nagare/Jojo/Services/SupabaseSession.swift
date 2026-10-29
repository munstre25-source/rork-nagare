import Foundation
import Security

/// A Supabase Auth session. Anonymous: Jojo has no visible accounts, so the learner is an
/// anonymous user whose id owns their synced vocab, practice history and video requests.
nonisolated struct AuthSession: Codable, Sendable, Equatable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var userId: String

    var isFresh: Bool { expiresAt.timeIntervalSinceNow > 60 }
}

/// Keychain storage for the session. `AfterFirstUnlockThisDeviceOnly`: survives app
/// restarts, never syncs to iCloud or migrates to another device.
nonisolated enum SessionKeychain {
    private static let service = "com.socialreporthq.jojo.supabase"
    private static let account = "session"

    static func load() -> AuthSession? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(AuthSession.self, from: data)
    }

    static func save(_ session: AuthSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let update: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        if SecItemUpdate(base as CFDictionary, update as CFDictionary) == errSecItemNotFound {
            SecItemAdd(base.merging(update) { $1 } as CFDictionary, nil)
        }
    }

    static func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

nonisolated enum AuthError: Error, Equatable {
    case notConfigured
    case offline
    case rejected(Int)
    case invalidResponse
}

/// Creates, refreshes and persists the anonymous session. One actor so concurrent callers
/// share a single in-flight signup/refresh instead of racing for tokens.
actor SupabaseAuth {
    static let shared = SupabaseAuth(api: .shared)

    private let api: SupabaseAPI
    private var cached: AuthSession?
    private var inFlight: Task<AuthSession, Error>?

    init(api: SupabaseAPI) {
        self.api = api
        self.cached = SessionKeychain.load()
    }

    var currentUserId: String? { cached?.userId }

    /// A valid access token, signing up anonymously on first use and refreshing when stale.
    func validSession() async throws -> AuthSession {
        if let cached, cached.isFresh { return cached }
        if let inFlight { return try await inFlight.value }
        let previous = cached
        let task = Task { [api] () throws -> AuthSession in
            if let previous {
                do {
                    return try await api.refreshSession(refreshToken: previous.refreshToken)
                } catch AuthError.rejected(let status) where (400..<500).contains(status) {
                    // Refresh token revoked or expired: the old anonymous user is unreachable.
                    return try await api.signUpAnonymously()
                }
            }
            return try await api.signUpAnonymously()
        }
        inFlight = task
        defer { inFlight = nil }
        let session = try await task.value
        cached = session
        SessionKeychain.save(session)
        return session
    }

    /// The current session if one already exists (refreshed when stale), never signing up.
    /// Analytics uses this so measuring the app never creates a backend user by itself.
    func existingSession() async -> AuthSession? {
        guard cached != nil else { return nil }
        return try? await validSession()
    }

    /// Forget the session (after server-side deletion). The next call creates a new user.
    func reset() {
        cached = nil
        inFlight?.cancel()
        inFlight = nil
        SessionKeychain.clear()
    }
}

extension SupabaseAPI {
    private static let authSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    /// POST /auth/v1/signup with an empty body creates an anonymous user.
    func signUpAnonymously() async throws -> AuthSession {
        try await authRequest(path: "auth/v1/signup", query: nil, body: [:])
    }

    /// POST /auth/v1/token?grant_type=refresh_token
    func refreshSession(refreshToken: String) async throws -> AuthSession {
        try await authRequest(
            path: "auth/v1/token",
            query: [URLQueryItem(name: "grant_type", value: "refresh_token")],
            body: ["refresh_token": refreshToken]
        )
    }

    private func authRequest(path: String, query: [URLQueryItem]?, body: [String: Any]) async throws -> AuthSession {
        guard let baseURL else { throw AuthError.notConfigured }
        guard var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false) else {
            throw AuthError.invalidResponse
        }
        components.queryItems = query
        guard let url = components.url else { throw AuthError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await Self.authSession.data(for: request)
        } catch {
            throw AuthError.offline
        }
        guard let http = response as? HTTPURLResponse else { throw AuthError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw AuthError.rejected(http.statusCode) }
        let payload = try JSONDecoder().decode(AuthPayload.self, from: data)
        let expiry = payload.expiresAt.map { Date(timeIntervalSince1970: $0) }
            ?? Date().addingTimeInterval(payload.expiresIn ?? 3600)
        return AuthSession(
            accessToken: payload.accessToken,
            refreshToken: payload.refreshToken,
            expiresAt: expiry,
            userId: payload.user.id
        )
    }
}

private nonisolated struct AuthPayload: Decodable {
    struct User: Decodable { let id: String }
    let accessToken: String
    let refreshToken: String
    let expiresIn: Double?
    let expiresAt: Double?
    let user: User

    enum CodingKeys: String, CodingKey {
        case user
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case expiresAt = "expires_at"
    }
}

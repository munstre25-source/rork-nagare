import Foundation

/// A cache entry the caller should persist into SwiftData.
nonisolated struct CachePayload: Sendable {
    let key: String
    let kind: String
    let data: Data
}

nonisolated struct LookupOutcome: Sendable {
    let explanation: WordExplanation
    let newCache: CachePayload?
}

nonisolated struct ContextOutcome: Sendable {
    let context: ContextExplanation
    let newCache: CachePayload?
}

nonisolated enum AskOutcome: Sendable, Equatable {
    case answer(String)
    case failure(String)
}

/// Stats for measuring live-call cost per user per day.
nonisolated struct LiveCallStats: Sendable {
    let todayCount: Int
    let totalCount: Int
    let averageMs: Int
}

/// Resolves word explanations: seed/local dictionary → local cache → Supabase Edge Function (12s) → static fallback.
/// Never throws and never surfaces errors to the UI.
actor WordExplainService {
    private let api: SupabaseAPI
    private let lexicon: LocalLexicon
    private var memoryCache: [String: Data] = [:]
    private static let logKey = "nagare.explain.calllog"

    init(api: SupabaseAPI, lexicon: LocalLexicon) {
        self.api = api
        self.lexicon = lexicon
    }

    func preload(_ entries: [String: Data]) {
        memoryCache.merge(entries) { current, _ in current }
    }

    static func lookupKey(for token: Token, sentence: String) -> String {
        // Match the server key: include the sentence whenever one is available so
        // in-context senses stay consistent and we don't pay twice for the same pair.
        let word = token.dictionaryForm
        if sentence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "lookup|\(word)"
        }
        return "lookup|\(word)|\(JapaneseText.sentenceHash(sentence))"
    }

    static func contextKey(for token: Token, sentence: String) -> String {
        "context|\(token.dictionaryForm)|\(JapaneseText.sentenceHash(sentence))"
    }

    func lookup(token: Token, sentence: String, appUserId: String) async -> LookupOutcome {
        if let instant = lexicon.instantExplanation(for: token), instant.hasMeaning {
            return LookupOutcome(explanation: instant, newCache: nil)
        }
        let key = Self.lookupKey(for: token, sentence: sentence)
        if let cached = memoryCache[key], let decoded = Self.decodeLookup(cached, token: token, source: .cache) {
            return LookupOutcome(explanation: decoded, newCache: nil)
        }
        guard api.isConfigured else {
            return LookupOutcome(explanation: .fallback(for: token), newCache: nil)
        }
        let started = Date()
        do {
            let data = try await api.explainWord(kind: "lookup", word: token.dictionaryForm, sentence: sentence, appUserId: appUserId)
            logCall(started: started, status: "ok")
            guard let decoded = Self.decodeLookup(data, token: token, source: .live) else {
                return LookupOutcome(explanation: .fallback(for: token), newCache: nil)
            }
            memoryCache[key] = data
            return LookupOutcome(explanation: decoded, newCache: CachePayload(key: key, kind: "lookup", data: data))
        } catch {
            logCall(started: started, status: statusLabel(error))
            return LookupOutcome(explanation: .fallback(for: token), newCache: nil)
        }
    }

    func context(token: Token, sentence: String, appUserId: String, fallback: ContextExplanation) async -> ContextOutcome {
        let key = Self.contextKey(for: token, sentence: sentence)
        if let cached = memoryCache[key],
           let decoded = try? JSONDecoder().decode(ContextExplanation.self, from: cached),
           decoded.examples.contains(where: {
               $0.components(separatedBy: " — ").first?.trimmingCharacters(in: .whitespacesAndNewlines) != sentence.trimmingCharacters(in: .whitespacesAndNewlines)
           }) {
            return ContextOutcome(context: decoded, newCache: nil)
        }
        guard api.isConfigured else { return ContextOutcome(context: fallback, newCache: nil) }
        let started = Date()
        do {
            let data = try await api.explainWord(kind: "context", word: token.dictionaryForm, sentence: sentence, appUserId: appUserId)
            logCall(started: started, status: "ok")
            guard let decoded = try? JSONDecoder().decode(ContextExplanation.self, from: data),
                  !decoded.contextualExplanation.isEmpty else {
                return ContextOutcome(context: fallback, newCache: nil)
            }
            memoryCache[key] = data
            return ContextOutcome(context: decoded, newCache: CachePayload(key: key, kind: "context", data: data))
        } catch {
            logCall(started: started, status: statusLabel(error))
            return ContextOutcome(context: fallback, newCache: nil)
        }
    }

    /// Ask Jojo: one free-form question about a word in its sentence. Failures carry
    /// actionable learner-facing feedback rather than disappearing behind a generic retry.
    func ask(token: Token, sentence: String, question: String, appUserId: String) async -> AskOutcome {
        let normalized = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return .failure("Type a question for Jojo first.") }
        guard api.isConfigured else {
            return .failure("Ask Jojo isn't configured in this build yet.")
        }
        let key = "ask|\(token.dictionaryForm)|\(JapaneseText.sentenceHash(sentence))|\(normalized.lowercased())"
        if let cached = memoryCache[key], let answer = Self.decodeAnswer(cached) { return .answer(answer) }
        let started = Date()
        do {
            let data = try await api.explainWord(kind: "ask", word: token.dictionaryForm, sentence: sentence,
                                                 appUserId: appUserId, question: String(normalized.prefix(200)))
            logCall(started: started, status: "ok")
            guard let answer = Self.decodeAnswer(data) else {
                return .failure("Jojo returned an empty explanation. Please try that question again.")
            }
            memoryCache[key] = data
            return .answer(answer)
        } catch {
            logCall(started: started, status: statusLabel(error))
            return .failure(Self.askFailureMessage(error))
        }
    }

    nonisolated private static func decodeAnswer(_ data: Data) -> String? {
        struct Payload: Decodable { let answer: String }
        guard let answer = try? JSONDecoder().decode(Payload.self, from: data).answer
            .trimmingCharacters(in: .whitespacesAndNewlines), !answer.isEmpty else { return nil }
        return answer
    }

    nonisolated static func decodeLookup(_ data: Data, token: Token, source: WordExplanation.Source) -> WordExplanation? {
        guard let response = try? JSONDecoder().decode(LookupResponse.self, from: data) else { return nil }
        let definitions = WordExplanation.meaningfulDefinitions(response.definitions ?? [])
        let jaDefinitions = WordExplanation.meaningfulDefinitions(response.jaDefinitions ?? [])
        guard !definitions.isEmpty || !jaDefinitions.isEmpty else { return nil }
        return WordExplanation(
            word: token.surface,
            readings: response.readings?.isEmpty == false ? (response.readings ?? []) : token.allReadings,
            romaji: response.romaji ?? token.romaji,
            pos: response.pos ?? token.pos,
            conjugationClass: response.conjugationClass ?? token.conjugationClass,
            jlpt: token.jlpt,
            definitions: definitions.isEmpty ? token.definitions : definitions,
            jaDefinitions: jaDefinitions.isEmpty ? token.jaDefinitions : jaDefinitions,
            formalityNote: response.formalityNote ?? token.formality,
            source: source
        )
    }

    nonisolated static func askFailureMessage(_ error: Error) -> String {
        let code: Int?
        let detail: String?
        switch error {
        case SupabaseError.function(let status, let message):
            code = status
            detail = message
        case SupabaseError.http(let status):
            code = status
            detail = nil
        default:
            code = nil
            detail = nil
        }
        if code == 403 || detail?.localizedCaseInsensitiveContains("subscription") == true {
            return "Ask Jojo needs an active Jojo Pro subscription."
        }
        if code == 429 {
            return "Jojo has reached the explanation limit for now. Please try again a little later."
        }
        if let urlError = error as? URLError, urlError.code == .timedOut {
            return "Jojo took too long to reply. Please try again."
        }
        if let code, code >= 500 {
            return "Jojo's AI is temporarily unavailable. Please try again shortly."
        }
        return "Jojo couldn't connect. Check your connection and try again."
    }

    private func statusLabel(_ error: Error) -> String {
        if case SupabaseError.http(let code) = error { return "http\(code)" }
        if case SupabaseError.function(let code, _) = error { return "http\(code)" }
        if let urlError = error as? URLError { return urlError.code == .timedOut ? "timeout" : "network" }
        return "error"
    }

    private func logCall(started: Date, status: String) {
        let ms = Int(Date().timeIntervalSince(started) * 1000)
        let defaults = UserDefaults.standard
        var log = defaults.array(forKey: Self.logKey) as? [[String: String]] ?? []
        log.append(["ts": String(Date().timeIntervalSince1970), "ms": String(ms), "status": status])
        if log.count > 1000 { log.removeFirst(log.count - 1000) }
        defaults.set(log, forKey: Self.logKey)
        print("[Explain] live call \(status) in \(ms)ms")
    }

    static func stats() -> LiveCallStats {
        let log = UserDefaults.standard.array(forKey: logKey) as? [[String: String]] ?? []
        let startOfDay = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970
        let today = log.filter { (Double($0["ts"] ?? "") ?? 0) >= startOfDay }
        let latencies = log.compactMap { Int($0["ms"] ?? "") }
        let average = latencies.isEmpty ? 0 : latencies.reduce(0, +) / latencies.count
        return LiveCallStats(todayCount: today.count, totalCount: log.count, averageMs: average)
    }
}

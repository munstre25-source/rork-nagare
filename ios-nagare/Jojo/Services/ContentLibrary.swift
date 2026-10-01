import Foundation

/// Loads bundled seed content (clips, dictionary, seed vocab) from JSON resources.
/// Regenerate the JSON with `python3 Tools/generate_seed.py`.
nonisolated enum ContentLibrary {
    static func loadSeedClips() -> [Clip] {
        decode([Clip].self, resource: "SeedClips") ?? []
    }

    static func loadDictionary() -> [String: DictionaryEntry] {
        decode([String: DictionaryEntry].self, resource: "Dictionary") ?? [:]
    }

    static func loadSeedVocab() -> [SeedVocabEntry] {
        decode([SeedVocabEntry].self, resource: "SeedVocab") ?? []
    }

    private static func decode<T: Decodable>(_ type: T.Type, resource: String) -> T? {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "json") else {
            print("[Content] missing resource \(resource).json")
            return nil
        }
        do {
            return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
        } catch {
            print("[Content] failed to decode \(resource).json: \(error)")
            return nil
        }
    }
}

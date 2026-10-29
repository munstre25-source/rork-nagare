import Foundation
import SwiftData

/// Mirrors saved words to `user_vocab` under the learner's anonymous Supabase user.
/// The device is the source of truth: changes are pushed in small debounced batches,
/// deletions are queued until the server confirms them, and a pull only adds words the
/// device doesn't have (e.g. after a reinstall that kept the Keychain session).
@MainActor
final class VocabSync {
    private let api: UserDataAPI
    private var pendingUpserts: [String: RemoteVocabRow] = [:]
    private var flushTask: Task<Void, Never>?
    private var isFlushing = false
    private(set) var isSuspended = false

    private static let pendingDeletesKey = "jojo.vocab.pendingDeletes"
    private static let needsFullPushKey = "jojo.vocab.needsFullPush"
    private static let syncedUserKey = "jojo.vocab.syncedUser"

    init(api: UserDataAPI = .shared) {
        self.api = api
    }

    var isAvailable: Bool { api.isConfigured }

    // MARK: Change capture

    /// Queues the current state of these words for upload.
    func noteChanged(_ words: [SavedWord]) {
        guard isAvailable, !isSuspended else { return }
        for word in words {
            guard let row = Self.row(for: word) else { continue }
            pendingUpserts[word.key] = row
            removePendingDelete(word.key)
        }
        scheduleFlush()
    }

    /// Queues server deletion for words no longer on the device.
    func noteDeleted(keys: [String]) {
        guard isAvailable, !isSuspended, !keys.isEmpty else { return }
        var deletes = Set(UserDefaults.standard.stringArray(forKey: Self.pendingDeletesKey) ?? [])
        for key in keys {
            pendingUpserts[key] = nil
            deletes.insert(key)
        }
        UserDefaults.standard.set(Array(deletes), forKey: Self.pendingDeletesKey)
        scheduleFlush()
    }

    /// Stop capturing while all local data is wiped; the server copy is deleted separately.
    func suspend() {
        isSuspended = true
        flushTask?.cancel()
        flushTask = nil
        pendingUpserts = [:]
    }

    func resume() { isSuspended = false }

    /// Forget every local sync marker (after account data deletion).
    func resetMarkers() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Self.pendingDeletesKey)
        defaults.removeObject(forKey: Self.needsFullPushKey)
        defaults.removeObject(forKey: Self.syncedUserKey)
    }

    // MARK: Launch sync

    /// Push everything once per anonymous user (and after a failed batch), then pull-merge.
    /// `insertMissing` receives server rows whose key the device doesn't have.
    func launchSync(allWords: @escaping () -> [SavedWord], insertMissing: @escaping ([RemoteVocabRow]) -> Void) {
        guard isAvailable, !isSuspended else { return }
        Task { [weak self] in
            guard let self else { return }
            guard let userId = try? await SupabaseAuth.shared.validSession().userId else { return }
            let defaults = UserDefaults.standard
            await self.flushDeletes()
            do {
                let remote = try await self.api.fetchVocab()
                let localKeys = Set(allWords().map(\.key))
                let pendingDeletes = Set(defaults.stringArray(forKey: Self.pendingDeletesKey) ?? [])
                let missing = remote.filter { row in
                    let key = SavedWord.makeKey(surface: row.term, reading: row.reading)
                    return !localKeys.contains(key) && !pendingDeletes.contains(key)
                }
                if !missing.isEmpty { insertMissing(missing) }
                let needsFull = defaults.bool(forKey: Self.needsFullPushKey)
                    || defaults.string(forKey: Self.syncedUserKey) != userId
                if needsFull {
                    let rows = allWords().compactMap(Self.row(for:))
                    for batch in stride(from: 0, to: rows.count, by: 200) {
                        try await self.api.upsertVocab(Array(rows[batch..<min(batch + 200, rows.count)]))
                    }
                    defaults.set(userId, forKey: Self.syncedUserKey)
                    defaults.set(false, forKey: Self.needsFullPushKey)
                }
            } catch {
                defaults.set(true, forKey: Self.needsFullPushKey)
            }
        }
    }

    // MARK: Flushing

    private func scheduleFlush() {
        flushTask?.cancel()
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await self?.flush()
        }
    }

    private func flush() async {
        guard !isFlushing, !isSuspended else { return }
        isFlushing = true
        defer { isFlushing = false }
        let batch = Array(pendingUpserts.values)
        pendingUpserts = [:]
        if !batch.isEmpty {
            do {
                try await api.upsertVocab(batch)
            } catch {
                // Retry everything on next launch rather than holding rows in memory.
                UserDefaults.standard.set(true, forKey: Self.needsFullPushKey)
            }
        }
        await flushDeletes()
    }

    private func flushDeletes() async {
        let keys = UserDefaults.standard.stringArray(forKey: Self.pendingDeletesKey) ?? []
        for key in keys {
            guard let (term, reading) = Self.split(key) else {
                removePendingDelete(key)
                continue
            }
            do {
                try await api.deleteVocab(term: term, reading: reading)
                removePendingDelete(key)
            } catch {
                return
            }
        }
    }

    private func removePendingDelete(_ key: String) {
        var deletes = UserDefaults.standard.stringArray(forKey: Self.pendingDeletesKey) ?? []
        guard deletes.contains(key) else { return }
        deletes.removeAll { $0 == key }
        UserDefaults.standard.set(deletes, forKey: Self.pendingDeletesKey)
    }

    // MARK: Mapping

    nonisolated static func split(_ key: String) -> (String, String)? {
        guard let bar = key.firstIndex(of: "|") else { return nil }
        let term = String(key[..<bar])
        let reading = String(key[key.index(after: bar)...])
        guard !term.isEmpty else { return nil }
        return (term, reading)
    }

    /// Fits a saved word into the table's constraints; nil when it can't be represented.
    static func row(for word: SavedWord) -> RemoteVocabRow? {
        guard let (term, reading) = split(word.key), term.count <= 64, reading.count <= 64 else { return nil }
        let jlpt = word.jlpt?.uppercased()
        return RemoteVocabRow(
            userId: nil,
            term: term,
            reading: reading,
            surface: word.contextSurface.isEmpty ? nil : String(word.contextSurface.prefix(64)),
            romaji: word.romaji.isEmpty ? nil : String(word.romaji.prefix(128)),
            pos: word.pos.isEmpty ? nil : String(word.pos.prefix(40)),
            jlpt: ["N5", "N4", "N3", "N2", "N1"].contains(jlpt ?? "") ? jlpt : nil,
            definitions: Array(word.definitions.prefix(12)).map { String($0.prefix(300)) },
            contextSentence: word.contextSentence.isEmpty ? nil : String(word.contextSentence.prefix(400)),
            contextNote: word.contextNote.isEmpty ? nil : String(word.contextNote.prefix(600)),
            clipId: word.contextClipId.isEmpty ? nil : String(word.contextClipId.prefix(120)),
            lineIndex: word.contextClipId.isEmpty ? nil : max(0, word.contextLineIndex),
            encounterCount: max(0, word.occurrenceCount),
            srsState: word.state.rawValue
        )
    }
}

import Foundation
import Observation

/// The learner's "bring your own video" requests. Submits links, polls the shared server
/// job while it runs, and keeps finished lessons on device so they open offline.
@Observable
@MainActor
final class ImmersionStore {
    private(set) var jobs: [ImmersionJob] = []
    private(set) var isSubmitting = false
    private(set) var lastError: String?
    /// Finished lessons, newest first.
    var readyClips: [Clip] { jobs.compactMap { $0.phase == .ready ? $0.clip : nil } }
    var activeCount: Int { jobs.filter(\.isActive).count }

    /// Called when the set of finished lessons changes, so the library can index them.
    @ObservationIgnored var onClipsChanged: (([Clip]) -> Void)?

    @ObservationIgnored private let api: UserDataAPI
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var hiddenIds: Set<String>
    @ObservationIgnored private let fileURL: URL?

    private static let hiddenKey = "jojo.immersion.hidden"

    init(api: UserDataAPI = .shared) {
        self.api = api
        self.hiddenIds = Set(UserDefaults.standard.stringArray(forKey: Self.hiddenKey) ?? [])
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        self.fileURL = dir?.appending(path: "immersion-jobs.json")
        loadCache()
    }

    var isAvailable: Bool { api.isConfigured }

    // MARK: Actions

    /// Sends a YouTube link to the pipeline. Returns true when the request was accepted.
    @discardableResult
    func submit(_ link: String) async -> Bool {
        lastError = nil
        guard YouTubeLink.videoId(from: link) != nil else {
            lastError = "That doesn't look like a YouTube video link."
            Haptics.warning()
            return false
        }
        guard api.isConfigured else {
            lastError = ImmersionAPIError.notConfigured.message
            return false
        }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let job = try await api.submitVideo(link)
            hiddenIds.remove(job.id)
            persistHidden()
            upsert(job)
            Haptics.success()
            track("immersion_submitted", props: ["status": job.status])
            startPolling()
            return true
        } catch let error as ImmersionAPIError {
            lastError = error.message
            Haptics.warning()
            track("immersion_submit_failed", props: ["reason": "\(error)"])
            return false
        } catch {
            lastError = "Something went wrong. Please try again."
            Haptics.warning()
            return false
        }
    }

    /// Manual retry. The server decides whether a reset is allowed yet.
    func retry(_ job: ImmersionJob) async {
        guard let url = job.watchURL?.absoluteString else { return }
        await submit(url)
    }

    /// Hides a request from this device. The shared server job is left for other learners.
    func hide(_ job: ImmersionJob) {
        hiddenIds.insert(job.id)
        persistHidden()
        jobs.removeAll { $0.id == job.id }
        saveCache()
        onClipsChanged?(readyClips)
    }

    func clearError() { lastError = nil }

    /// Pulls the latest state for every request. Safe to call often.
    func refresh() async {
        guard api.isConfigured else { return }
        do {
            let fresh = try await api.fetchJobs()
            let visible = fresh.filter { !hiddenIds.contains($0.id) }
            // Keep a cached lesson if the server row lost its clip (e.g. clip row replaced mid-run).
            jobs = visible.map { job in
                guard job.clip == nil, let old = jobs.first(where: { $0.id == job.id }), let clip = old.clip,
                      job.status == "succeeded", job.clipId == clip.id else { return job }
                var merged = job
                merged.clip = clip
                return merged
            }
            saveCache()
            onClipsChanged?(readyClips)
            if jobs.contains(where: \.isActive) { startPolling() }
        } catch {
            // Offline or transient: keep the cached list; polling retries.
        }
    }

    /// Polls while anything is in flight: every 4s for two minutes, then every 15s.
    func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            var elapsed: Double = 0
            while !Task.isCancelled {
                let interval: Double = elapsed < 120 ? 4 : 15
                try? await Task.sleep(for: .seconds(interval))
                elapsed += interval
                guard let self, !Task.isCancelled else { return }
                await self.pollOnce()
                if !self.jobs.contains(where: \.isActive) { break }
            }
            self?.pollTask = nil
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// Wipes local state after "Delete my data".
    func reset() {
        stopPolling()
        jobs = []
        hiddenIds = []
        lastError = nil
        UserDefaults.standard.removeObject(forKey: Self.hiddenKey)
        if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
        onClipsChanged?([])
    }

    // MARK: Internals

    private func pollOnce() async {
        let active = jobs.filter(\.isActive).map(\.id)
        guard !active.isEmpty else { return }
        do {
            let fresh = try await api.fetchJobs(ids: active)
            var changed = false
            for job in fresh where !hiddenIds.contains(job.id) {
                let before = jobs.first(where: { $0.id == job.id })
                if before != job { changed = true }
                if before?.phase != .ready, job.phase == .ready {
                    Haptics.success()
                    track("immersion_ready", props: ["timing": job.timingMode ?? "unknown"])
                }
                upsert(job, persist: false)
            }
            if changed {
                saveCache()
                onClipsChanged?(readyClips)
            }
        } catch {
            // Keep polling; the next tick retries.
        }
    }

    private func upsert(_ job: ImmersionJob, persist: Bool = true) {
        if let index = jobs.firstIndex(where: { $0.id == job.id }) {
            jobs[index] = job
        } else {
            jobs.insert(job, at: 0)
        }
        if persist {
            saveCache()
            onClipsChanged?(readyClips)
        }
    }

    private func loadCache() {
        guard let fileURL, let data = try? Data(contentsOf: fileURL),
              let cached = try? JSONDecoder().decode([ImmersionJob].self, from: data) else { return }
        jobs = cached.filter { !hiddenIds.contains($0.id) }
    }

    private func saveCache() {
        guard let fileURL else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(jobs).write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            print("[Immersion] cache write failed: \(error.localizedDescription)")
        }
    }

    private func persistHidden() {
        UserDefaults.standard.set(Array(hiddenIds), forKey: Self.hiddenKey)
    }
}

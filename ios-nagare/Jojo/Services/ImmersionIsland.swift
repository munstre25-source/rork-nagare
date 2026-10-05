import ActivityKit
import Foundation

/// Keeps the line being heard in the Dynamic Island while For You is playing.
enum ImmersionIsland {
    @MainActor private static var activity: Activity<ImmersionAttributes>?
    @MainActor private static var lastKey = ""

    /// Safe to call from the playback clock.
    static func note(
        clip: Clip,
        lineIndex: Int,
        tokenIndex: Int?,
        minutesLeft: Int,
        goalProgress: Double,
        accent: String
    ) {
        Task { @MainActor in
            guard let line = clip.lines[safe: lineIndex] else { return }
            let spoken = tokenIndex.flatMap { line.tokens[safe: $0] }
            let word = spoken ?? line.tokens.first { $0.tappable && !$0.isPunctuation }
            let surface = word?.surface ?? line.text
            guard !surface.isEmpty else { return }
            let reading = word?.reading ?? word?.baseReading ?? ""
            let state = ImmersionAttributes.ContentState(
                surface: surface,
                reading: reading == surface ? "" : reading,
                line: line.text,
                translation: line.translation,
                minutesLeft: minutesLeft,
                goalProgress: min(max(goalProgress, 0), 1),
                accent: accent
            )
            let key = "\(clip.id)|\(lineIndex)|\(surface)|\(minutesLeft)|\(accent)"
            guard key != lastKey else { return }
            lastKey = key
            await push(state)
        }
    }

    @MainActor
    static func end() {
        lastKey = ""
        let current = activity
        activity = nil
        guard let current else { return }
        Task { await current.end(nil, dismissalPolicy: .immediate) }
    }

    /// Clears an island left behind by a previous launch, without touching one started since.
    static func endStale() {
        Task { @MainActor in
            let current = activity?.id
            for item in Activity<ImmersionAttributes>.activities where item.id != current {
                await item.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    @MainActor
    private static func push(_ state: ImmersionAttributes.ContentState) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        if let activity {
            await activity.update(ActivityContent(state: state, staleDate: nil))
            return
        }
        do {
            activity = try Activity.request(
                attributes: ImmersionAttributes(session: "feed"),
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil
            )
        } catch {
            activity = nil
            lastKey = ""
        }
    }
}

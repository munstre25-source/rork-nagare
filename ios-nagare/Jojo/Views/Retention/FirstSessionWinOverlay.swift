import Foundation

/// Legacy first-session coach progress (stored in `UserProfile.firstSessionStep`).
/// The overlay was replaced by the guided tour (`GuidanceCenter`); the value is still read so
/// people who already finished or skipped the old coach don't see the new tour.
nonisolated enum FirstSessionStep: Int, CaseIterable, Sendable {
    case tap = 0
    case hear = 1
    case good = 2
    case done = 3
}

import Foundation

nonisolated enum LibraryShelf: String, CaseIterable, Identifiable, Sendable {
    case watched, liked, saved, later

    var id: String { rawValue }

    var title: String {
        switch self {
        case .watched: "Watched"
        case .liked: "Liked"
        case .saved: "Saved"
        case .later: "Later"
        }
    }

    var symbol: String {
        switch self {
        case .watched: "checkmark.circle"
        case .liked: "heart.fill"
        case .saved: "bookmark.fill"
        case .later: "clock.fill"
        }
    }

    var subtitle: String {
        switch self {
        case .watched: "Clips you’ve finished"
        case .liked: "Videos you liked"
        case .saved: "Clips you bookmarked"
        case .later: "Want to watch"
        }
    }
}

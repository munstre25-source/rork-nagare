import Foundation

nonisolated enum LibraryShelf: String, CaseIterable, Identifiable, Sendable {
    case watched, saved, later

    var id: String { rawValue }

    var title: String {
        switch self {
        case .watched: "Watched"
        case .saved: "Saved"
        case .later: "Later"
        }
    }

    var symbol: String {
        switch self {
        case .watched: "checkmark.circle"
        case .saved: "heart.fill"
        case .later: "bookmark.fill"
        }
    }

    var subtitle: String {
        switch self {
        case .watched: "Clips you’ve finished"
        case .saved: "Favorites you hearted"
        case .later: "Want to watch"
        }
    }
}

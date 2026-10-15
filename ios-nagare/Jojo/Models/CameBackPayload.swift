import Foundation

/// Feed toast when a saved word reappears in the spoken line.
struct CameBackPayload: Equatable, Identifiable {
    var id: String { wordKey + clipId }
    var surface: String
    var gloss: String
    var wordKey: String
    var clipId: String
}

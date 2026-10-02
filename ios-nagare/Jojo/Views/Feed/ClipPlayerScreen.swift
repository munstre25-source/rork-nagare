import SwiftUI

/// Full-screen single-clip player (fullscreen button, Explore, Review thumbnails, Search results).
/// Thin wrapper around ImmersivePlayerScreen so every entry point gets the Kiku look.
struct ClipPlayerScreen: View {
    let clip: Clip
    var startLine: Int?
    var loopLine: Bool = false

    var body: some View {
        ImmersivePlayerScreen(clip: clip, startLine: startLine, loopLine: loopLine)
    }
}

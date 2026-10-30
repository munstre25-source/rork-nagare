import SwiftUI

/// A real frame from the clip's video — the YouTube still, the way Kiku's review card shows
/// the scene a word came from. Resolves the largest available 16:9 still once per video and
/// falls back to the gradient poster when a video has no stills.
@MainActor
struct ClipVideoStill: View {
    let clip: Clip
    var showsPlay: Bool = true

    @State private var stillURL: URL?
    @State private var resolved = false

    /// One HEAD probe per video for the whole session, shared across every card.
    private static var resolvedURLs: [String: URL?] = [:]

    var body: some View {
        ZStack {
            if let stillURL {
                AsyncImage(url: stillURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.bgElevatedDark
                }
            } else if resolved {
                ClipPosterView(clip: clip, showsSymbol: false)
            } else {
                Color.bgElevatedDark
            }
            if showsPlay {
                Image(systemName: "play.fill")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(.black.opacity(0.45), in: Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1))
                    .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
            }
        }
        .task(id: clip.videoId) {
            if let cached = Self.resolvedURLs[clip.videoId] {
                stillURL = cached
                resolved = true
                return
            }
            let url = clip.hasRealVideo ? await Self.firstExistingStill(videoId: clip.videoId) : nil
            Self.resolvedURLs[clip.videoId] = url
            stillURL = url
            resolved = true
        }
    }

    /// The biggest 16:9 still YouTube serves for the video; nil when none exist.
    private static func firstExistingStill(videoId: String) async -> URL? {
        for name in ["maxresdefault", "hq720", "mqdefault"] {
            guard let url = URL(string: "https://i.ytimg.com/vi/\(videoId)/\(name).jpg") else { continue }
            var request = URLRequest(url: url)
            request.httpMethod = "HEAD"
            request.timeoutInterval = 6
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  let http = response as? HTTPURLResponse, http.statusCode == 200,
                  data.count > 1_000 else { continue }
            return url
        }
        return nil
    }
}

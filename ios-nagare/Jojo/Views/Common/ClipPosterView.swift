import SwiftUI
import AVFoundation
import UIKit

extension Clip {
    /// Synchronous poster from a bundled JPG, if present.
    var bundledPosterImage: UIImage? {
        guard let url = Self.bundledPosterURL(for: id) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }
}

/// Real clip artwork: bundled JPG → first frame of local MP4 → gradient poster.
struct ClipPosterView: View {
    let clip: Clip
    var isAnimating: Bool = false
    var showsSymbol: Bool = true

    @State private var generated: UIImage?

    var body: some View {
        ZStack {
            if let image = clip.bundledPosterImage ?? generated {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else {
                GradientPoster(clip: clip, isAnimating: isAnimating, showsSymbol: showsSymbol)
            }
        }
        .task(id: clip.id) {
            guard clip.bundledPosterImage == nil, generated == nil,
                  let url = Clip.bundledVideoURL(for: clip.id) else { return }
            generated = await Self.frameImage(from: url, at: 1.5)
        }
    }

    private static func frameImage(from url: URL, at seconds: Double) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 1280, height: 720)
            let time = CMTime(seconds: seconds, preferredTimescale: 600)
            generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { _, cgImage, _, result, _ in
                if result == .succeeded, let cgImage {
                    continuation.resume(returning: UIImage(cgImage: cgImage))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

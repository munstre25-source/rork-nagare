import SwiftUI
import AVFoundation
import UIKit

@MainActor
private enum PosterImageCache {
    static let images: NSCache<NSURL, UIImage> = {
        let cache = NSCache<NSURL, UIImage>()
        cache.countLimit = 24
        cache.totalCostLimit = 32 * 1024 * 1024
        return cache
    }()

    static func store(_ image: UIImage, for url: URL) {
        let pixels = image.size.width * image.size.height * image.scale * image.scale
        images.setObject(image, forKey: url as NSURL, cost: Int(pixels * 4))
    }
}

extension Clip {
    /// Bundled stills survive view recreation without repeated file reads and decoding.
    @MainActor var bundledPosterImage: UIImage? {
        guard let url = Self.bundledPosterURL(for: id) else { return nil }
        if let image = PosterImageCache.images.object(forKey: url as NSURL) { return image }
        guard let image = UIImage(contentsOfFile: url.path) else { return nil }
        PosterImageCache.store(image, for: url)
        return image
    }
}

/// Real clip artwork: bundled JPG, local frame, or the source video's YouTube thumbnail.
struct ClipPosterView: View {
    let clip: Clip
    var isAnimating: Bool = false
    var showsSymbol: Bool = true

    @State private var generated: UIImage?
    @State private var generatedClipId: String?

    private var currentGenerated: UIImage? {
        generatedClipId == clip.id ? generated : nil
    }

    private var youtubeThumbnail: URL? {
        guard clip.hasRealVideo else { return nil }
        return URL(string: "https://i.ytimg.com/vi/\(clip.videoId)/mqdefault.jpg")
    }

    var body: some View {
        ZStack {
            if let image = clip.bundledPosterImage ?? currentGenerated {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else if let youtubeThumbnail {
                AsyncImage(url: youtubeThumbnail) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipped()
                    } else {
                        // Keep an identifiable poster while loading or if YouTube has no still.
                        GradientPoster(clip: clip, isAnimating: isAnimating, showsSymbol: showsSymbol)
                    }
                }
            } else {
                GradientPoster(clip: clip, isAnimating: isAnimating, showsSymbol: showsSymbol)
            }
        }
        .task(id: clip.id) {
            generated = nil
            generatedClipId = nil
            guard clip.bundledPosterImage == nil,
                  let url = Clip.bundledVideoURL(for: clip.id) else { return }
            if let frame = PosterImageCache.images.object(forKey: url as NSURL) {
                generated = frame
                generatedClipId = clip.id
                return
            }
            let frame = await Self.frameImage(from: url, at: 1.5)
            if !Task.isCancelled {
                if let frame { PosterImageCache.store(frame, for: url) }
                generated = frame
                generatedClipId = clip.id
            }
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

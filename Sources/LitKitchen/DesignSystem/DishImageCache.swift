import ImageIO
import SwiftUI
import UIKit

/// A decoded-image cache for dish photos.
///
/// `AsyncImage` keeps no memory of its own: when SwiftUI rebuilds the view it
/// starts the load again from scratch, and the image blinks back to a
/// placeholder while it does. That was tolerable in the feed, where rows are
/// rebuilt rarely — and became obvious on the map, where the camera publishes a
/// new zoom on every frame of a pinch and every pin is rebuilt with it. Food
/// flickering into fork-and-knife mid-gesture makes the map look broken.
///
/// URLCache does not solve it. It avoids the network round-trip but still
/// re-decodes, and the placeholder still shows for a frame or two. What has to
/// be cached is the *decoded* image.
@MainActor
enum DishImageCache {
    private static let store: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        // Thumbnails, not originals — a few hundred fit comfortably, and the
        // cost limit is the real bound since dimensions vary.
        c.countLimit = 240
        c.totalCostLimit = 48 * 1024 * 1024
        return c
    }()

    /// In-flight loads, so eight pins sharing one seed photo issue one request
    /// rather than eight.
    private static var inFlight: [String: Task<UIImage?, Never>] = [:]

    static func cached(_ urlString: String) -> UIImage? {
        store.object(forKey: urlString as NSString)
    }

    static func load(_ urlString: String, maxPixel: CGFloat = 0) async -> UIImage? {
        if let hit = cached(urlString) { return hit }
        guard let url = URL(string: urlString) else { return nil }

        if let running = inFlight[urlString] { return await running.value }

        let task = Task<UIImage?, Never> {
            guard
                let (data, response) = try? await URLSession.shared.data(from: url),
                let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode)
            else { return nil }
            // Decode straight to the size being drawn. `UIImage(data:)` decodes
            // at full resolution whatever the view does with it afterwards, and
            // a 1200×1600 cook photo costs 7.3 MB of that — about seven of them
            // fill this entire cache, so a screen of map pins evicted itself
            // continuously and re-downloaded on every pan.
            return downsample(data, maxPixel: maxPixel) ?? UIImage(data: data)
        }
        inFlight[urlString] = task

        let image = await task.value
        inFlight[urlString] = nil
        if let image {
            store.setObject(image, forKey: urlString as NSString, cost: data(cost: image))
        }
        return image
    }

    private static func data(cost image: UIImage) -> Int {
        let size = image.size
        return Int(size.width * size.height * image.scale * image.scale * 4)
    }

    /// Decode at the drawn size instead of the stored size.
    ///
    /// ImageIO rather than `UIImage`: it produces the thumbnail without ever
    /// decompressing the full image into memory, which is the whole point —
    /// `UIImage(data:)` followed by a resize has already paid the cost by the
    /// time you shrink it. This is the WWDC "iOS Memory Deep Dive" recipe.
    ///
    /// A backstop, not the main mechanism. Storage now returns an
    /// already-correct thumbnail for anything in a public bucket (see
    /// `StorageImage`), so this matters for signed buyer avatars and any
    /// future off-Supabase URL — and it is what keeps the cache honest if the
    /// render endpoint is ever unavailable.
    private static func downsample(_ data: Data, maxPixel: CGFloat) -> UIImage? {
        guard maxPixel > 0 else { return nil }
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions)
        else { return nil }

        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            // Without this a photograph shot in portrait comes back rotated:
            // the orientation lives in EXIF, and the thumbnail does not inherit
            // it unless asked.
            kCGImageSourceCreateThumbnailWithTransform: true,
            // Pay the decode here, on this background task, rather than on the
            // first frame that tries to draw it.
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxPixel.rounded(.up)),
        ] as CFDictionary

        guard let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options)
        else { return nil }
        return UIImage(cgImage: thumb)
    }
}

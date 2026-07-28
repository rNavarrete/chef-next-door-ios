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

    static func load(_ urlString: String) async -> UIImage? {
        if let hit = cached(urlString) { return hit }
        guard let url = URL(string: urlString) else { return nil }

        if let running = inFlight[urlString] { return await running.value }

        let task = Task<UIImage?, Never> {
            guard
                let (data, response) = try? await URLSession.shared.data(from: url),
                let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                let image = UIImage(data: data)
            else { return nil }
            return image
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
}

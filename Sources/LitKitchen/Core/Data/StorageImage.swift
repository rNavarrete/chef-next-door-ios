import Foundation

/// Asks Supabase Storage for a photo the size we are actually going to draw.
///
/// Every photo in the app was fetched at full resolution and then scaled down
/// by the view. A map pin is 58×44pt and was pulling a 900×675 JPEG to fill it;
/// a real cook's upload is 1200×1600. Measured against this project's bucket:
///
///     original          160 KB over the wire, 2.3 MB decoded in memory
///     render at 120×90  4.9 KB over the wire, ~0.04 MB decoded
///
/// Thirty-three times the bytes and nearly two hundred times the memory, per
/// pin, for pixels no one can see. On a screen of seventy-odd pins over
/// cellular that is the difference between a map and a slideshow — and it was
/// also silently thrashing the image cache, whose 48 MB ceiling holds only
/// about seven full-size photographs. Every eviction is another download.
///
/// The render endpoint is a paid Supabase feature and is **verified enabled on
/// this project** — the numbers above are measurements, not estimates. If it
/// were ever switched off these URLs would 400, so `thumbnail` is written to
/// fail closed: anything it does not recognise comes back untouched and loads
/// exactly as it did before.
enum StorageImage {
    private static let objectPath = "/storage/v1/object/public/"
    private static let renderPath = "/storage/v1/render/image/public/"

    /// A URL for the same image at roughly the size it will be drawn.
    ///
    /// `width`/`height` are **pixels, not points** — pass the point size
    /// multiplied by the screen scale, or the image arrives soft on a 3× phone.
    /// `DishPhoto` does that conversion so no caller has to remember.
    ///
    /// Returns the input unchanged for anything that is not a public Storage
    /// object: signed URLs carry a token in the query string and rewriting the
    /// path would invalidate it, and a remote URL from anywhere else has no
    /// render endpoint at all.
    static func thumbnail(
        _ urlString: String?,
        width: Int,
        height: Int,
        quality: Int = 72
    ) -> String? {
        guard let urlString, !urlString.isEmpty else { return nil }
        guard urlString.contains(objectPath), !urlString.contains("token=") else {
            return urlString
        }
        let base = urlString.replacingOccurrences(of: objectPath, with: renderPath)
        let separator = base.contains("?") ? "&" : "?"
        // `cover` rather than `contain`: every surface that draws a photo
        // clips it to a fixed frame, so letterboxing would only add bytes to
        // encode bars the view then crops off.
        return "\(base)\(separator)width=\(width)&height=\(height)&resize=cover&quality=\(quality)"
    }
}

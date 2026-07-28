import Foundation
import os
import Supabase
import UIKit

/// Uploads cook-supplied photos to Supabase Storage.
///
/// Photos are the feed's primary signal — a card without one reads as an
/// abandoned listing next to cards that have one. But stock-looking food
/// photography measured as a *distrust* signal in this market
/// (`RESEARCH.md` Finding 6), so this exists to make a cook's own phone photo
/// the path of least resistance, not to offer a library of nice pictures.
@MainActor
public final class PhotoUploader {
    private let client: SupabaseClient
    private let log = Logger(subsystem: "com.litkitchen.app", category: "PhotoUpload")

    public init(client: SupabaseClient = SupabaseEnvironment.shared) {
        self.client = client
    }

    public enum UploadError: LocalizedError {
        case notSignedIn
        case unreadableImage
        case failed(String)

        public var errorDescription: String? {
            switch self {
            case .notSignedIn: "Sign in before adding a photo."
            case .unreadableImage: "That image couldn't be read. Try another."
            case .failed(let message): message
            }
        }
    }

    private static let bucket = "kitchen-photos"

    /// Longest edge, in pixels. A modern phone photo is ~4000px and 3–8 MB;
    /// the largest this is ever displayed at is a 104pt thumbnail on a 3×
    /// screen. Uploading the original would spend a cook's mobile data on
    /// detail that is thrown away before it reaches a screen.
    nonisolated private static let maxDimension: CGFloat = 1600
    nonisolated private static let jpegQuality: CGFloat = 0.8

    /// Uploads and returns a public URL.
    ///
    /// The path is `<uid>/<kind>/<uuid>.jpg` — the uid prefix is what the
    /// storage policy checks, so a cook can only ever write inside their own
    /// folder (`migrations/024`).
    public func upload(_ image: UIImage, kind: Kind) async throws -> String {
        guard let userID = try? await client.auth.session.user.id else {
            throw UploadError.notSignedIn
        }
        guard let data = Self.downscaledJPEG(image) else {
            throw UploadError.unreadableImage
        }

        // `.lowercased()` is load-bearing. Swift's `UUID.uuidString` is
        // UPPERCASE; Postgres renders `auth.uid()::text` lowercase. The storage
        // policy compares the first path segment to it as text, so an uppercased
        // folder fails the check and every upload comes back
        // "new row violates row-level security policy" — while the identical
        // request built by hand with a lowercase path succeeds.
        let path = "\(userID.uuidString.lowercased())/\(kind.rawValue)/\(UUID().uuidString.lowercased()).jpg"
        do {
            try await client.storage
                .from(Self.bucket)
                .upload(path, data: data, options: FileOptions(contentType: "image/jpeg"))
            return try client.storage.from(Self.bucket).getPublicURL(path: path).absoluteString
        } catch {
            // The real error, not a guess at one. A swallowed upload failure
            // is indistinguishable from a network blip and sent me looking at
            // connectivity when the cause was the request itself.
            log.error("upload failed: \(String(describing: error), privacy: .public)")
            #if DEBUG
            throw UploadError.failed("Upload failed: \(String(describing: error))")
            #else
            throw UploadError.failed("Couldn't upload that photo. Check your connection and try again.")
            #endif
        }
    }

    public enum Kind: String, Sendable {
        case avatar
        case dish
    }

    /// Attaches an avatar to the signed-in cook. Separate from `register_cook`
    /// because there is no cook id to name a folder with until registration
    /// returns.
    public func setAvatar(url: String) async throws {
        struct Params: Encodable { let p_url: String }
        do {
            try await client.rpc("set_cook_avatar", params: Params(p_url: url)).execute()
        } catch {
            throw UploadError.failed("Couldn't save that photo to your kitchen.")
        }
    }

    /// Scales the longest edge down to `maxDimension` and re-encodes as JPEG.
    /// `UIGraphicsImageRenderer` respects orientation, so a photo taken in
    /// portrait doesn't arrive rotated — which `CGImage`-level resizing gets
    /// wrong often enough to be worth avoiding.
    nonisolated static func downscaledJPEG(_ image: UIImage) -> Data? {
        let longest = max(image.size.width, image.size.height)
        guard longest > 0 else { return nil }

        let scale = min(1, maxDimension / longest)
        let target = CGSize(width: (image.size.width * scale).rounded(),
                            height: (image.size.height * scale).rounded())

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1          // target is already in pixels
        format.opaque = true      // no transparency in a photo; smaller output

        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: jpegQuality)
    }
}

import PhotosUI
import SwiftUI

/// Pick-and-upload tile for a cook photo.
///
/// Uploads immediately on selection rather than deferring to the save button.
/// A cook on a phone at the kitchen counter should find out about a failed
/// upload while they're still looking at the picker, not after they've filled
/// in a form and pressed Save.
struct PhotoPickerTile: View {
    /// Bound to the uploaded public URL. `nil` until an upload succeeds, so a
    /// failed upload can never be mistaken for a saved one.
    @Binding var photoURL: String?
    var kind: PhotoUploader.Kind
    var size: CGFloat = 96
    var cornerRadius: CGFloat = 16
    /// Avatars read as a person, dishes as a card. Same control, two shapes.
    var isCircular: Bool = false
    var emptyLabel: String = "Add photo"

    @State private var selection: PhotosPickerItem?
    @State private var preview: UIImage?
    @State private var isUploading = false
    @State private var errorMessage: String?

    private let uploader = PhotoUploader()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PhotosPicker(selection: $selection, matching: .images, photoLibrary: .shared()) {
                tile
            }
            .buttonStyle(.plain)
            .disabled(isUploading)

            if let errorMessage {
                Text(errorMessage)
                    .font(LK.Typography.meta)
                    .foregroundStyle(LK.Palette.allergenInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onChange(of: selection) { _, item in
            guard let item else { return }
            load(item)
        }
        // Show what is already saved.
        //
        // `preview` is only populated by picking an image *in this session*, so
        // a tile bound to a photo the cook saved yesterday rendered the empty
        // "Add photo" state — telling them it hadn't saved, and inviting them to
        // upload it again. Seeded from the decoded cache, so a revisit is
        // instant and costs no network.
        .task(id: photoURL) {
            guard let photoURL else {
                preview = nil
                return
            }
            guard preview == nil else { return }
            preview = await DishImageCache.load(photoURL)
        }
    }

    private var tile: some View {
        ZStack {
            if let preview {
                Image(uiImage: preview)
                    .resizable()
                    .scaledToFill()
            } else {
                LK.Palette.chipNeutral
                VStack(spacing: 4) {
                    Image(systemName: "camera")
                        .font(.system(size: 20, weight: .light))
                    Text(emptyLabel)
                        .font(.system(size: 11, weight: .medium))
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(LK.Palette.inkTertiary)
                .padding(6)
            }

            if isUploading {
                Color.black.opacity(0.35)
                ProgressView().tint(.white)
            }
        }
        .frame(width: size, height: size)
        .modifier(TileShape(isCircular: isCircular, cornerRadius: cornerRadius))
        // Never announce a photo as attached while it's still uploading, or
        // while it failed — the tile shows the local preview either way.
        .accessibilityLabel(
            isUploading ? "Uploading photo"
                        : (photoURL == nil ? emptyLabel : "Photo added, double tap to change")
        )
    }

    /// Clip + hairline in one place. A `@ViewBuilder` returning
    /// `some InsettableShape` doesn't compile — the conditional erases to
    /// `_ConditionalContent`, which isn't insettable — and `strokeBorder`
    /// needs an insettable shape, so the branch has to happen around the whole
    /// clip-and-stroke pair rather than around the shape.
    private struct TileShape: ViewModifier {
        let isCircular: Bool
        let cornerRadius: CGFloat

        func body(content: Content) -> some View {
            if isCircular {
                content
                    .clipShape(Circle())
                    .overlay { Circle().strokeBorder(LK.Palette.hairline, lineWidth: 0.5) }
            } else {
                let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                content
                    .clipShape(shape)
                    .overlay { shape.strokeBorder(LK.Palette.hairline, lineWidth: 0.5) }
            }
        }
    }

    private func load(_ item: PhotosPickerItem) {
        isUploading = true
        errorMessage = nil
        // Clear first: if this upload fails, the previously attached URL must
        // not survive next to a new preview image.
        photoURL = nil

        Task {
            defer { isUploading = false }
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                errorMessage = "That image couldn't be read. Try another."
                return
            }
            preview = image
            do {
                photoURL = try await uploader.upload(image, kind: kind)
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription
                    ?? "Couldn't upload that photo."
            }
        }
    }
}

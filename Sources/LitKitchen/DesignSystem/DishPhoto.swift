import SwiftUI

/// A cook-submitted dish photo, with the placeholder it degrades to.
///
/// Every surface renders through this so the empty case is designed rather
/// than incidental — a cook with no photo yet is normal, not an error, and the
/// card must not collapse or look broken around them.
///
/// Dark cooks lose their colour (`isLit: false`), same rule as the rest of the
/// interface: closed reads as a memory of a card, not an offer.
struct DishPhoto: View {
    let urlString: String?
    var size: CGFloat = 104
    /// Defaults to `size`, i.e. square. Map pins pass a shorter height so a
    /// 4:3 photograph is cropped to 4:3 rather than to a square — see
    /// `MapPin`, where the crop was costing the picture its subject.
    var height: CGFloat?
    var cornerRadius: CGFloat = LK.Metrics.radiusInner
    var isLit: Bool = true

    /// Seeded from the cache so a photo already in memory renders on the very
    /// first frame — no placeholder, no fade. This is what stops map pins
    /// blinking back to fork-and-knife every time the camera moves.
    @State private var loaded: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let loaded {
                Image(uiImage: loaded)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if urlString == nil || failed {
                // A dead URL must look like "no photo", never like a broken
                // app.
                placeholder
            } else {
                placeholder.overlay { ProgressView().scaleEffect(0.7) }
            }
        }
        .task(id: urlString) {
            guard let urlString else { return }
            if let hit = DishImageCache.cached(urlString) {
                loaded = hit
                return
            }
            let image = await DishImageCache.load(urlString)
            // Only animate a genuine load. Cache hits above return before this
            // and appear instantly, which is the whole point.
            withAnimation(.easeOut(duration: 0.18)) {
                loaded = image
                failed = image == nil
            }
        }
        .frame(width: size, height: height ?? size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .saturation(isLit ? 1 : 0)
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(LK.Palette.hairline, lineWidth: 0.5)
        }
        .accessibilityHidden(true)   // the row's text carries the meaning
    }

    private var placeholder: some View {
        LK.Palette.chip
            .overlay {
                Image(systemName: "fork.knife")
                    .font(.system(size: size * 0.22, weight: .light))
                    .foregroundStyle(LK.Palette.inkTertiary.opacity(0.45))
            }
    }
}

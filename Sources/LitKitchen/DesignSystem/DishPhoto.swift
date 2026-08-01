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
    /// What to draw when there is no photograph. Pass the dish name; the first
    /// character becomes a letterform. Nil keeps the old fork-and-knife, which
    /// is still right anywhere there is no name to draw from.
    var monogramSource: String?

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

    @ViewBuilder
    private var placeholder: some View {
        if let letter = monogramLetter {
            monogram(letter)
        } else {
            LK.Palette.chip
                .overlay {
                    Image(systemName: "fork.knife")
                        .font(.system(size: size * 0.22, weight: .light))
                        .foregroundStyle(LK.Palette.inkTertiary.opacity(0.45))
                }
        }
    }

    /// First letter of the dish, uppercased. Nil for a name that starts with
    /// something that would not read as a letterform — an emoji, a digit, a
    /// stray bullet — which falls back to the fork and knife rather than
    /// setting a 32pt "7".
    private var monogramLetter: String? {
        guard let first = monogramSource?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .first,
            first.isLetter
        else { return nil }
        return String(first).uppercased()
    }

    /// A letter standing in for a photograph, misregistered like cheap colour
    /// printing.
    ///
    /// A grid of identical grey fork-and-knife tiles is the worst thing on a
    /// feed whose subject is what the food looks like — it makes every cook
    /// without a photo look like the same broken row. A letterform is at least
    /// *this dish*, and the offset plates make the tile look printed rather
    /// than merely empty.
    ///
    /// Ink last and centred, so the letter stays legible at 4.5:1 and the
    /// colour reads as fringing around it rather than as the letter itself.
    private func monogram(_ letter: String) -> some View {
        let plate = size * 0.022      // scales with the tile; ~1.2pt at 56
        return LK.Palette.printPaper
            .overlay {
                ZStack {
                    Text(letter)
                        .foregroundStyle(Color(hex: 0xE0218A).opacity(0.85))
                        .offset(x: -plate, y: -plate)
                    Text(letter)
                        .foregroundStyle(Color(hex: 0xF5C518).opacity(0.85))
                        .offset(x: plate, y: plate)
                    Text(letter)
                        .foregroundStyle(LK.Palette.ink)
                }
                .font(LK.Typography.display(size * 0.52, weight: .bold))
            }
    }
}

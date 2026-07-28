import SwiftUI

/// One dish, in full.
///
/// The menu row is a list entry: name, price, allergens, and whatever fits.
/// This is where someone actually decides — the photos a cook took of *this*
/// dish, what they wrote about it, what's in it, and what it costs before you
/// commit to opening a conversation.
///
/// It is also the first surface that consumes migration 057 properly. Cooks
/// have been able to attach four photos per dish since then and buyers only
/// ever saw the first one, on a card.
struct DishDetailSheet: View {
    let item: MenuItem
    let cookName: String
    /// Nil when there's no messaging backend — the sheet still shows the dish.
    var onOrder: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var page: Int? = 0

    private var photos: [String] { item.photos }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    gallery
                    names
                    priceBlock
                    madeWithBlock
                }
                .padding(LK.Metrics.screenPadding)
            }
            .background(LK.Palette.ground)
            .safeAreaInset(edge: .bottom) { orderBar }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .font(LK.Typography.navBar)
                        .tint(LK.Palette.action)
                }
                // The cook's name, not the dish's. The dish is already the
                // largest thing on the sheet; whose kitchen you are in is the
                // fact the sheet does not otherwise carry.
                ToolbarItem(placement: .principal) {
                    Text(cookName)
                        .font(LK.Typography.bodyEmphasis)
                        .foregroundStyle(LK.Palette.inkQuiet)
                }
            }
        }
        .tint(LK.Palette.action)
    }

    // MARK: - Photos

    /// Main image plus every thumbnail.
    ///
    /// Baymard's mobile-gallery research gives two workable signposts for
    /// "there are more photos than you can see": indicator dots (used on 75% of
    /// mobile sites) or a visible thumbnail strip. Thumbnails are the stronger
    /// signal but normally have to be truncated, and truncation *without* a cue
    /// is the failure mode they document — users assume the visible thumbnails
    /// are all of them.
    ///
    /// Migration 057 caps a dish at four photos, which removes the tradeoff
    /// entirely: all four fit at once, so there is nothing to truncate and
    /// nothing to signpost. Baymard lists "all thumbnails displayed" as viable
    /// only when counts are limited — ours are, by construction.
    ///
    /// A counter rides on the image as well, because the thumbnail strip sits
    /// below it and a one-handed reader may never look down.
    @ViewBuilder
    private var gallery: some View {
        if photos.isEmpty {
            // No photo is a normal state for a new cook, not an error. The
            // placeholder keeps the layout honest rather than collapsing it.
            DishPhoto(urlString: nil, size: 260, cornerRadius: 22)
                .frame(maxWidth: .infinity)
                .frame(height: 238)
        } else {
            VStack(spacing: 10) {
                pager
                if photos.count > 1 { thumbnails }
            }
        }
    }

    /// `ScrollView` + `.scrollTargetBehavior(.paging)`, not `TabView(.page)`.
    ///
    /// Two reasons. A paged `TabView` nested in this sheet's vertical
    /// `ScrollView` fights it for the drag gesture; and `scrollPosition` gives
    /// a two-way binding, so a thumbnail tap moves the image *and* a swipe
    /// moves the thumbnail highlight, from one piece of state.
    private var pager: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(photos.indices, id: \.self) { index in
                    DishPhoto(
                        urlString: photos[index],
                        size: 520,
                        cornerRadius: 0,
                        isLit: item.isAvailable
                    )
                    .frame(height: 238)
                    .containerRelativeFrame(.horizontal)
                    .clipped()
                    .id(index)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollIndicators(.hidden)
        .scrollPosition(id: $page)
        .frame(height: 238)
        .clipShape(RoundedRectangle(cornerRadius: LK.Metrics.radiusCard, style: .continuous))
        .overlay(alignment: .topTrailing) {
            if photos.count > 1 {
                Text("\((page ?? 0) + 1)/\(photos.count)")
                    .font(LK.Typography.ui(12, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(LK.Palette.photoScrim, in: Capsule())
                    .padding(10)
            }
        }
    }

    private var thumbnails: some View {
        HStack(spacing: 8) {
            ForEach(photos.indices, id: \.self) { index in
                Button {
                    // Scrolls the main image rather than swapping its source,
                    // so the change reads as movement through one set of photos
                    // instead of a reload.
                    withAnimation(.easeInOut(duration: 0.25)) { page = index }
                } label: {
                    DishPhoto(
                        urlString: photos[index],
                        size: 58,
                        cornerRadius: LK.Metrics.radiusField,
                        isLit: item.isAvailable
                    )
                    .overlay {
                        // `action`, not heat. Selection is an affordance you
                        // operated, not a statement about the food.
                        RoundedRectangle(cornerRadius: LK.Metrics.radiusField, style: .continuous)
                            .strokeBorder(
                                index == page ? LK.Palette.action : .clear,
                                lineWidth: 2
                            )
                    }
                    // The unselected ones step back rather than the selected one
                    // stepping forward — otherwise the strip jitters as the
                    // active thumbnail changes size mid-swipe.
                    .opacity(index == page ? 1 : 0.55)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Photo \(index + 1) of \(photos.count)")
            }
            Spacer(minLength: 0)
        }
        .animation(.easeInOut(duration: 0.2), value: page)
    }

    // MARK: - Text

    private var names: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.displayName())
                .font(LK.Typography.titleSecondary)
                .foregroundStyle(LK.Palette.ink)
                .fixedSize(horizontal: false, vertical: true)

            // The other name, when the cook gave one. Both are real names for
            // the dish in this market, and showing the second is the same
            // bilingual promise the search expansion makes.
            if let other = otherName {
                Text(other)
                    .font(LK.Typography.fieldValue)
                    .foregroundStyle(LK.Palette.inkTertiary)
            }

            if !item.isAvailable {
                Text("Sold out today")
                    .font(LK.Typography.ui(13.5, weight: .semibold))
                    .foregroundStyle(LK.Palette.inkTertiary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(LK.Palette.chip, in: Capsule())
                    .padding(.top, 4)
            }
        }
    }

    /// Whichever name isn't already the headline, if it differs.
    private var otherName: String? {
        let shown = item.displayName()
        for candidate in [item.nameES, item.nameEN] {
            if let candidate, !candidate.isEmpty, candidate != shown { return candidate }
        }
        return nil
    }

    private var priceBlock: some View {
        HStack(spacing: 10) {
            // A figure, not a pill. A price is not heat — and the pill's
            // hardcoded brown ink on an adaptive fill was unreadable in dark
            // mode, the same defect the map's price chip had.
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(item.price.figure)
                    .font(LK.Typography.titleSecondary)
                    .monospacedDigit()
                    .foregroundStyle(LK.Palette.ink)
                Text(item.price.unitLabel)
                    .font(LK.Typography.bodyEmphasis)
                    .foregroundStyle(LK.Palette.ink)
            }

            if item.price.minQuantity > 1 {
                // Stated in words, not as "min 4". This is the screen where
                // someone commits, and the minimum is the single most common
                // reason an order comes back needing renegotiation.
                Text("^[\(item.price.minQuantity) **order**](inflect: true) minimum")
                    .font(LK.Typography.body)
                    .foregroundStyle(LK.Palette.inkTertiary)
            }
            Spacer(minLength: 0)
        }
    }

    /// `Made with` and `Contains`, in one card.
    ///
    /// They were a paragraph and a chip row with nothing tying them together,
    /// which read as two unrelated afterthoughts. They answer the same question
    /// — what is in this — so they are one object with two labelled halves.
    ///
    /// Allergens stay always-visible: never a tooltip, never an accordion. This
    /// is the one screen where a UI shortcut is a safety bug (`PRD.md` §7).
    @ViewBuilder
    private var madeWithBlock: some View {
        let description = item.description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !description.isEmpty || !item.allergens.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                if !description.isEmpty {
                    section(header: "Made with") {
                        Text(description)
                            .font(LK.Typography.body)
                            .foregroundStyle(LK.Palette.inkQuiet)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if !description.isEmpty && !item.allergens.isEmpty {
                    Rectangle().fill(LK.Palette.hairline).frame(height: 1)
                }
                if !item.allergens.isEmpty {
                    section(header: "Contains") {
                        FlowLayout(spacing: 6) {
                            ForEach(item.allergens, id: \.self) { allergen in
                                Text(allergen)
                                    .font(LK.Typography.ui(14))
                                    .foregroundStyle(LK.Palette.ink)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .background(LK.Palette.chip, in: Capsule())
                            }
                        }
                    }
                } else {
                    section(header: "Contains") {
                        Text("\(cookName) hasn't listed any allergens for this dish. Ask them if you need to be sure.")
                            .font(LK.Typography.meta)
                            .foregroundStyle(LK.Palette.inkTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LK.Palette.surface, in: RoundedRectangle(cornerRadius: LK.Metrics.radiusCard, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: LK.Metrics.radiusCard, style: .continuous)
                    .strokeBorder(LK.Palette.hairline, lineWidth: LK.Metrics.cardBorderWidth)
            }
            .lkCardShadow()
        }
    }

    private func section<Content: View>(
        header: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(header)
                .font(LK.Typography.caps)
                .textCase(.uppercase)
                .tracking(LK.Typography.capsTracking)
                .foregroundStyle(LK.Palette.inkTertiary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
    }

    @ViewBuilder
    private var orderBar: some View {
        if let onOrder {
            VStack(spacing: 0) {
                Button {
                    dismiss()
                    onOrder()
                } label: {
                    Text(item.isAvailable ? "Order from \(cookName)" : "Ask \(cookName) about this")
                        .font(LK.Typography.navBarEmphasis)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(LK.Palette.action, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, LK.Metrics.screenPadding)
                .padding(.vertical, 12)
            }
            .background(.ultraThinMaterial)
        }
    }
}

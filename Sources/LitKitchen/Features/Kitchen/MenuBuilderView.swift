import SwiftUI

/// New or existing dish. The structured-price block is the point of this screen.
struct MenuBuilderView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: MenuItemDraft
    let cookID: UUID
    let onSave: (MenuItem) -> Void

    /// `item` nil creates, non-nil edits in place.
    init(cookID: UUID, editing item: MenuItem? = nil, onSave: @escaping (MenuItem) -> Void) {
        self.cookID = cookID
        self.onSave = onSave
        _draft = State(wrappedValue: item.map(MenuItemDraft.init(editing:)) ?? MenuItemDraft())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    photoSection
                    nameSection
                    priceSection
                    allergenSection
                    disclosureFooter
                }
                .padding(LK.Metrics.screenPadding)
            }
            .background(LK.Palette.ground)
            .navigationTitle(draft.isEditing ? "Edit dish" : "New dish")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let item = draft.build(cookID: cookID) {
                            onSave(item)
                            dismiss()
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(!draft.canSave)
                }
            }
        }
        .tint(LK.Palette.action)
    }

    // MARK: - Name

    /// The dish photo. First on the screen because it is first on the feed
    /// card — `headline_photo` is what a buyer sees before the name or the
    /// price, and a dish without one sits next to dishes that have one.
    private var photoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Show the food")
                    .font(LK.Typography.bodyEmphasis)
                    .foregroundStyle(LK.Palette.ink)
                Text("Your own photos, taken on your phone. They beat a perfect stock picture, which reads as a business rather than a neighbour. Up to four — the plate, the inside, the portion in a hand.")
                    .font(LK.Typography.meta)
                    .foregroundStyle(LK.Palette.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Horizontal, because the first slot is meaningfully different from
            // the rest and a grid would not say so. Reading order *is* display
            // order, and the leftmost is the one on the feed card.
            // All four slots, always. Rendering only the filled ones plus a
            // single "Add photo" tile meant a cook adding their first dish saw
            // exactly one square — the copy said "up to four" and the interface
            // showed room for one. Four outlines state the capacity before
            // anyone has to discover it.
            HStack(spacing: 9) {
                ForEach(0..<MenuItemDraft.maxPhotos, id: \.self) { index in
                    if index < draft.photos.count {
                        filledSlot(url: draft.photos[index], index: index)
                    } else if index == draft.photos.count {
                        // Exactly one live picker: the next slot to fill. The
                        // rest are outlines, so there is never a question of
                        // which tap adds where.
                        emptySlot
                    } else {
                        waitingSlot
                    }
                }
                Spacer(minLength: 0)
            }
            .animation(.easeInOut(duration: 0.2), value: draft.photos.count)

            if draft.photos.count > 1 {
                Text("First photo is the one buyers see on the feed. Tap another to move it there.")
                    .font(LK.Typography.ui(12))
                    .foregroundStyle(LK.Palette.inkTertiary)
            }
        }
    }

    /// Four across a 402pt screen minus gutters and gaps.
    private static let slotSize: CGFloat = 74

    private func filledSlot(url: String, index: Int) -> some View {
        DishPhoto(urlString: url, size: Self.slotSize, cornerRadius: LK.Metrics.radiusInner)
            .overlay(alignment: .topLeading) {
                if index == 0 {
                    Text("1st")
                        .font(LK.Typography.ui(10.5, weight: .heavy))
                        .foregroundStyle(LK.Palette.heatInk)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(LK.Palette.chip, in: Capsule())
                        .padding(4)
                }
            }
            .overlay(alignment: .topTrailing) {
                Button {
                    draft.photos.remove(at: index)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(LK.Typography.navBar)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.black.opacity(0.55))
                }
                .buttonStyle(.plain)
                .padding(4)
                .accessibilityLabel("Remove photo \(index + 1)")
            }
            .contentShape(Rectangle())
            .onTapGesture {
                // Promotion, not a picker: moving a photo to the front is how a
                // cook chooses their headline, and there is nowhere else in the
                // app to do it.
                guard index != 0 else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    let moved = draft.photos.remove(at: index)
                    draft.photos.insert(moved, at: 0)
                }
            }
            .accessibilityHint(index == 0 ? "Shown on the feed" : "Double tap to show this one on the feed")
    }

    /// Binds to a scratch value: `PhotoPickerTile` reports one URL, and this
    /// appends it rather than replacing anything.
    private var emptySlot: some View {
        PhotoPickerTile(
            photoURL: Binding(
                get: { nil },
                set: { newURL in
                    guard let newURL, draft.canAddPhoto else { return }
                    draft.photos.append(newURL)
                }
            ),
            kind: .dish,
            size: Self.slotSize,
            cornerRadius: 16,
            emptyLabel: draft.photos.isEmpty ? "Add" : "Add"
        )
    }

    /// A slot that exists to be counted, not tapped.
    private var waitingSlot: some View {
        RoundedRectangle(cornerRadius: LK.Metrics.radiusInner, style: .continuous)
            .strokeBorder(
                LK.Palette.inkTertiary.opacity(0.3),
                style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
            )
            .frame(width: Self.slotSize, height: Self.slotSize)
    }

    private var nameSection: some View {
        GroupedCard {
            LabeledField(label: "Name", text: $draft.nameEN, placeholder: "Tamal de puerco")
            Divider().overlay(LK.Palette.hairline)
            // The bilingual synonym field. Not "translation" — titles in this
            // market genuinely carry both, and this is what feeds the search
            // synonym expansion buyers see (`también: …`).
            LabeledField(label: "Also called…", text: $draft.nameES, placeholder: "pork tamale")
            Divider().overlay(LK.Palette.hairline)

            // `MenuItem.description` has existed since the model was written and
            // renders on every buyer-facing row — but there was no way to enter
            // it. Only seeded dishes ever had one, which is why real cooks'
            // dishes showed a name and a price and nothing else.
            HStack(alignment: .top, spacing: 0) {
                Text("Made with")
                    .font(LK.Typography.body)
                    .foregroundStyle(LK.Palette.ink)
                    .frame(width: 96, alignment: .leading)
                TextField(
                    "Wood-fired, thin crust. Vegetarian.",
                    text: $draft.description,
                    axis: .vertical
                )
                .font(LK.Typography.body)
                .lineLimit(1...4)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            Divider().overlay(LK.Palette.hairline)
            HStack {
                Text("Category")
                    .font(LK.Typography.body)
                    .foregroundStyle(LK.Palette.ink)
                Spacer()
                Picker("", selection: $draft.categoryType) {
                    Text("MEHKO meal").tag(FoodCategoryType.mehkoMeal)
                    Text("Baked good").tag(FoodCategoryType.cottageFood)
                }
                .labelsHidden()
                .tint(LK.Palette.action)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Price

    private var priceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Price — all three, always")

            GroupedCard {
                HStack(spacing: 10) {
                    priceField(title: "Amount", text: $draft.amountText, placeholder: "3.00", isFocusedStyle: true)
                        .keyboardType(.decimalPad)
                    priceField(title: "Min", text: $draft.minQuantityText, placeholder: "1")
                        .keyboardType(.numberPad)
                }
                .padding(14)

                Divider().overlay(LK.Palette.hairline)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Per")
                        .font(LK.Typography.ui(12, weight: .semibold))
                        .textCase(.uppercase)
                        .tracking(0.5)
                        .foregroundStyle(LK.Palette.inkTertiary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 7) {
                            ForEach(PriceUnit.allCases, id: \.self) { unit in
                                UnitChip(unit: unit, isSelected: draft.unit == unit) {
                                    draft.unit = unit
                                }
                            }
                        }
                    }
                }
                .padding(14)
            }

            // The loop-closer. What the cook types, as a stranger will read it.
            HStack(spacing: 8) {
                Text("Buyers see")
                    .font(LK.Typography.ui(13.5, weight: .semibold))
                    .foregroundStyle(LK.Palette.action)
                Text(draft.buyerPreview)
                    .font(LK.Typography.bodyEmphasis)
                    .monospacedDigit()
                    .foregroundStyle(LK.Palette.ink)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(LK.Palette.chip, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func priceField(
        title: String,
        text: Binding<String>,
        placeholder: String,
        isFocusedStyle: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(LK.Typography.ui(12, weight: .semibold))
                .textCase(.uppercase)
                .tracking(0.5)
                .foregroundStyle(LK.Palette.inkTertiary)
            TextField(placeholder, text: text)
                .font(LK.Typography.navBarEmphasis)
                .monospacedDigit()
                .padding(.horizontal, 11)
                .padding(.vertical, 9)
                .background(LK.Palette.ground, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(
                            isFocusedStyle ? LK.Palette.action : LK.Palette.hairline,
                            lineWidth: isFocusedStyle ? 1.5 : 1
                        )
                }
        }
    }

    // MARK: - Allergens

    private var allergenSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Allergens — required")

            FlowLayout(spacing: 7) {
                ForEach(MenuItemDraft.commonAllergens, id: \.self) { allergen in
                    AllergenChip(
                        title: allergen,
                        isSelected: draft.allergens.contains(allergen)
                    ) {
                        if draft.allergens.contains(allergen) {
                            draft.allergens.remove(allergen)
                        } else {
                            draft.allergens.insert(allergen)
                            draft.allergensAcknowledged = false
                        }
                    }
                }
            }

            // "None" has to be chosen, not skipped. An empty allergen list on
            // a dish is indistinguishable from an unfilled form otherwise, and
            // this is the one field where that ambiguity is a safety problem.
            if draft.allergens.isEmpty {
                Toggle(isOn: Bindable(draft).allergensAcknowledged) {
                    Text("None of these are in this dish")
                        .font(LK.Typography.meta)
                        .foregroundStyle(LK.Palette.inkQuiet)
                }
                .tint(LK.Palette.action)
                .padding(.top, 2)
            }
        }
    }

    private var disclosureFooter: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !draft.validationProblems.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(draft.validationProblems, id: \.self) { problem in
                        Text("• \(problem)")
                            .font(LK.Typography.meta)
                            .foregroundStyle(LK.Palette.inkTertiary)
                    }
                }
            }

            if draft.categoryType == .mehkoMeal {
                // Rendered from category + agency, never left to the cook.
                Text("Listed as a MEHKO meal, so “Made in a Home Kitchen” and your permit number print on it automatically.")
                    .font(LK.Typography.meta)
                    .foregroundStyle(LK.Palette.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 4)
    }
}

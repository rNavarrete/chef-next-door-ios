import SwiftUI

// MARK: - Containers

struct GroupedCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        // Radius and edge weight raised to match the feed cards. A 0.5pt
        // hairline is the convention for a dense settings list; this holds a
        // neighbour's menu, and it should read as an object rather than a
        // table. Warm border rather than grey — the whole surface is paper.
        VStack(spacing: 0) { content }
            .background(LK.Palette.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            // Clips its own content.
            //
            // The background was drawn *behind* the children and nothing bounded
            // them, so anything wider than the card — a row's horizontal photo
            // strip, which is deliberately inset negatively to run to the edge —
            // spilled past the rounded corners and out of the card entirely.
            // Before the corner radius went up this was invisible; at 22pt the
            // overflow crosses a visible curve.
            //
            // Clipped before the border so the stroke still draws on top at full
            // weight rather than being shaved by its own clip.
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(LK.Palette.hairline, lineWidth: LK.Metrics.cardBorderWidth)
            }
            .lkCardShadow()
    }
}

struct SectionHeader: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(LK.Typography.caps)
            .textCase(.uppercase)
            .tracking(LK.Typography.capsTracking)
            .foregroundStyle(LK.Palette.inkTertiary)
    }
}

struct LabeledField: View {
    let label: String
    @Binding var text: String
    let placeholder: String
    /// Dish names must not be autocorrected. Verified in the simulator:
    /// typing "Pupusa revuelta" on an English keyboard produced
    /// **"Pupusa rebuilt a"**. A bilingual app whose whole thesis is that
    /// Spanish and English are both first-class cannot let the keyboard
    /// silently anglicise a cook's menu — and the cook may never notice,
    /// because the correction lands after they've moved to the next field.
    var autocorrects: Bool = false
    /// Overridable, because it was previously hardcoded to `.sentences` here
    /// and silently beat `.never` applied at the call site — an inner modifier
    /// wins. That turned "buyer1@seed.test" into "Buyer1@seed.test" on an
    /// email field, which is the kind of bug that only shows up when someone
    /// actually types into it.
    var capitalization: TextInputAutocapitalization = .sentences
    var keyboard: UIKeyboardType = .default

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(LK.Typography.body)
                .foregroundStyle(LK.Palette.ink)
                .frame(width: 96, alignment: .leading)
            TextField(placeholder, text: $text)
                .font(LK.Typography.body)
                .foregroundStyle(LK.Palette.ink)
                .autocorrectionDisabled(!autocorrects)
                .textInputAutocapitalization(capitalization)
                .keyboardType(keyboard)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

// MARK: - Chips

struct UnitChip: View {
    let unit: PriceUnit
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(unit.shortLabel)
                .font(LK.Typography.bodyEmphasis)
                .foregroundStyle(isSelected ? .white : LK.Palette.inkQuiet)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isSelected ? LK.Palette.ink : LK.Palette.chip, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Dish-level allergen chip. Always visible — never a tooltip (there is no
/// hover on iPhone) and never inside an accordion. Colour is never the only
/// signal: selection also carries a checkmark.
struct AllergenChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(LK.Typography.ui(12, weight: .bold))
                }
                Text(title)
                    .font(LK.Typography.ui(13.5, weight: .semibold))
            }
            .foregroundStyle(isSelected ? LK.Palette.ink : LK.Palette.inkQuiet)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(isSelected ? LK.Palette.chip : LK.Palette.chip, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) allergen")
        .accessibilityValue(isSelected ? "contains" : "not listed")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// The lamp. Amber, and never on anything tappable.
struct LampIndicator: View {
    var tier: FreshnessTier
    var size: CGFloat = 9

    var body: some View {
        Group {
            switch tier {
            case .lit, .dimming:
                Circle().fill(tier == .lit ? LK.Palette.heat : LK.Palette.heat.opacity(0.55))
            case .unconfirmed:
                // Hollow ring — the dot stops asserting the cook is cooking.
                Circle().strokeBorder(Color(red: 0.788, green: 0.604, blue: 0.271), lineWidth: 2)
            case .out:
                Circle().fill(LK.Palette.inkTertiary.opacity(0.35))
            }
        }
        .frame(width: size, height: size)
        .shadow(
            color: tier == .lit ? LK.Palette.heat.opacity(0.55) : .clear,
            radius: tier == .lit ? 5 : 0
        )
    }
}

// MARK: - Layout

/// Wrapping row layout for chips. `Layout` rather than a nested-HStack hack so
/// it reflows correctly under larger Dynamic Type sizes.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

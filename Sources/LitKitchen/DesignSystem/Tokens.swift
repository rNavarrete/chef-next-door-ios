import SwiftUI

/// Design tokens — polish pass.
///
/// **The rule:** marigold marks *heat*, blue marks *affordance*. Marigold never appears on a
/// button, a badge, a price or a background wash. The single exception is the cook's own
/// burner dial, which *is* the heat.
///
/// Fourteen roles, each with exactly one light value and one dark value. There is no third
/// set. If a screen needs a colour that is not here, the screen is wrong or this file is
/// missing a role — resolve it, do not inline a hex.
///
/// Dark mode is a night-blue parallel: a cold ground so the one warm thing on screen reads
/// hottest. Two roles change in *kind* between modes — see `heatInk` and the shadow note on
/// `Elevation`.
public enum LK {}

// MARK: - Color

public extension LK {
    enum Palette {
        // MARK: Ground
        public static let ground = Color(hex: 0xF4F5F6, dark: 0x0F1622)
        public static let surface = Color(hex: 0xFFFFFF, dark: 0x182231)
        /// Selected segment in a segmented control. Light lifts with a shadow; dark cannot,
        /// so it lifts with a lighter fill.
        public static let surfaceSelected = Color(hex: 0xFFFFFF, dark: 0x33445B)
        /// Unselected chips, icon wells, inert fills.
        public static let chip = Color(hex: 0xE9EBEE, dark: 0x1F2A3A)
        public static let hairline = Color(hex: 0x14161A, alpha: 0.08, dark: 0xFFFFFF, darkAlpha: 0.09)
        /// Chrome sitting on top of a photo.
        public static let photoScrim = Color(hex: 0x14161A, alpha: 0.60, dark: 0x080C14, darkAlpha: 0.70)

        // MARK: Heat — availability only, never affordance
        /// The lamp dot and the burner arc. Does not shift between modes: a light source
        /// does not adapt to the room. Never used for text.
        public static let heat = Color(hex: 0xF0B429)
        /// The paper of a physical print — the Polaroid frame around a cook's
        /// portrait. **Does not adapt**, for the same reason `heat` does not
        /// and for the same reason the photo inside it does not: it is part of
        /// the depicted object, not part of the interface. A Polaroid is white;
        /// a dark one is not a Polaroid, it is a card with a picture on it.
        public static let printPaper = Color(hex: 0xFFFDF8)

        /// The only amber *text* in the app. This role **inverts** between modes — on paper
        /// the readable amber is darker than the lamp, on night blue it must be lighter.
        /// Do not compute one from the other.
        public static let heatInk = Color(hex: 0x7C5500, dark: 0xF3C463)

        // MARK: Affordance — everything tappable
        public static let action = Color(hex: 0x37507F, dark: 0xA8C6F2)
        /// Text and glyphs on a filled action. Inverts with `action`.
        public static let inkOnAction = Color(hex: 0xFFFFFF, dark: 0x10203A)

        // MARK: Ink
        public static let ink = Color(hex: 0x14161A, dark: 0xEAEFF5)
        public static let inkQuiet = Color(hex: 0x55585F, dark: 0xA9B6C6)
        /// Meta lines, caps headers, inactive tabs. 4.55:1 on `ground` — do not lighten.
        public static let inkTertiary = Color(hex: 0x6D7076, dark: 0x8494A8)
        /// Unentered fields and a disabled Save. Deliberately below reading contrast: it
        /// marks the *absence* of content and must not read as content.
        public static let inkPlaceholder = Color(hex: 0xA9ABB0, dark: 0x5D6A7C)
    }
}

// MARK: - Type

public extension LK {
    enum Typography {
        /// Display face. Nothing legibility-critical depends on it — UI text stays on SF.
        ///
        /// No font file has ever shipped for this family and there is no `UIAppFonts` entry,
        /// so `.custom` falls back. The fallback is deliberately **SF Pro Rounded**: if the
        /// display face is missing, something has to carry the product's register. Drop the
        /// real file in and this reverts on its own.
        public static let displayFamily = "BricolageGrotesque"
        private static let displayIsInstalled = UIFont(name: displayFamily, size: 12) != nil

        /// Display type, tabular figures always — price columns misalign without it and
        /// price clarity is the product thesis.
        public static func display(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
            guard displayIsInstalled else {
                return .system(size: size, weight: weight, design: .rounded).monospacedDigit()
            }
            return .custom(displayFamily, size: size).weight(weight).monospacedDigit()
        }

        public static func ui(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
            .system(size: size, weight: weight)
        }

        // MARK: The scale — 28 / 24 / 19 / 17 / 15 / 13.5 / 12 / 10.5
        //
        // There is no 8, 9, 11, 14.5, 16 or 21. If a new size seems necessary, one of the
        // roles below is wrong. Inline `.system(size:)` in feature code is a bug.

        /// Screen title, cook name, dish name on a detail sheet.
        public static var screenTitle: Font { display(28, weight: .bold) }
        /// Price figure on a detail sheet; section title.
        public static var titleSecondary: Font { display(24, weight: .bold) }
        /// Dish name and price figure on a feed card.
        public static var dishNameCard: Font { display(19, weight: .bold) }
        /// Dish name in a grouped list row.
        public static var dishNameRow: Font { display(17, weight: .bold) }

        public static var navBar: Font { ui(17) }
        public static var navBarEmphasis: Font { ui(17, weight: .semibold) }
        public static var fieldValue: Font { ui(16) }
        public static var body: Font { ui(15) }
        public static var bodyEmphasis: Font { ui(15, weight: .semibold) }
        public static var meta: Font { ui(13.5) }
        /// Caps section header. Pair with `capsTracking` and `.textCase(.uppercase)`.
        public static var caps: Font { ui(12, weight: .bold) }
        public static var tabLabel: Font { ui(10.5, weight: .medium) }
        public static var tabLabelActive: Font { ui(10.5, weight: .semibold) }

        public static let capsTracking: CGFloat = 0.6
    }
}

// MARK: - Metrics

public extension LK {
    enum Metrics {
        public static let screenPadding: CGFloat = 20
        public static let feedGutter: CGFloat = 16
        public static let cardGap: CGFloat = 10
        public static let blockSpacing: CGFloat = 14
        public static let innerSpacing: CGFloat = 8

        public static let radiusCard: CGFloat = 20
        public static let radiusInner: CGFloat = 14
        public static let radiusField: CGFloat = 12
        public static let radiusButton: CGFloat = 14
        public static let radiusChip: CGFloat = 999

        /// Apple minimum. Non-negotiable.
        public static let minHitTarget: CGFloat = 44

        public static let cardBorderWidth: CGFloat = 1
    }
}

// MARK: - Elevation

public extension LK {
    /// A card is `surface` + 1px `hairline` + — in light mode only — one soft shadow.
    ///
    /// In dark mode there is **no shadow**. Elevation comes from the surface being lighter
    /// than the ground; a drop shadow at these values is invisible and only muddies the edge.
    enum Elevation {
        public static func cardShadows(_ scheme: ColorScheme) -> [(Color, CGFloat, CGFloat)] {
            guard scheme == .light else { return [] }
            return [
                (Color(hex: 0x14161A, alpha: 0.05), 2, 1),   // colour, radius, y
                (Color(hex: 0x14161A, alpha: 0.05), 20, 8),
            ]
        }
    }
}

// MARK: - Motion

public extension LK {
    /// One animation carries the whole metaphor: the lamp dot breathing.
    ///
    /// The glow colour **must** be the current `Palette.heat`. A hard-coded amber left over
    /// from an older palette will silently win over anything set on the view — this bug was
    /// live once already.
    ///
    /// Stagger `phase` per card (0, 0.7, 1.4, 2.1) so a feed does not throb in unison, and
    /// gate the whole thing behind `UIAccessibility.isReduceMotionEnabled`.
    enum Lamp {
        public static let period: Double = 2.8
        public static let glowMin: CGFloat = 7
        public static let glowMax: CGFloat = 14
        public static let opacityMin: Double = 0.50
        public static let opacityMax: Double = 0.78
        public static let dotSize: CGFloat = 7

        public static func phase(forIndex index: Int) -> Double {
            Double(index % 4) * 0.7
        }
    }

    /// The cook's burner dial — the one large warm object in the app.
    enum Dial {
        public static let outerSize: CGFloat = 172
        public static let innerSize: CGFloat = 146
        public static let pointerSize: CGFloat = 8

        /// In dark mode the arc drops to 80%. At full strength on night blue it is the
        /// brightest thing in the app, and this screen is used in a dim kitchen at arm's
        /// length. The one place the "heat does not adapt" rule bends — and it bends by
        /// opacity, not hue, so it is still the same marigold.
        public static func arcOpacity(_ scheme: ColorScheme) -> Double {
            scheme == .dark ? 0.80 : 1.0
        }
    }
}

// MARK: - Hex helper

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }

    /// Light/dark pair. Dark Mode is a parallel set, not an inversion.
    init(hex light: UInt32, alpha lightAlpha: Double = 1, dark: UInt32, darkAlpha: Double = 1) {
        self.init(uiColor: UIColor { traits in
            let value = traits.userInterfaceStyle == .dark ? dark : light
            let a = traits.userInterfaceStyle == .dark ? darkAlpha : lightAlpha
            return UIColor(
                red: CGFloat((value >> 16) & 0xFF) / 255,
                green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255,
                alpha: a
            )
        })
    }
}

// MARK: - Card elevation

/// The one card shadow, applied the one way.
///
/// `LK.Elevation.cardShadows` returns an empty list in dark mode on purpose: a
/// dark card is a *lighter* surface on a darker ground, and a drop shadow at
/// those values is invisible except as mud around the edge. Reading the scheme
/// from the environment rather than taking a parameter means no call site can
/// forget, which is what "one card, one shadow" has to mean to survive.
private struct LKCardShadow: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        LK.Elevation.cardShadows(scheme).reduce(AnyView(content)) { view, layer in
            AnyView(view.shadow(color: layer.0, radius: layer.1, y: layer.2))
        }
    }
}

public extension View {
    /// Elevation for a `surface` card. Light mode only, by design.
    func lkCardShadow() -> some View { modifier(LKCardShadow()) }
}

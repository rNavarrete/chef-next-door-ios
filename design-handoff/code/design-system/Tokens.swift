import SwiftUI

/// Design tokens from the design handoff ("the kitchen light is on").
///
/// **The one rule that must not erode:** amber marks *heat*, blue marks
/// *affordance*. Amber never appears on a button, badge, or countdown — with
/// exactly one exception, the cook's own burner dial, which *is* the heat.
/// Any other amber control is a bug.
///
/// Dark Mode is a parallel warm-black set, not an inversion: the ground stays
/// warm so photos and Spanish diacritics keep contrast.
public enum LK {}

// MARK: - Color

public extension LK {
    enum Palette {
        // Ink
        public static let ink = Color(hex: 0x14161C, dark: 0xF4F0E9)
        public static let inkSecondary = Color(hex: 0x4A443B, dark: 0xA9A196)
        /// Minimum 4.5:1 on paper. Do not lighten.
        public static let inkTertiary = Color(hex: 0x6B6357, dark: 0x8E877C)

        // Ground
        public static let paper = Color(hex: 0xFAF6EF, dark: 0x15130F)
        public static let paperAlt = Color(hex: 0xF6F2EA, dark: 0x1B1813)
        public static let surface = Color(hex: 0xFFFFFF, dark: 0x211D18)
        public static let surfaceWarm = Color(hex: 0xFFF6E8, dark: 0x2A2118)
        public static let chipNeutral = Color(hex: 0xF1ECE2, dark: 0x2A251E)
        public static let hairline = Color(hex: 0x14161C, alpha: 0.09, dark: 0xFFFFFF, darkAlpha: 0.10)

        // MARK: Heat — availability only, never affordance
        /// Amber is light: it does not shift between modes.
        public static let lamp = Color(hex: 0xF5A524)
        public static let lampBright = Color(hex: 0xFFC35C)
        /// Text on amber tints. 4.5:1+.
        public static let lampInk = Color(hex: 0x8A5A00, dark: 0xF0BE6B)
        public static let lampInkDeep = Color(hex: 0xB87400, dark: 0xF5A524)
        public static let lampTint = Color(hex: 0xFFF3DF, dark: 0x33270F)
        public static let lampPointer = Color(hex: 0xC97F0A)

        // MARK: Affordance — everything tappable
        public static let action = Color(hex: 0x1A6FBE, dark: 0x5AA6E8)
        public static let actionPressed = Color(hex: 0x145C9E, dark: 0x7FBCF0)
        public static let actionTint = Color(hex: 0xEFF4FA, dark: 0x16202B)

        // Allergens — a safety surface
        public static let allergenInk = Color(hex: 0x8F4517, dark: 0xE8A579)
        public static let allergenBG = Color(hex: 0xFBE9DF, dark: 0x2E1B10)

        /// Unused since the map moved to daylight — the surface these were
        /// built for no longer exists. Kept because a night mode for the map
        /// is still plausible; delete them if that stops being true.
        public static let duskMapTop = Color(hex: 0x1E2C3E)
        public static let duskMapMid = Color(hex: 0x141E2A)
        public static let duskMapBottom = Color(hex: 0x0D141D)
    }
}

// MARK: - Type

public extension LK {
    enum Typography {
        /// Display face. Nothing legibility-critical depends on it — UI text
        /// stays on SF.
        public static let displayFamily = "BricolageGrotesque"

        /// Whether the display face is actually installed.
        ///
        /// It never has been. The family is named here and nowhere else: there
        /// is no font file in the repository and no `UIAppFonts` entry in
        /// `project.yml`, so `.custom` has been falling back to plain
        /// system type since the tokens were written. Every screen title, dish
        /// name and price in the app has been rendering as stock SF Pro while
        /// claiming to be a display face.
        private static let displayIsInstalled = UIFont(name: displayFamily, size: 12) != nil

        /// Display type with **tabular figures**, always.
        ///
        /// Measured: Bricolage's proportional digits vary by up to 12.5px at
        /// 40px and flatten to a 0px spread with the feature on. Price columns
        /// misalign without it, and price clarity is the product thesis.
        ///
        /// The fallback is **SF Pro Rounded**, not SF Pro. If the display face
        /// is missing, something has to carry the app's character, and rounded
        /// is the register this product wants — neighbours cooking dinner, not
        /// a logistics dashboard. Drop the font file in and this reverts to
        /// Bricolage on its own.
        public static func display(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
            guard displayIsInstalled else {
                return .system(size: size, weight: weight, design: .rounded)
                    .monospacedDigit()
            }
            return .custom(displayFamily, size: size)
                .weight(weight)
                .monospacedDigit()
        }

        public static func ui(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
            .system(size: size, weight: weight)
        }

        // Roles from the handoff
        public static var screenTitle: Font { display(36, weight: .heavy) }
        public static var screenTitleSecondary: Font { display(26, weight: .heavy) }
        public static var cookNameDetail: Font { display(30, weight: .bold) }
        public static var dishNameCard: Font { display(21, weight: .bold) }
        public static var dishNameRow: Font { display(18, weight: .bold) }
        public static var priceFigure: Font { display(22, weight: .bold) }
        public static var priceUnit: Font { ui(15, weight: .semibold) }
        public static var body: Font { ui(16) }
        public static var meta: Font { ui(14) }
        public static var availabilityLabel: Font { ui(12, weight: .bold) }
    }
}

// MARK: - Metrics

public extension LK {
    enum Metrics {
        public static let screenPadding: CGFloat = 20
        public static let feedGutter: CGFloat = 16
        public static let blockSpacing: CGFloat = 14
        public static let innerSpacing: CGFloat = 8

        public static let radiusCard: CGFloat = 28
        public static let radiusList: CGFloat = 15
        public static let radiusField: CGFloat = 12
        public static let radiusButton: CGFloat = 14
        public static let radiusThumb: CGFloat = 14

        /// Apple minimum. Non-negotiable.
        public static let minHitTarget: CGFloat = 44
    }
}

// MARK: - Glow

public extension LK {
    /// Glow is not decoration — it is how "open" reads before any word does.
    /// Intensity is driven by the decay tier, so a dimming kitchen is visibly
    /// dimmer without a word changing.
    struct Glow: Sendable {
        public let radius: CGFloat
        public let opacity: Double
        public let ringOpacity: Double

        public static func forTier(_ tier: FreshnessTier) -> Glow {
            switch tier {
            case .lit: Glow(radius: 20, opacity: 0.22, ringOpacity: 0.35)
            case .dimming: Glow(radius: 8, opacity: 0.09, ringOpacity: 0.16)
            case .unconfirmed, .out: Glow(radius: 0, opacity: 0, ringOpacity: 0)
            }
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

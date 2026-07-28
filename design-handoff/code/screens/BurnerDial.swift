import SwiftUI

/// The burner. One tap, either direction.
///
/// This used to be asymmetric — tap to open, hold 0.9s to close — on the
/// reasoning that an accidental *close* costs a cook their afternoon while an
/// accidental *open* is harmless. Sound reasoning, but the hold **did not work
/// on device**: `.onTapGesture` and `.gesture(LongPressGesture)` were attached
/// to the same view, the tap recogniser competed with the long press, and cooks
/// pressing and holding got nothing at all. A safety mechanism nobody can
/// operate is not a safety mechanism; it is a kitchen that cannot be closed.
///
/// What guards the accidental close now is what happens after it: closing
/// raises the close-out sheet, so the cook sees immediately that it happened,
/// and reopening is the same single tap.
///
/// Only the pointer rotates. The `ON` / `since 9:58 am` labels stay upright, so
/// the state is readable at arm's length with wet hands.
struct BurnerDial: View {
    var isOn: Bool
    /// False for a kitchen that has never served. Only affects the resting
    /// label — "cooking again" is wrong on the very first day, and this dial is
    /// the thing a new cook looks at longest.
    var hasEverOpened: Bool = true
    var sinceLabel: String?
    /// Fired for both directions — the caller knows which way `isOn` is
    /// pointing and what closing entails.
    var onToggle: () -> Void

    @State private var pointerAngle: Double = -42

    private let size: CGFloat = 168

    var body: some View {
        ZStack {
            if isOn {
                Circle()
                    .fill(LK.Palette.lamp.opacity(0.18))
                    .frame(width: size * 2.2, height: size * 2.2)
                    .blur(radius: 44)
                    .allowsHitTesting(false)
            }

            Circle()
                .fill(
                    RadialGradient(
                        colors: isOn
                            ? [Color(hex: 0xFFF6E8), Color(hex: 0xF7EBD6)]
                            : [Color(hex: 0xF2EEE6), Color(hex: 0xE8E3D9)],
                        center: .init(x: 0.4, y: 0.35),
                        startRadius: 4,
                        endRadius: size * 0.8
                    )
                )
                .frame(width: size, height: size)
                .overlay {
                    Circle().strokeBorder(
                        isOn ? LK.Palette.lamp.opacity(0.18) : LK.Palette.hairline,
                        lineWidth: 10
                    )
                }
                .overlay {
                    Circle().strokeBorder(
                        isOn ? LK.Palette.lamp.opacity(0.5) : LK.Palette.hairline,
                        lineWidth: 2
                    )
                    .padding(12)
                }
                .shadow(color: isOn ? LK.Palette.lamp.opacity(0.4) : .clear, radius: 34)

            // The pointer — the only thing that rotates.
            Capsule()
                .fill(isOn ? LK.Palette.lampPointer : LK.Palette.inkTertiary.opacity(0.5))
                .frame(width: 6, height: 34)
                .offset(y: -(size / 2) + 26)
                .rotationEffect(.degrees(isOn ? pointerAngle : 180))

            VStack(spacing: 3) {
                Text(isOn ? "ON" : "OFF")
                    // Through the token, not `.custom` directly — otherwise
                    // this one label skips the display face's fallback and
                    // renders in plain system while every other display string
                    // in the app is rounded.
                    .font(LK.Typography.display(30, weight: .heavy))
                    .foregroundStyle(isOn ? LK.Palette.lampInkDeep : LK.Palette.inkTertiary)
                if let sinceLabel, isOn {
                    Text(sinceLabel)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(LK.Palette.lampInk.opacity(0.85))
                } else if !isOn {
                    // Says what the finger does. The control still *looks*
                    // like a knob, but nothing here responds to a rotation.
                    Text(hasEverOpened
                         ? "Tap when you're\ncooking again"
                         : "Tap to turn\nyour light on")
                        .font(.system(size: 11))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(LK.Palette.inkTertiary)
                }
            }
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .onTapGesture {
            withAnimation(.spring(response: 0.9, dampingFraction: 0.55)) {
                pointerAngle = isOn ? -42 : 0
            }
            onToggle()
        }
        .accessibilityElement()
        .accessibilityLabel("Burner")
        .accessibilityValue(isOn ? "on, \(sinceLabel ?? "")" : "off")
        .accessibilityHint(isOn ? "Double tap to turn off" : "Double tap to turn on")
        .accessibilityAddTraits(.isButton)
    }
}

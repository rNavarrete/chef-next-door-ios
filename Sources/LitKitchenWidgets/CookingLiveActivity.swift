import ActivityKit
import SwiftUI
import WidgetKit

/// Lock Screen and Dynamic Island presentation for an active claim.
///
/// Amber marks heat, blue marks affordance — the rule holds here too. The lamp
/// dot is amber; both buttons are blue. There is no amber control.
struct CookingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CookingActivityAttributes.self) { context in
            LockScreenCard(context: context)
                .activityBackgroundTint(Color(red: 0.98, green: 0.965, blue: 0.937))
                .activitySystemActionForegroundColor(Color(red: 0.08, green: 0.086, blue: 0.11))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    LampDot(isLit: context.state.lampIsLit)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.priceSummary)
                        .font(.system(size: 15, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text("\(context.attributes.cookName) \(context.state.headline)")
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 8) {
                        // Was `contactURL` — an `sms:` link with no recipient,
                        // pointing at a handoff the app no longer does. Opens
                        // the thread instead, where the order already is.
                        Link(destination: URL(string: "litkitchen://thread/\(context.attributes.threadID)")!) {
                            Text("Message \(context.attributes.cookName)")
                                .font(.system(size: 15, weight: .semibold))
                                .frame(maxWidth: .infinity)
                        }
                        // Absent while waiting: there is no address yet, and a
                        // Directions button that goes nowhere is worse than no
                        // button.
                        if let directions = context.state.directionsURL {
                            Link(destination: directions) {
                                Text("Directions")
                                    .font(.system(size: 15, weight: .semibold))
                                    .frame(maxWidth: .infinity)
                            }
                        }
                    }
                    .tint(Color(red: 0.102, green: 0.435, blue: 0.745))
                }
            } compactLeading: {
                LampDot(isLit: context.state.lampIsLit, size: 8)
            } compactTrailing: {
                Text(context.state.priceSummary)
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
            } minimal: {
                LampDot(isLit: context.state.lampIsLit, size: 8)
            }
            .widgetURL(URL(string: "litkitchen://thread/\(context.attributes.threadID)"))
        }
    }
}

private struct LockScreenCard: View {
    let context: ActivityViewContext<CookingActivityAttributes>

    private let ink = Color(red: 0.08, green: 0.086, blue: 0.11)
    private let inkTertiary = Color(red: 0.42, green: 0.388, blue: 0.341)
    private let action = Color(red: 0.102, green: 0.435, blue: 0.745)

    /// Stale wins over the address: by this point the buyer knows where the
    /// kitchen is, and what the card is for is closing the claim out.
    private var staleOrAddressLine: String {
        if context.isStale {
            return "Tap to mark it picked up — it's how \(context.attributes.cookName) knows it's done."
        }
        return context.state.stage == .confirmed
            ? context.state.addressLine
            : "You'll get the address when \(context.attributes.cookName) says yes."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                LampDot(isLit: context.state.lampIsLit && !context.isStale)
                // Once the card is stale the lamp stops asserting anything and
                // the line becomes a question. This is the only nudge that
                // works without push: the system flips `isStale` at the date we
                // set, with no server and no app running.
                // No cook name here. With it, this line read "FATIMA H. HASN'T
                // ANSWERED YET SINCE 9:06…" on a real Lock Screen — clipped at
                // exactly the timestamp, which is the one piece of information
                // the line exists to carry. The name is already on the card
                // twice below (the sentence and the button), so spending the
                // width on a third mention is what pushed the clock off the
                // edge. State and time only, same shape as the feed's
                // "COOKING · SINCE 8:08 PM".
                Text(context.isStale
                     ? "Did you pick this up?"
                     : "\(context.state.headline) \(context.state.sinceLabel)"
                    )
                    .font(.system(size: 12, weight: .bold))
                    .textCase(.uppercase)
                    .tracking(0.3)
                    .foregroundStyle(Color(red: 0.541, green: 0.353, blue: 0))
                    .lineLimit(1)
                    // Belt and braces: a longer localisation or a wider clock
                    // format shrinks rather than dropping the time again.
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(context.state.itemSummary)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(ink)
                Text(context.state.priceSummary)
                    .font(.system(size: 15, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(inkTertiary)
                Spacer(minLength: 0)
            }

            // While waiting this says what happens next instead of standing
            // empty. The card is most useful precisely when there's no address
            // yet, so that line has to carry its own weight.
            Text(staleOrAddressLine)
                .font(.system(size: 14))
                .foregroundStyle(inkTertiary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Link(destination: URL(string: "litkitchen://thread/\(context.attributes.threadID)")!) {
                    Text("Message \(context.attributes.cookName)")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(action, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
                // Directions stop being the useful action once the pickup has
                // almost certainly happened; marking it done starts being one.
                if context.isStale {
                    Link(destination: URL(string: "litkitchen://thread/\(context.attributes.threadID)")!) {
                        Text("I picked it up")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 34)
                            .background(action, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    }
                } else if let directions = context.state.directionsURL {
                    Link(destination: directions) {
                        Text("Directions")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(action)
                            .frame(maxWidth: .infinity, minHeight: 34)
                            .background(
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .strokeBorder(action.opacity(0.35), lineWidth: 1)
                            )
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Opaque, and drawn by us.
        //
        // `activityBackgroundTint` alone is a *tint*, not a fill: the system
        // composites it over the wallpaper. On a warm Lock Screen photo the
        // cream came out gold with the wallpaper banding straight through it,
        // and the card's colour changed with whatever the user had set behind
        // it. A card whose palette depends on someone's wallpaper cannot hold
        // "amber marks heat" — the amber status line was competing with an
        // amber background. The tint stays as the fallback for the region the
        // system draws around this view.
        .background(Color(red: 0.98, green: 0.965, blue: 0.937))
    }
}

/// The lamp. Amber, and the only amber thing on the card.
struct LampDot: View {
    var isLit: Bool
    var size: CGFloat = 9

    private let lamp = Color(red: 0.961, green: 0.647, blue: 0.141)

    var body: some View {
        Circle()
            .fill(isLit ? lamp : Color.clear)
            .overlay {
                if !isLit {
                    Circle().strokeBorder(Color(red: 0.788, green: 0.604, blue: 0.271), lineWidth: 2)
                }
            }
            .frame(width: size, height: size)
            // Glow is how "lit" reads before any word does. Static, not
            // animated: Live Activities do not run continuous animation, and
            // pretending otherwise would just burn budget.
            .shadow(color: isLit ? lamp.opacity(0.55) : .clear, radius: 4)
    }
}

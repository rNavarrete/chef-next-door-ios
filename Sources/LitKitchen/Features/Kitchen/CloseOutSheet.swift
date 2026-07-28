import SwiftUI

/// An order the cook hasn't closed out.
public struct OpenOrder: Codable, Sendable, Identifiable, Hashable {
    public var id: UUID { conversationID }
    public let conversationID: UUID
    public let buyerName: String
    public let itemSummary: String?
    public let totalCents: Int?
    public let addressShared: Bool
    public let orderedAt: Date

    enum CodingKeys: String, CodingKey {
        case conversationID = "conversation_id"
        case buyerName = "buyer_name"
        case itemSummary = "item_summary"
        case totalCents = "total_cents"
        case addressShared = "address_shared"
        case orderedAt = "ordered_at"
    }
}

/// Presentation payload, so the orders travel with the sheet instead of being
/// read from view state at present time.
struct CloseOutPrompt: Identifiable {
    let id = UUID()
    let orders: [OpenOrder]
}

/// Shown when a cook closes their kitchen with orders still open.
///
/// Closing is the one moment a cook is both finished and definitely looking at
/// the app, which makes it the only reliable place to ask. Nothing else marks
/// an order done: without this the record accumulates orders that never
/// resolved, and the buyer's review — which gates on pickup — never becomes
/// possible.
///
/// **Rebuilt from claims onto conversations** (`migrations/045`). It read
/// `claim_inbox`, which after 043 still worked and still returned nothing: the
/// sheet would have opened forever showing zero orders, telling a cook nobody
/// was waiting when someone was. A silent no-op is worse than a missing
/// feature, because nobody goes looking for it.
///
/// Deliberately skippable. A cook who genuinely doesn't remember should say
/// nothing rather than guess, because a pickup is evidence a handoff happened
/// (`PRD.md` §8, `COUNSEL_QUESTIONS.md` Q3) and a guess is worse than silence.
struct CloseOutSheet: View {
    let orders: [OpenOrder]
    /// `true` when the food changed hands; `false` when they never came.
    var onResolve: (OpenOrder, Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var resolved: Set<UUID> = []

    private var remaining: [OpenOrder] {
        orders.filter { !resolved.contains($0.id) }
    }

    private static let clock: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: LK.Metrics.blockSpacing) {
                    Text(remaining.isEmpty
                         ? "All closed out"
                         : remaining.count == 1
                           ? "One order is still open"
                           : "\(remaining.count) orders are still open")
                        .font(LK.Typography.titleSecondary)
                        .foregroundStyle(LK.Palette.ink)

                    Text(remaining.isEmpty
                         ? "Thanks — that keeps your reviews honest."
                         : "Did these get picked up? Marking them closes them out, and lets those buyers leave a review.")
                        .font(LK.Typography.body)
                        .foregroundStyle(LK.Palette.inkQuiet)
                        .fixedSize(horizontal: false, vertical: true)

                    if !remaining.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(Array(remaining.enumerated()), id: \.element.id) { index, order in
                                if index > 0 {
                                    Rectangle().fill(LK.Palette.hairline).frame(height: 1)
                                }
                                row(for: order)
                            }
                        }
                        .background(
                            LK.Palette.surface,
                            in: RoundedRectangle(cornerRadius: LK.Metrics.radiusInner, style: .continuous)
                        )
                    }
                }
                .padding(LK.Metrics.screenPadding)
            }
            .background(LK.Palette.ground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(remaining.isEmpty ? "Done" : "Not now") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .tint(LK.Palette.action)
    }

    private func row(for order: OpenOrder) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(order.buyerName)
                    .font(LK.Typography.bodyEmphasis)
                    .foregroundStyle(LK.Palette.ink)
                    .lineLimit(1)
                Text(order.itemSummary ?? "—")
                    .font(LK.Typography.meta)
                    .foregroundStyle(LK.Palette.inkQuiet)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(Self.clock.string(from: order.orderedAt).lowercased())
                    // A cook who never shared their address almost certainly
                    // never meant to serve this one, and shouldn't be nudged
                    // into calling a stranger a no-show.
                    if !order.addressShared {
                        Text("· address never shared")
                    }
                }
                .font(LK.Typography.meta)
                .foregroundStyle(LK.Palette.inkTertiary)
            }
            Spacer(minLength: 8)

            Button("Didn't come") {
                resolved.insert(order.id)
                onResolve(order, false)
            }
            .font(LK.Typography.ui(13.5, weight: .semibold))
            .foregroundStyle(LK.Palette.inkTertiary)
            .buttonStyle(.plain)

            Button("Picked up") {
                resolved.insert(order.id)
                onResolve(order, true)
            }
            .font(LK.Typography.ui(13.5, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(LK.Palette.action, in: Capsule())
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}

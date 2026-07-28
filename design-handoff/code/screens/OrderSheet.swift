import SwiftUI

/// Picking dishes, which posts a priced order into the conversation.
///
/// Replaces `ClaimSheet`. The picker is much the same — a person still chooses
/// dishes and quantities — but what comes out the other end is a message in a
/// thread rather than a "claim" the buyer had to learn the meaning of. The cook
/// reads an itemised card and replies; there is no separate object to accept.
///
/// Prices shown here are for the buyer's benefit only. `post_order` resolves
/// every price server-side from `menu_items`, so nothing typed or tampered with
/// on this screen can change what the cook is quoted.
struct OrderSheet: View {
    let cookName: String
    let menu: [MenuItem]
    var onSend: ([(MenuItem, Int)], String?) async -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var quantities: [UUID: Int] = [:]
    @State private var note = ""
    @State private var isSending = false

    private var available: [MenuItem] { menu.filter(\.isAvailable) }

    private var chosen: [(MenuItem, Int)] {
        available.compactMap { item in
            let quantity = quantities[item.id] ?? 0
            return quantity > 0 ? (item, quantity) : nil
        }
    }

    private var totalCents: Int {
        // `Price.totalCents(quantity:)`, not `amountCents * quantity`. The
        // model's version applies the minimum — `amountCents * max(quantity,
        // minQuantity)` — so a hand-rolled multiply here produced a *different
        // total from the same data*: this sheet quoted $3.00 for one tamale
        // where the model said $9.00. Two totals in one codebase is one too
        // many, and the buyer was being shown the one the cook can't honour.
        chosen.reduce(0) { $0 + $1.0.price.totalCents(quantity: $1.1) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: LK.Metrics.blockSpacing) {
                    Text("What would you like?")
                        .font(LK.Typography.screenTitleSecondary)
                        .foregroundStyle(LK.Palette.ink)

                    VStack(spacing: 0) {
                        ForEach(Array(available.enumerated()), id: \.element.id) { index, item in
                            row(for: item)
                            if index < available.count - 1 {
                                Rectangle().fill(LK.Palette.hairline).frame(height: 1)
                            }
                        }
                    }
                    .background(LK.Palette.surface,
                                in: RoundedRectangle(cornerRadius: LK.Metrics.radiusList, style: .continuous))

                    GroupedCard {
                        LabeledField(
                            label: "Note", text: $note,
                            placeholder: "Optional — allergies, timing", autocorrects: true
                        )
                    }

                    Text("\(cookName) sees this as a message and replies to you. Nothing is charged here — you pay them directly.")
                        .font(LK.Typography.meta)
                        .foregroundStyle(LK.Palette.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(LK.Metrics.screenPadding)
            }
            .background(LK.Palette.paper)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) { sendBar }
        }
    }

    private func row(for item: MenuItem) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.displayName())
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(LK.Palette.ink)
                // `displayWithMinimum`, matching the feed card and the cook's
                // menu. This sheet was the one place that dropped the "· min 3"
                // — the single screen where the number actually constrains what
                // the buyer may do.
                Text(item.price.displayWithMinimum)
                    .font(LK.Typography.meta)
                    .foregroundStyle(LK.Palette.inkSecondary)
            }
            Spacer(minLength: 8)

            // The count sits *outside* the Stepper. Putting it in the Stepper's
            // label looks right in code and renders as nothing: `.labelsHidden()`
            // hides the label, which was the number — so the buyer had two
            // buttons and no idea how many they had picked.
            Text("\(quantities[item.id] ?? 0)")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(
                    (quantities[item.id] ?? 0) > 0 ? LK.Palette.ink : LK.Palette.inkTertiary
                )
                .monospacedDigit()
                .frame(minWidth: 24)

            // Steps 0 → minimum → minimum+1. `in: 0...99` let a buyer send an
            // order for one tamale from a cook with a three-tamale minimum —
            // an order that cannot be filled, which the cook then has to
            // decline by hand. The minimum is shown on the feed card, on the
            // menu, and was enforced nowhere.
            Stepper(
                value: Binding(
                    get: { quantities[item.id] ?? 0 },
                    set: { newValue in
                        let current = quantities[item.id] ?? 0
                        let minimum = item.price.minQuantity
                        if newValue > current {
                            // First step off zero lands on the minimum, not 1.
                            quantities[item.id] = max(newValue, minimum)
                        } else {
                            // Stepping below the minimum means "none", because
                            // there is no valid quantity between 0 and it.
                            quantities[item.id] = newValue < minimum ? 0 : newValue
                        }
                    }
                ),
                in: 0...99
            ) { EmptyView() }
            .labelsHidden()
            .fixedSize()
            .accessibilityLabel("\(item.displayName()) quantity")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private var sendBar: some View {
        VStack(spacing: 8) {
            if !chosen.isEmpty {
                HStack {
                    Text("Total")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(LK.Palette.inkSecondary)
                    Spacer()
                    Text(String(format: "$%.2f", Double(totalCents) / 100))
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(LK.Palette.ink)
                        .monospacedDigit()
                }
            }

            Button {
                Task {
                    isSending = true
                    await onSend(chosen, note.isEmpty ? nil : note)
                    isSending = false
                    dismiss()
                }
            } label: {
                ZStack {
                    Text(chosen.isEmpty ? "Pick something" : "Send to \(cookName)")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .opacity(isSending ? 0 : 1)
                    if isSending { ProgressView().tint(.white) }
                }
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(
                    chosen.isEmpty ? LK.Palette.inkTertiary : LK.Palette.action,
                    in: RoundedRectangle(cornerRadius: LK.Metrics.radiusButton, style: .continuous)
                )
            }
            .buttonStyle(.plain)
            .disabled(chosen.isEmpty || isSending)
        }
        .padding(.horizontal, LK.Metrics.screenPadding)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }
}

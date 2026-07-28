import SwiftUI

/// A cook reporting a buyer.
///
/// Mirrors `ReportSheet` (buyer → cook) but routes somewhere different, and the
/// wording says so. A food-safety complaint about a kitchen is the enforcement
/// agency's business and the app hands back the agency name; this goes to us
/// and nowhere else, so promising a regulator would be a lie.
///
/// Blocking is pre-checked. Reporting someone you then have to keep hearing
/// from is not a resolution — but it stays a checkbox, because "this happened,
/// and I'll still serve them" is a real answer a cook is entitled to give.
struct ReportBuyerSheet: View {
    let threadID: UUID
    let buyerName: String
    let repository: any MessageRepository
    var onDone: () -> Void = {}

    @Environment(\.dismiss) private var dismiss

    @State private var kind: BuyerReportKind = .harassment
    @State private var note = ""
    @State private var alsoBlock = true
    @State private var isSending = false
    @State private var error = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: LK.Metrics.blockSpacing) {
                    Text("What happened?")
                        .font(LK.Typography.titleSecondary)
                        .foregroundStyle(LK.Palette.ink)

                    VStack(spacing: 0) {
                        ForEach(Array(BuyerReportKind.allCases.enumerated()), id: \.offset) { index, option in
                            Button { kind = option } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: kind == option
                                          ? "largecircle.fill.circle" : "circle")
                                        .foregroundStyle(kind == option
                                                         ? LK.Palette.action : LK.Palette.inkTertiary)
                                    Text(option.label)
                                        .font(LK.Typography.body)
                                        .foregroundStyle(LK.Palette.ink)
                                        .multilineTextAlignment(.leading)
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            if index < BuyerReportKind.allCases.count - 1 {
                                Rectangle().fill(LK.Palette.hairline)
                                    .frame(height: 1).padding(.leading, 40)
                            }
                        }
                    }
                    .background(LK.Palette.surface,
                                in: RoundedRectangle(cornerRadius: LK.Metrics.radiusInner, style: .continuous))

                    GroupedCard {
                        LabeledField(
                            label: "Details", text: $note,
                            placeholder: "Optional", autocorrects: true
                        )
                    }

                    Toggle(isOn: $alsoBlock) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Also block \(buyerName)")
                                .font(LK.Typography.body)
                                .foregroundStyle(LK.Palette.ink)
                            Text("They stop being able to message you or order from your kitchen. They aren't told.")
                                .font(LK.Typography.meta)
                                .foregroundStyle(LK.Palette.inkTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .tint(LK.Palette.action)

                    Text("This goes to us, not to a health department. If it's about food safety at a kitchen, report the kitchen instead.")
                        .font(LK.Typography.meta)
                        .foregroundStyle(LK.Palette.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)

                    if !error.isEmpty {
                        Text(error)
                            .font(LK.Typography.meta)
                            .foregroundStyle(LK.Palette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button {
                        Task { await send() }
                    } label: {
                        ZStack {
                            Text("Send report")
                                .font(LK.Typography.navBarEmphasis)
                                .foregroundStyle(.white)
                                .opacity(isSending ? 0 : 1)
                            if isSending { ProgressView().tint(.white) }
                        }
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(LK.Palette.action,
                                    in: RoundedRectangle(cornerRadius: LK.Metrics.radiusButton, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isSending)
                }
                .padding(LK.Metrics.screenPadding)
            }
            .background(LK.Palette.ground)
            .navigationTitle("Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func send() async {
        isSending = true
        defer { isSending = false }
        error = ""
        do {
            try await repository.reportBuyer(
                in: threadID, kind: kind,
                note: note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : note,
                alsoBlock: alsoBlock
            )
            onDone()
            dismiss()
        } catch {
            self.error = UserFacingError.message(
                for: error, fallback: "Couldn't send that report. Try again."
            )
        }
    }
}

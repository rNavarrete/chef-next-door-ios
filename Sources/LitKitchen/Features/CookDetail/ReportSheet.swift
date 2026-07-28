import SwiftUI

/// Reporting a kitchen.
///
/// The important thing this screen does is **not** pretend we are the
/// regulator. A food-safety complaint belongs to the enforcement agency for
/// that kitchen — which differs by city — so the confirmation hands back the
/// agency's name rather than "thanks, we'll look into it" (`PRD.md` §8).
struct ReportSheet: View {
    @Environment(\.dismiss) private var dismiss

    let cookID: UUID
    let cookName: String
    var claimID: UUID?

    @State private var kind: ComplaintKind?
    @State private var body_ = ""
    @State private var isSending = false
    @State private var outcome: ReportOutcome?
    @State private var errorMessage: String?

    private let trust = TrustRepository()

    var body: some View {
        NavigationStack {
            ScrollView {
                if let outcome {
                    confirmation(outcome)
                } else {
                    form
                }
            }
            .background(LK.Palette.ground)
            .navigationTitle(outcome == nil ? "Report \(cookName)" : "Reported")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(outcome == nil ? "Cancel" : "Done") { dismiss() }
                }
                if outcome == nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Send") { send() }
                            .fontWeight(.semibold)
                            .disabled(kind == nil || isSending)
                    }
                }
            }
        }
        .tint(LK.Palette.action)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("What happened?")
                .font(LK.Typography.titleSecondary)
                .foregroundStyle(LK.Palette.ink)

            VStack(spacing: 0) {
                ForEach(Array(ComplaintKind.allCases.enumerated()), id: \.element) { index, option in
                    if index > 0 { Divider().overlay(LK.Palette.hairline).padding(.leading, 14) }
                    Button {
                        kind = option
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: kind == option ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(kind == option ? LK.Palette.action : LK.Palette.inkTertiary)
                            Text(option.label)
                                .font(LK.Typography.body)
                                .foregroundStyle(LK.Palette.ink)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                        }
                        .padding(14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(LK.Palette.surface, in: RoundedRectangle(cornerRadius: LK.Metrics.radiusInner, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: LK.Metrics.radiusInner, style: .continuous)
                    .strokeBorder(LK.Palette.hairline, lineWidth: 0.5)
            }

            GroupedCard {
                TextField("What should we know? (optional)", text: $body_, axis: .vertical)
                    .font(LK.Typography.body)
                    .lineLimit(3...6)
                    .autocorrectionDisabled()
                    .padding(14)
            }

            // Said before sending, not after, so nobody discovers afterwards
            // that the thing they reported goes somewhere else.
            if let kind, kind.isForAgency {
                Text("Illness and unsafe handling are investigated by the county or city health department, not by us. We'll show you who to contact and keep a record of your report.")
                    .font(LK.Typography.meta)
                    .foregroundStyle(LK.Palette.inkQuiet)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(LK.Typography.meta)
                    .foregroundStyle(LK.Palette.ink)
            }
        }
        .padding(LK.Metrics.screenPadding)
    }

    private func confirmation(_ outcome: ReportOutcome) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(outcome.isFoodSafety ? "Report the illness to the health department" : "Thanks — we've logged it")
                .font(LK.Typography.titleSecondary)
                .foregroundStyle(LK.Palette.ink)
                .fixedSize(horizontal: false, vertical: true)

            if outcome.isFoodSafety, let agency = outcome.agencyName {
                Text("This kitchen is enforced by **\(agency)**. They investigate foodborne illness; we can't. Your report is on file here, and we'll act on our side if there's a pattern.")
                    .font(LK.Typography.body)
                    .foregroundStyle(LK.Palette.inkQuiet)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("We've recorded it against this kitchen. If we see a pattern we'll act on it.")
                    .font(LK.Typography.body)
                    .foregroundStyle(LK.Palette.inkQuiet)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("If you'd rather not see this kitchen again, you can block it from their page.")
                .font(LK.Typography.meta)
                .foregroundStyle(LK.Palette.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(LK.Metrics.screenPadding)
    }

    private func send() {
        guard let kind else { return }
        isSending = true
        errorMessage = nil
        Task {
            defer { isSending = false }
            do {
                outcome = try await trust.report(
                    cookID: cookID, kind: kind, body: body_, claimID: claimID
                )
            } catch {
                errorMessage = "Couldn't send that report. Try again in a moment."
            }
        }
    }
}

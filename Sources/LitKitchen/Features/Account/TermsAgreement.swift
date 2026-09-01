import SwiftUI

/// Whether this person has agreed to the terms.
///
/// Guideline 1.2 requires the agreement *before* registering or logging in, so
/// this cannot live on the account — there is no account yet at the moment it
/// has to be answered. It is a device-local flag, set by an explicit tap.
enum TermsAgreement {
    private static let key = "hasAgreedToTermsV1"

    static var isAccepted: Bool {
        UserDefaults.standard.bool(forKey: key)
    }

    static func accept() {
        UserDefaults.standard.set(true, forKey: key)
    }

    /// Versioned key, so a future revision of the terms can ask again by
    /// bumping it rather than by silently treating an old agreement as consent
    /// to something the person never read.
    static func reset() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

/// The consent row that stands in front of every way into an account.
///
/// A checkbox rather than the usual "by continuing you agree…" small print.
/// The guideline says *require that users agree*, and a line of text under a
/// button is not a thing anyone agrees to — it is a thing they walk past. A
/// reviewer looking for this feature also has to be able to see it, and an
/// unticked box in front of a disabled button is unmissable.
struct AgreementGate: View {
    @Binding var isAccepted: Bool
    @State private var showingTerms = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                isAccepted.toggle()
                if isAccepted { TermsAgreement.accept() }
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: isAccepted ? "checkmark.square.fill" : "square")
                        .font(LK.Typography.ui(19))
                        .foregroundStyle(isAccepted ? LK.Palette.action : LK.Palette.inkTertiary)
                        .accessibilityHidden(true)

                    Text("I agree to the Terms of Use, and I understand there is no tolerance for objectionable content or abusive behaviour.")
                        .font(LK.Typography.meta)
                        .foregroundStyle(LK.Palette.inkQuiet)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("I agree to the Terms of Use")
            .accessibilityValue(isAccepted ? "Agreed" : "Not agreed")
            .accessibilityAddTraits(isAccepted ? [.isSelected] : [])

            Button("Read the Terms of Use") { showingTerms = true }
                .font(LK.Typography.meta)
                .foregroundStyle(LK.Palette.action)
                .padding(.leading, 29)
                .frame(minHeight: 34)
        }
        .sheet(isPresented: $showingTerms) { TermsView() }
    }
}

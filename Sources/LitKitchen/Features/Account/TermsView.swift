import SwiftUI

/// The terms a person agrees to before they can sign in.
///
/// Required by App Store Review Guideline 1.2, which is not satisfied by a
/// privacy policy: an app carrying user-generated content must present terms
/// that "make it clear that there is no tolerance for objectionable content or
/// abusive users", and the person must actually agree to them *before*
/// registering or logging in — not find them later in a settings screen.
///
/// Rejected on 30 August 2026 for exactly this. Reporting and blocking already
/// existed on both sides and the discovery feed already filters blocked cooks
/// server-side; the agreement was the only one of the four required precautions
/// genuinely missing.
///
/// Carried in the binary rather than fetched. A person offline, or behind a
/// captive portal in someone's kitchen, must still be able to read what they
/// are agreeing to — and a reviewer must not be blocked by our web host.
struct TermsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(Self.sections, id: \.heading) { section in
                        VStack(alignment: .leading, spacing: 7) {
                            Text(section.heading)
                                .font(LK.Typography.titleSecondary)
                                .foregroundStyle(LK.Palette.ink)
                            Text(section.body)
                                .font(LK.Typography.body)
                                .foregroundStyle(LK.Palette.inkQuiet)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Text("Last updated 31 August 2026")
                        .font(LK.Typography.meta)
                        .foregroundStyle(LK.Palette.inkTertiary)
                        .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
            }
            .background(LK.Palette.ground)
            .navigationTitle("Terms of Use")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .tint(LK.Palette.action)
    }

    private struct Section {
        let heading: String
        let body: String
    }

    /// The zero-tolerance paragraph is the one Guideline 1.2 actually asks for.
    /// It is second, directly under what the app is, because a reviewer reads
    /// from the top and should not have to scroll to find it.
    private static let sections: [Section] = [
        Section(
            heading: "What this app is",
            body: """
            Chef Next Door helps you find home cooks near you who are cooking \
            right now, and message them. We are not a restaurant, a delivery \
            service, or a payment processor. We never take a payment and never \
            take a fee. Food is arranged directly between you and the cook, and \
            you pay them directly.
            """
        ),
        Section(
            heading: "Zero tolerance for objectionable content and abusive behaviour",
            body: """
            There is no tolerance for objectionable content or abusive users on \
            Chef Next Door.

            You agree not to post, send, or share anything that is unlawful, \
            harassing, threatening, abusive, hateful, defamatory, obscene, \
            sexually explicit, discriminatory, deceptive, or that impersonates \
            another person. This applies to kitchen names, dish names and \
            descriptions, photographs, profile names and photos, reviews, and \
            every message you send.

            Accounts that post objectionable content or behave abusively are \
            removed. We review every report we receive and act within 24 hours, \
            which may include deleting content, suspending an account, or \
            removing a person permanently. Serious matters are referred to law \
            enforcement or to the county health agency responsible for that \
            kitchen.
            """
        ),
        Section(
            heading: "Reporting content",
            body: """
            Every kitchen has a "Report this kitchen" action on its page, and \
            every conversation has a report action in the menu at the top right. \
            Reports reach us directly. A food-safety report is also routed to \
            the environmental health agency for that kitchen's city, and the \
            confirmation names the agency it went to.
            """
        ),
        Section(
            heading: "Blocking people",
            body: """
            You can block any kitchen from its page, and any person from a \
            conversation. Blocking is immediate and mutual in effect: a blocked \
            kitchen disappears from your feed, your map and your search results \
            straight away, and neither of you can message the other again. \
            Blocking also tells us, so we can look at the account. You can see \
            and undo your blocks under Messages, in the Blocked tab.
            """
        ),
        Section(
            heading: "Cooks and permits",
            body: """
            Cooks are responsible for holding the permits their county requires, \
            for the safety of the food they make, and for what they publish. \
            Where a cook gives us a permit number, we check it against their \
            county's public register, and only a genuine match earns a verified \
            badge. A badge is a statement about a public record, not a guarantee \
            about a meal.
            """
        ),
        Section(
            heading: "Your account",
            body: """
            You must be 17 or older to have an account. Keep your sign-in \
            details to yourself, and tell us if you think someone else is using \
            your account. You can delete your account at any time from the \
            Account tab, which removes your profile, your messages and your \
            saved kitchens.
            """
        ),
        Section(
            heading: "Liability",
            body: """
            Chef Next Door is provided as it is. We do not cook, handle, inspect \
            or deliver any food, and we are not a party to anything you agree \
            with a cook. To the fullest extent the law allows, we are not liable \
            for what is arranged between you and a cook, including illness, \
            allergic reaction, or a meal that never arrives.
            """
        ),
        Section(
            heading: "Contact",
            body: """
            Questions, reports and complaints: rolando.e.navarrete@gmail.com. \
            We answer reports within 24 hours.
            """
        ),
    ]
}

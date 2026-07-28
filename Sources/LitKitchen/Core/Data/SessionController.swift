import Foundation
import Observation
import Supabase

/// Who the current buyer is.
///
/// Browsing needs no account; claiming does, because a claim reveals a cook's
/// home address and that has to be attributable. So identity is established
/// lazily, at the moment of the first claim, rather than behind a sign-up wall
/// on launch.
///
/// **Anonymous, not anonymous-forever.** Supabase issues a real `authenticated`
/// user with `is_anonymous = true`, so RLS works exactly as it does for a
/// permanent account. When Sign in with Apple lands it *upgrades this same
/// user* rather than creating a second one — claims, follows and reviews all
/// carry over. Do not create a separate account at that point.
@Observable
@MainActor
public final class SessionController {
    private let client: SupabaseClient

    public private(set) var userID: UUID?
    public private(set) var isAnonymous = true
    /// Whether the signed-in user has a `cooks` row. This is what decides
    /// whether the cook-side surfaces exist at all — there is no "role" field,
    /// because being a cook *is* having a kitchen.
    public private(set) var cookID: UUID?
    public private(set) var signInError: String?
    /// How this account signs in — an email, or nil for Apple's private relay
    /// and for anonymous sessions. Surfaced only so a person can answer "which
    /// account am I in?", which until now the app gave no way to ask.
    public private(set) var email: String?

    public var isCook: Bool { cookID != nil }

    public init(client: SupabaseClient = SupabaseEnvironment.shared) {
        self.client = client
    }

    /// Restores an existing session, if there is one. Supabase persists the
    /// refresh token in the keychain, so an anonymous identity survives
    /// relaunch — losing it would orphan the buyer's claims.
    public func restore() async {
        if let session = try? await client.auth.session {
            userID = session.user.id
            isAnonymous = session.user.isAnonymous
            email = session.user.email
            await refreshCookStatus()
        }
    }

    /// Signs in an existing cook. Email/password rather than Sign in with
    /// Apple because SIWA needs a signing team — this is a real second auth
    /// method, not a stand-in, and cooks who sign up on the web will use it.
    public func signIn(email: String, password: String) async {
        do {
            let session = try await client.auth.signIn(email: email, password: password)
            userID = session.user.id
            isAnonymous = session.user.isAnonymous
            self.email = session.user.email
            signInError = nil
            await refreshCookStatus()
        } catch {
            signInError = "Couldn't sign in. Check the email and password."
        }
    }

    /// Creates a brand-new account for a cook signing up.
    ///
    /// Distinct from ``upgradeToAccount``: that one preserves an existing
    /// anonymous identity, this one makes a fresh user. Both hit the same
    /// email-confirmation wall, and both have to say so rather than reporting
    /// success — a cook who thinks they have an account and doesn't will get
    /// as far as the kitchen form before anything goes wrong.
    public func signUp(email: String, password: String) async -> UpgradeResult {
        do {
            let response = try await client.auth.signUp(email: email, password: password)
            if let session = response.session {
                userID = session.user.id
                isAnonymous = session.user.isAnonymous
                self.email = session.user.email
                signInError = nil
                await refreshCookStatus()
                return .upgraded
            }
            // No session means GoTrue accepted the signup and is waiting on a
            // confirmation link. The user exists; they just can't act yet.
            return .needsEmailConfirmation(email)
        } catch {
            let message = Self.upgradeFailureMessage(for: error)
            signInError = message
            return .failed(message)
        }
    }

    /// Signed in with a real account, but no kitchen yet — a registration that
    /// was started and not finished. Onboarding resumes here rather than
    /// starting over, which matters because the most likely reason to be in
    /// this state is an email confirmation that arrived after the app closed.
    public var needsCookOnboarding: Bool {
        userID != nil && !isAnonymous && cookID == nil
    }

    /// Re-reads cook status after registration completes.
    public func refreshAfterRegistration() async {
        await refreshCookStatus()
    }

    public func signOut() async {
        // Before the session goes: retiring the device token needs an
        // authenticated call, and the row routes *this account's* notifications
        // to *this handset*. Leaving it means the next person to sign in on this
        // phone keeps getting the previous one's orders.
        await PushRegistrar.shared.forgetToken()
        try? await client.auth.signOut()
        userID = nil
        cookID = nil
        email = nil
        isAnonymous = true
    }

    /// A user is a cook if they own a `cooks` row. RLS lets anyone read cooks,
    /// so this is a plain lookup rather than a privileged call.
    private func refreshCookStatus() async {
        guard let userID else { cookID = nil; return }
        struct Row: Decodable { let id: UUID }
        let rows: [Row]? = try? await client
            .from("cooks")
            .select("id")
            .eq("id", value: userID)
            .limit(1)
            .execute()
            .value
        cookID = rows?.first?.id
    }

    /// The identity used for a claim. Signs in anonymously on first use.
    @discardableResult
    public func requireIdentity() async throws -> UUID {
        if let userID { return userID }

        if let session = try? await client.auth.session {
            userID = session.user.id
            isAnonymous = session.user.isAnonymous
            email = session.user.email
            return session.user.id
        }

        let session = try await client.auth.signInAnonymously()
        userID = session.user.id
        isAnonymous = session.user.isAnonymous
        email = session.user.email
        return session.user.id
    }

    /// Converts the current **anonymous** user into a permanent account,
    /// keeping the same `user_id`.
    ///
    /// This is the difference between "sign up" and "sign in", and it matters
    /// more here than in most apps: an anonymous identity has no credentials,
    /// so once its session is gone there is no way back into it. Every claim,
    /// follow and review made anonymously would be orphaned — not deleted,
    /// just permanently unreachable.
    ///
    /// `updateUser` on a live anonymous session upgrades in place. Signing
    /// into a *pre-existing* account cannot merge — those are genuinely two
    /// different users — which is why ``willLoseAnonymousData`` warns first.
    ///
    /// **The upgrade is not necessarily done when this call succeeds.** With
    /// email confirmations enabled — the Supabase default — GoTrue accepts the
    /// address, mails a confirmation link, and leaves `is_anonymous` **true**
    /// until that link is clicked. An earlier version of this returned `true`
    /// on any 200 and dismissed the sheet, so the buyer was told their claims
    /// were saved while the account did not yet exist. Trust `is_anonymous`
    /// from the response, never the absence of an error.
    public enum UpgradeResult: Equatable {
        /// `is_anonymous` came back false — the account exists now.
        case upgraded
        /// Accepted, but pending an emailed confirmation link. Still anonymous.
        case needsEmailConfirmation(String)
        case failed(String)
    }

    public func upgradeToAccount(email: String, password: String) async -> UpgradeResult {
        guard isAnonymous else { return .failed("You're already signed in.") }
        do {
            let user = try await client.auth.update(
                user: UserAttributes(email: email, password: password)
            )
            userID = user.id
            isAnonymous = user.isAnonymous
            signInError = nil
            await refreshCookStatus()
            return user.isAnonymous ? .needsEmailConfirmation(email) : .upgraded
        } catch {
            let message = Self.upgradeFailureMessage(for: error)
            signInError = message
            return .failed(message)
        }
    }

    /// GoTrue's error codes are specific and worth passing through. The old
    /// catch-all ("that email may already be in use") sent me looking for a
    /// duplicate account when the actual cause was an address the server
    /// rejects outright.
    private static func upgradeFailureMessage(for error: Error) -> String {
        guard let authError = error as? AuthError else {
            return "Couldn't save your account. Check your connection and try again."
        }
        switch authError.errorCode.rawValue {
        case "email_address_invalid":
            // Reserved TLDs (.test, .invalid, .example, .localhost — RFC 2606)
            // are refused. Worth naming, because a seed-data address like
            // `someone@seed.test` fails here while the identical address works
            // for the seeded cooks, who were written straight into auth.users
            // and so never met this validator.
            return "That email address isn't accepted. Try a different one."
        case "email_exists", "user_already_exists":
            return "There's already an account with that email. Sign in instead."
        case "weak_password":
            return "Pick a longer password — at least 6 characters."
        case "over_email_send_rate_limit":
            return "Too many attempts just now. Try again in a few minutes."
        default:
            return authError.message
        }
    }

    /// True when signing out (or into another account) would strand data that
    /// can never be recovered, because the current identity is anonymous.
    public var willLoseAnonymousData: Bool { isAnonymous && userID != nil }

    // MARK: - Sign in with Apple

    /// Surfaces a failure that happened *before* Supabase was reached — Apple's
    /// own authorization sheet failing, say. `signInError` stays `private(set)`
    /// so no view can invent an error state; this is the one narrow door.
    public func reportAppleFailure(_ message: String?) {
        signInError = message
    }

    /// Signs in or upgrades with Apple, whichever the current state calls for.
    ///
    /// **The branch is the entire point.** `signInWithIdToken` finds or creates
    /// an Apple-backed user — run it on an anonymous session and the anonymous
    /// user is simply abandoned, taking every claim, follow and review with it.
    /// `linkIdentityWithIdToken` attaches Apple to the *current* user instead,
    /// keeping the same `user_id`.
    ///
    /// This is the same distinction as ``upgradeToAccount`` versus ``signIn``,
    /// and it's easier to get wrong here because both Apple paths look
    /// identical from the button's side.
    ///
    /// Apple also sidesteps the email-confirmation wall that blocks the
    /// password upgrade: Apple has already verified the address, so the session
    /// comes back usable rather than pending.
    public func continueWithApple(_ credential: AppleCredential) async -> UpgradeResult {
        do {
            let credentials = OpenIDConnectCredentials(
                provider: .apple, idToken: credential.idToken, nonce: credential.nonce
            )

            let session: Session
            if isAnonymous, userID != nil {
                session = try await client.auth.linkIdentityWithIdToken(credentials: credentials)
            } else {
                session = try await client.auth.signInWithIdToken(credentials: credentials)
            }

            userID = session.user.id
            isAnonymous = session.user.isAnonymous
            email = session.user.email
            signInError = nil
            await adoptAppleName(credential.fullName)
            await refreshCookStatus()
            return .upgraded
        } catch {
            // A cancelled authorization is a decision, not a failure — leaving
            // an error banner behind would be arguing with it.
            if case AppleSignInError.cancelled = error {
                signInError = nil
                return .failed("")
            }
            let message = Self.appleFailureMessage(for: error)
            signInError = message
            return .failed(message)
        }
    }

    /// Seeds the profile from the name Apple supplies.
    ///
    /// **Apple sends `fullName` exactly once** — on the very first
    /// authorization for this Apple ID and app. Every later sign-in returns
    /// nil, and there is no API to ask again; the only recovery is for the user
    /// to revoke the app in Settings. Until now we parsed it in
    /// ``AppleSignIn`` and dropped it, so it was being thrown away at the one
    /// moment it existed.
    ///
    /// Best-effort on purpose. A profile is not required to sign in — only to
    /// send a message — so a failure here must not turn a successful
    /// authorization into a failed one. The name sheet is the backstop.
    private func adoptAppleName(_ name: String?) async {
        guard let name = name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else { return }
        // `seed_…`, not `upsert_…`: this is a guess, and it must lose to a name
        // the person typed themselves. The server does `on conflict do nothing`.
        try? await client
            .rpc("seed_my_profile_name", params: ["p_name": String(name.prefix(50))])
            .execute()
    }

    private static func appleFailureMessage(for error: Error) -> String {
        guard let authError = error as? AuthError else {
            return (error as? LocalizedError)?.errorDescription
                ?? "Couldn't finish signing in with Apple."
        }
        switch authError.errorCode.rawValue {
        case "identity_already_exists":
            // Genuinely unfixable in place: that Apple ID is already a separate
            // user, and merging two users is not something Supabase — or we —
            // can do safely. Say so plainly instead of retrying.
            return "That Apple ID already has an account here. Sign in with it instead — orders made on this phone won't carry over."
        case "provider_disabled":
            return "Apple sign-in isn't enabled for this app yet."
        default:
            return authError.message
        }
    }

    public enum SessionError: Error, CustomStringConvertible {
        case notImplemented
        public var description: String {
            "Sign in with Apple upgrade is not wired yet — it needs a signing team."
        }
    }
}

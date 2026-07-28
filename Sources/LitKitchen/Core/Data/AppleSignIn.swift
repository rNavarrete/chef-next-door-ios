import AuthenticationServices
import os
import CryptoKit
import Foundation

/// The credential Apple hands back, reduced to what Supabase needs.
public struct AppleCredential: Sendable {
    public let idToken: String
    /// The raw nonce we generated. Apple embeds its **hash** in the token, and
    /// GoTrue re-hashes this to compare — so the raw value must survive from
    /// request to verification or the token is rejected.
    public let nonce: String
    /// Apple returns the name **only on the very first authorization** for a
    /// given Apple ID and app. There is no second chance and no API to fetch it
    /// later; if it isn't captured here it is gone for good.
    public let fullName: String?
    public let email: String?
}

public enum AppleSignInError: LocalizedError {
    case cancelled
    case noIdentityToken
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .cancelled: nil            // the user meant it; say nothing
        case .noIdentityToken: "Apple didn't return a usable sign-in token."
        case .failed(let message): message
        }
    }
}

/// Wraps `ASAuthorizationController` in something awaitable.
///
/// Deliberately not a view: the same credential is needed from two different
/// screens (a buyer upgrading, a cook signing up), and threading a delegate
/// through both was the alternative.
@MainActor
public final class AppleSignInCoordinator: NSObject {
    private var continuation: CheckedContinuation<AppleCredential, Error>?
    private var currentNonce: String?

    /// Whether the system actually asked us where to put the sheet.
    ///
    /// `presentationAnchor(for:)` is called only when the flow is about to be
    /// presented, which makes it the one reliable signal that a sheet existed
    /// for someone to cancel. iOS reports a flow that *cannot start* — no
    /// entitlement, Sign in with Apple restricted by Screen Time, no Apple ID
    /// on the device — with the same `.canceled` code a real dismissal uses.
    /// Without this flag the two are indistinguishable, and the app stays
    /// silent on both.
    private var didPresent = false

    /// The in-flight controller, **retained**.
    ///
    /// `ASAuthorizationController` does not keep itself alive for the duration
    /// of a request, and it holds `delegate` and `presentationContextProvider`
    /// weakly. Created as a local it deallocated the instant
    /// `performRequests()` returned, and the request died with it — no sheet,
    /// no `didCompleteWithError`, no callback of any kind. On device that
    /// presented as "Sign in with Apple didn't start" for an account that was
    /// signed in and working.
    private var controller: ASAuthorizationController?

    /// This flow has been diagnosed wrong twice from symptoms alone — once as a
    /// cancellation mapping, once as a missing entitlement — when it was first
    /// an untappable button and then an unretained controller. It is entirely
    /// system-driven and invisible from the outside, so it says what it is doing.
    ///
    ///     xcrun devicectl device process view --device <id> \
    ///       --console --predicate 'subsystem == "com.litkitchen.app"'
    private let log = Logger(subsystem: "com.litkitchen.app", category: "applesignin")

    public override init() { super.init() }

    public func requestCredential() async throws -> AppleCredential {
        let nonce = Self.randomNonce()
        currentNonce = nonce

        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        // Apple hashes this into the token; GoTrue compares against the raw
        // value we send alongside. Replay protection, and non-optional in
        // practice — Supabase rejects a token whose nonce it can't verify.
        request.nonce = Self.sha256(nonce)

        didPresent = false
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            // Held until the request finishes. See `controller`.
            self.controller = controller
            log.info("apple: performRequests")
            controller.performRequests()
            startPresentationWatchdog()
        }
    }

    /// Last-resort release for a request that never calls back at all.
    ///
    /// **This nearly broke sign-in, and the history matters.** It was written
    /// when tapping the button produced no AuthenticationServices activity
    /// whatsoever, on the theory that `performRequests()` can return silently.
    /// The real cause was elsewhere: the `ASAuthorizationController` was a local
    /// and deallocated immediately, so nothing was alive to call back. With the
    /// controller retained, the delegate always fires.
    ///
    /// At five seconds this then became the bug. AuthKit routinely takes longer
    /// than that to present on a real device — first authorization, cold
    /// daemon, network — and the watchdog was resuming the continuation and
    /// clearing it *before* the sheet appeared. The user then signed in
    /// successfully, `didCompleteWithAuthorization` found no continuation, and
    /// the credential was dropped on the floor. Sign-in "did nothing", with a
    /// stale failure message sitting underneath a working sheet.
    ///
    /// Twenty-five seconds. Long enough that a sheet which is merely slow is
    /// never cut off, short enough that a genuinely dead request eventually
    /// releases the button instead of spinning for the life of the view. It
    /// still only fires when the system never asked for a presentation anchor,
    /// which is the one signal that means it never intended to present.
    private func startPresentationWatchdog() {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(25))
            guard let self, !self.didPresent, let pending = self.continuation else { return }
            self.log.error("apple: watchdog fired — no presentation after 25s")
            // Cleared first: whichever of this and the delegate arrives second
            // must not resume the continuation twice, which traps.
            self.continuation = nil
            self.controller = nil
            pending.resume(throwing: AppleSignInError.failed(
                "Sign in with Apple didn't start. Check that you're signed in to an Apple ID in Settings, then try again."
            ))
        }
    }

    // MARK: - Nonce

    private static func randomNonce(length: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        guard status == errSecSuccess else {
            // SecRandom failing means the platform CSPRNG is unavailable, which
            // is not a condition to paper over with a weaker fallback.
            preconditionFailure("SecRandomCopyBytes failed: \(status)")
        }
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(bytes.map { charset[Int($0) % charset.count] })
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

extension AppleSignInCoordinator: ASAuthorizationControllerDelegate {
    public func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        defer { continuation = nil; self.controller = nil }
        log.info("apple: didCompleteWithAuthorization, continuation=\(self.continuation != nil, privacy: .public)")
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let idToken = String(data: tokenData, encoding: .utf8),
              let nonce = currentNonce
        else {
            continuation?.resume(throwing: AppleSignInError.noIdentityToken)
            return
        }

        let name = [credential.fullName?.givenName, credential.fullName?.familyName]
            .compactMap { $0 }
            .joined(separator: " ")

        continuation?.resume(returning: AppleCredential(
            idToken: idToken,
            nonce: nonce,
            fullName: name.isEmpty ? nil : name,
            email: credential.email
        ))
    }

    public func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        defer { continuation = nil; self.controller = nil }
        let code = (error as? ASAuthorizationError)?.code
        log.error("apple: didCompleteWithError code=\(code?.rawValue ?? -1, privacy: .public) didPresent=\(self.didPresent, privacy: .public) \(error.localizedDescription, privacy: .public)")

        // A cancellation only counts as one if there was something to cancel.
        // Otherwise this is the flow failing to start, and staying quiet about
        // it leaves a buyer tapping a dead button — with no other way to make
        // an account, since Apple is their only option.
        guard code == .canceled, didPresent else {
            continuation?.resume(throwing: AppleSignInError.failed(
                didPresent
                    ? error.localizedDescription
                    : "Sign in with Apple isn't available on this device right now. Check that you're signed in to an Apple ID in Settings."
            ))
            return
        }
        continuation?.resume(throwing: AppleSignInError.cancelled)
    }
}

extension AppleSignInCoordinator: ASAuthorizationControllerPresentationContextProviding {
    public func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        didPresent = true
        log.info("apple: presentationAnchor — the sheet is coming up")
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        return scene?.keyWindow ?? ASPresentationAnchor()
    }
}

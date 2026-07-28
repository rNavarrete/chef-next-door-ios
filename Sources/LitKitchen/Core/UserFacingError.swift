import Foundation

/// Turns a thrown error into something worth showing a person.
///
/// Every view model here started out doing `errorMessage = String(describing:
/// error)`, which is fine in a log and indefensible on screen — a buyer
/// checking their claim was shown a full `NSURLError` dump: domain, code,
/// failing URL, session-task identifiers, the lot. It was found on a physical
/// device, in front of a real claim, which is roughly the worst place to find
/// it.
///
/// Two rules encoded here:
///
/// 1. **A cancelled request is not an error.** SwiftUI tears down a `.task`
///    whenever its view goes away, so an ordinary tab switch throws
///    `NSURLErrorCancelled` mid-flight. Reporting that as a failure means the
///    app accuses itself of breaking every time someone navigates.
/// 2. **The raw error goes to the log, never the screen.** The person holding
///    the phone gets a sentence they can act on; the detail stays where it can
///    actually be read.
public enum UserFacingError {

    /// A message for display, or `""` when there is genuinely nothing to say.
    /// Callers should treat empty as "show no error row at all".
    public static func message(for error: Error, fallback: String) -> String {
        if error is CancellationError { return "" }

        let ns = error as NSError
        guard ns.domain == NSURLErrorDomain else { return fallback }

        switch ns.code {
        case NSURLErrorCancelled:
            return ""
        case NSURLErrorNotConnectedToInternet,
             NSURLErrorNetworkConnectionLost,
             NSURLErrorTimedOut,
             NSURLErrorCannotConnectToHost,
             NSURLErrorCannotFindHost,
             NSURLErrorDataNotAllowed:
            return "You're offline. Check your connection and pull to refresh."
        default:
            return fallback
        }
    }
}

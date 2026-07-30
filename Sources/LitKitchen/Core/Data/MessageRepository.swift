import Foundation
import Supabase

/// One thread, as it appears in the inbox.
///
/// Both sides read from the same RPC — `iAmTheCook` is what decides whose name
/// `otherName` holds. One screen serves the cook and the buyer because it is
/// genuinely one list; splitting it would mean two views rendering the same
/// rows with the labels swapped.
public struct Conversation: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public let cookID: UUID
    public let buyerID: UUID
    public let otherName: String
    /// A `cooks.avatar_url` (public bucket) when the other party is a cook, or
    /// a `profiles.avatar_path` (private bucket, needs signing) when it's a
    /// buyer. `iAmTheCook` disambiguates.
    public let otherAvatar: String?
    public let lastBody: String?
    public let lastKind: MessageKind?
    public let lastPayload: OrderPayload?
    public let lastAt: Date
    public let unread: Int
    public let iAmTheCook: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case cookID = "cook_id"
        case buyerID = "buyer_id"
        case otherName = "other_name"
        case otherAvatar = "other_avatar"
        case lastBody = "last_body"
        case lastKind = "last_kind"
        case lastPayload = "last_payload"
        case lastAt = "last_at"
        case unread
        case iAmTheCook = "i_am_the_cook"
    }

    /// The one-line preview. Rebuilt from the payload for orders so the inbox
    /// agrees with the card; `lastBody` is a server-side string and cannot be
    /// per-reader.
    public func preview(
        preferring language: String = Locale.current.language.languageCode?.identifier ?? "en"
    ) -> String {
        guard lastKind == .order, let lines = lastPayload?.lines, !lines.isEmpty else {
            return lastBody ?? "No messages yet"
        }
        let items = lines
            .map { "\($0.quantity)× \($0.displayName(preferring: language))" }
            .joined(separator: ", ")
        let total = Double(lastPayload?.totalCents ?? 0) / 100
        return String(format: "%@ · $%.2f", items, total)
    }
}

/// A thread is a timeline of typed events, not just text — an order, an address
/// being shared and a pickup all happen *in* the conversation now, because that
/// is where the two people actually are.
public enum MessageKind: String, Codable, Sendable {
    case text, order, address, pickup
}

public struct OrderLine: Codable, Sendable, Hashable {
    /// The canonical record of what was ordered — cook's naming first.
    public let name: String
    /// Both forms, so each side renders the one it would render anywhere else.
    /// A buyer picked "Pork tamale" and then watched it confirm as "Tamal de
    /// puerco en rojo"; the same dish under two names, with nothing on screen
    /// to say so. Nil on rows written before 044.
    public let nameEN: String?
    public let nameES: String?
    public let quantity: Int
    public let unitCents: Int

    enum CodingKeys: String, CodingKey {
        case name, quantity
        case nameEN = "name_en"
        case nameES = "name_es"
        case unitCents = "unit_cents"
    }

    /// Mirrors ``MenuItem/displayName(preferring:)`` exactly. If the two ever
    /// disagree, a dish is named one thing in the picker and another in the
    /// order — which is the bug this exists to fix.
    public func displayName(
        preferring language: String = Locale.current.language.languageCode?.identifier ?? "en"
    ) -> String {
        let preferred = language.hasPrefix("es") ? nameES : nameEN
        return preferred ?? nameES ?? nameEN ?? name
    }
}

public struct OrderPayload: Codable, Sendable, Hashable {
    public let lines: [OrderLine]
    public let totalCents: Int
    public let note: String?

    enum CodingKeys: String, CodingKey {
        case lines
        case totalCents = "total_cents"
        case note
    }
}

public struct Message: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public let conversationID: UUID
    public let senderID: UUID
    public let body: String
    public let createdAt: Date
    public let readAt: Date?
    public let kind: MessageKind
    /// Present only on `.order`. Deliberately decoded lazily rather than as a
    /// typed column: the server owns this shape.
    public let payload: OrderPayload?

    enum CodingKeys: String, CodingKey {
        case id
        case conversationID = "conversation_id"
        case senderID = "sender_id"
        case body
        case createdAt = "created_at"
        case readAt = "read_at"
        case kind, payload
    }

    public init(
        id: UUID, conversationID: UUID, senderID: UUID, body: String,
        createdAt: Date, readAt: Date?, kind: MessageKind = .text,
        payload: OrderPayload? = nil
    ) {
        self.id = id
        self.conversationID = conversationID
        self.senderID = senderID
        self.body = body
        self.createdAt = createdAt
        self.readAt = readAt
        self.kind = kind
        self.payload = payload
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        conversationID = try c.decode(UUID.self, forKey: .conversationID)
        senderID = try c.decode(UUID.self, forKey: .senderID)
        body = try c.decode(String.self, forKey: .body)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        readAt = try c.decodeIfPresent(Date.self, forKey: .readAt)
        // Defaults so a row written before 043 still decodes.
        kind = (try? c.decode(MessageKind.self, forKey: .kind)) ?? .text
        payload = try? c.decodeIfPresent(OrderPayload.self, forKey: .payload)
    }
}

/// Where a thread has got to, for the header and the action bar.
public struct ThreadState: Codable, Sendable, Hashable {
    public let addressShared: Bool
    public let pickedUp: Bool
    public let reviewed: Bool
    public let iAmTheCook: Bool
    /// Drives the lamp on the Lock Screen card. Server-side rather than assumed
    /// `true`: pushes only fire on address-shared and pickup, so a card started
    /// at order time would otherwise assert a lit kitchen for hours after the
    /// cook closed.
    public let cookIsCooking: Bool
    public let cookName: String
    public let orderedAt: Date?

    enum CodingKeys: String, CodingKey {
        case addressShared = "address_shared"
        case pickedUp = "picked_up"
        case reviewed
        case iAmTheCook = "i_am_the_cook"
        case cookIsCooking = "cook_is_cooking"
        case cookName = "cook_name"
        case orderedAt = "ordered_at"
    }
}

/// Thrown when the send was refused for a reason the person can fix.
///
/// Deliberately *not* folded into a generic error string. The server raises
/// distinct SQLSTATEs (`P0002` no account, `P0003` no name) precisely so this
/// can open the right sheet, and rendering "add your name to send a message"
/// as a red error row would be telling someone they broke something when they
/// have simply not finished signing up.
public enum MessageSendError: Error, Equatable {
    case gate(MessagingGate)
    case rateLimited
    /// The cook hasn't shared their address in this thread yet, or the caller
    /// has hit the daily reveal cap.
    ///
    /// Lived on `SupabaseClaimRepository.ClaimError` until claiming was retired
    /// in migration 043. Messaging kept throwing it, which is the only reason
    /// the entire claims subsystem — a model file and a 195-line repository,
    /// none of it reachable from any screen — stayed compiled into the app.
    case addressNotAvailable
}

extension MessageSendError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .gate:        "You need an account to send that."
        case .rateLimited: "That's a lot of messages at once — try again shortly."
        case .addressNotAvailable:
            "The address isn't available yet. The cook has to say yes first — and there's a daily limit on how many addresses one person can unlock."
        }
    }
}

public protocol MessageRepository: AnyObject, Sendable {
    func conversations() async throws -> [Conversation]
    func messages(in threadID: UUID) async throws -> [Message]
    /// Opens or continues the thread with this cook. Returns the message id.
    @discardableResult
    func send(to cookID: UUID, body: String, claimID: UUID?) async throws -> UUID
    @discardableResult
    func reply(in threadID: UUID, body: String) async throws -> UUID
    func markRead(_ threadID: UUID) async throws
    /// Unread messages across every conversation, for the app icon badge.
    ///
    /// Separate from the per-thread counts the inbox already carries, because
    /// the badge has to be right after reading a thread reached straight from a
    /// notification — a path that never loads the inbox at all.
    func unreadTotal() async throws -> Int
    /// Whether the current session may send at all, without sending anything.
    /// Lets a screen show the sign-in prompt *before* someone types a message
    /// and loses it to a refusal.
    func gate() async throws -> MessagingGate?

    /// Cook side. Blocks the buyer in this thread — silently, from their point
    /// of view. See `migrations/042`.
    func blockBuyer(in threadID: UUID) async throws
    func unblockBuyer(_ buyerID: UUID) async throws
    func blockedBuyers() async throws -> [BlockedBuyer]
    func reportBuyer(in threadID: UUID, kind: BuyerReportKind, note: String?, alsoBlock: Bool) async throws

    /// Removes a conversation from *this* user's list.
    ///
    /// Not a delete: the other party keeps their copy, and it returns for both
    /// if either speaks again (064). Erasing a cook's record of an order from
    /// the buyer's side would destroy someone else's data, which is a different
    /// feature and not one this app should have.
    func hideConversation(_ threadID: UUID) async throws

    // MARK: - Ordering in the thread (043)

    /// Buyer side. Posts a priced order into the thread, opening it if needed.
    /// Prices are resolved server-side from the menu — never sent by the client.
    @discardableResult
    func postOrder(to cookID: UUID, items: [(MenuItem, Int)], note: String?) async throws -> UUID
    /// Cook side. Discloses the exact address to this buyer, audited.
    func shareAddress(in threadID: UUID) async throws
    /// Buyer side. Only succeeds once the cook has shared.
    func address(in threadID: UUID) async throws -> RevealedAddress
    /// Cook side. What unlocks the review.
    func markPickedUp(in threadID: UUID) async throws
    func state(of threadID: UUID) async throws -> ThreadState?
    /// Stores the per-activity push token so the server can update the Lock
    /// Screen card. Tokens are reissued mid-activity, so this is a stream, not
    /// a one-time handshake.
    func registerActivityToken(threadID: UUID, token: String, activityID: String) async throws
    /// Cook side. Orders with no pickup recorded — what the close-out prompt asks about.
    func openOrders() async throws -> [OpenOrder]

    /// Fires whenever a message lands in this thread, including your own.
    ///
    /// Yields `Void` rather than the row: the caller reloads, which also picks
    /// up the state change an 'address' or 'pickup' message implies. Trusting
    /// the payload would mean the transcript and the action bar could disagree.
    func liveMessages(in threadID: UUID) -> AsyncStream<Void>
    /// Fires on any message in any thread you are part of. Drives the inbox,
    /// which otherwise only refreshed when you navigated back to it.
    func liveConversations() -> AsyncStream<Void>

    /// The device's APNs token, for ordinary alerts. Distinct from the
    /// per-activity Live Activity token above.
    func registerDeviceToken(_ token: String) async throws
    func forgetDeviceToken(_ token: String) async throws
}

public struct BlockedBuyer: Codable, Sendable, Identifiable, Hashable {
    public var id: UUID { buyerID }
    public let buyerID: UUID
    public let displayName: String
    public let avatarPath: String?
    public let blockedAt: Date

    enum CodingKeys: String, CodingKey {
        case buyerID = "buyer_id"
        case displayName = "display_name"
        case avatarPath = "avatar_path"
        case blockedAt = "blocked_at"
    }
}

public enum BuyerReportKind: String, CaseIterable, Sendable {
    case harassment, noShow = "no_show", spam, other

    public var label: String {
        switch self {
        case .harassment: "Messages that made me uncomfortable"
        // "Claimed" is a word this product retired in migration 043 — buyers
        // order in the thread now, and there is no claim to make. The enum case
        // and its `no_show` wire value stay: the database column is a
        // `report_kind` and renaming it would rewrite history for no gain.
        // Only the sentence a cook reads had to change.
        case .noShow:     "Ordered and never showed up"
        case .spam:       "Spam or advertising"
        case .other:      "Something else"
        }
    }
}

public final class SupabaseMessageRepository: MessageRepository {
    private let client: SupabaseClient

    public init(client: SupabaseClient = SupabaseEnvironment.shared) {
        self.client = client
    }

    public func conversations() async throws -> [Conversation] {
        try await client.rpc("my_conversations").execute().value
    }

    public func messages(in threadID: UUID) async throws -> [Message] {
        try await client
            .from("messages")
            .select()
            .eq("conversation_id", value: threadID)
            .order("created_at", ascending: true)
            .execute()
            .value
    }

    @discardableResult
    public func send(to cookID: UUID, body: String, claimID: UUID?) async throws -> UUID {
        struct Params: Encodable {
            let p_cook: UUID
            let p_body: String
            let p_claim: UUID?
        }
        do {
            return try await client
                .rpc("send_message", params: Params(p_cook: cookID, p_body: body, p_claim: claimID))
                .execute()
                .value
        } catch {
            throw Self.translate(error)
        }
    }

    @discardableResult
    public func reply(in threadID: UUID, body: String) async throws -> UUID {
        struct Params: Encodable {
            let p_thread: UUID
            let p_body: String
        }
        do {
            return try await client
                .rpc("reply_in_conversation", params: Params(p_thread: threadID, p_body: body))
                .execute()
                .value
        } catch {
            throw Self.translate(error)
        }
    }

    public func markRead(_ threadID: UUID) async throws {
        struct Params: Encodable { let p_thread: UUID }
        try await client
            .rpc("mark_conversation_read", params: Params(p_thread: threadID))
            .execute()
    }

    /// A `head` request: PostgREST returns the count in a header and no rows,
    /// so this costs a round trip and nothing else.
    ///
    /// No filter naming my own conversations, because RLS already does it —
    /// `messages_parties_read` limits this table to threads I am party to
    /// (`migrations/049`). The only condition worth stating is the one RLS
    /// cannot know: that a message I sent myself is not unread mail.
    public func unreadTotal() async throws -> Int {
        guard let me = client.auth.currentUser?.id else { return 0 }
        let response = try await client
            .from("messages")
            .select("id", head: true, count: .exact)
            .is("read_at", value: nil)
            .neq("sender_id", value: me)
            .execute()
        return response.count ?? 0
    }

    public func gate() async throws -> MessagingGate? {
        // No session at all is `needsAccount`, not "no gate". `sender_can_message`
        // is revoked from `anon`, so with no JWT PostgREST refuses the call
        // before the function runs — and a caller doing `try? await gate()`
        // reads that failure as "nothing to prompt for", which is how a
        // signed-out buyer got a composer that types fine and then fails with a
        // generic error instead of an offer to sign in.
        guard client.auth.currentUser != nil else { return .needsAccount }

        let state: String = try await client.rpc("sender_can_message").execute().value
        switch state {
        case "anonymous":  return .needsAccount
        case "no_profile": return .needsProfile
        default:           return nil
        }
    }

    public func hideConversation(_ threadID: UUID) async throws {
        struct Params: Encodable { let p_conversation: UUID }
        try await client
            .rpc("hide_conversation", params: Params(p_conversation: threadID))
            .execute()
    }

    public func blockBuyer(in threadID: UUID) async throws {
        struct Params: Encodable { let p_thread: UUID }
        try await client.rpc("block_buyer_in", params: Params(p_thread: threadID)).execute()
    }

    public func unblockBuyer(_ buyerID: UUID) async throws {
        struct Params: Encodable { let p_buyer: UUID }
        try await client.rpc("unblock_buyer", params: Params(p_buyer: buyerID)).execute()
    }

    public func blockedBuyers() async throws -> [BlockedBuyer] {
        try await client.rpc("my_blocked_buyers").execute().value
    }

    public func reportBuyer(
        in threadID: UUID, kind: BuyerReportKind, note: String?, alsoBlock: Bool
    ) async throws {
        struct Params: Encodable {
            let p_thread: UUID
            let p_kind: String
            let p_body: String?
            let p_block: Bool
        }
        try await client
            .rpc("report_buyer", params: Params(
                p_thread: threadID, p_kind: kind.rawValue,
                p_body: note, p_block: alsoBlock
            ))
            .execute()
    }

    @discardableResult
    public func postOrder(to cookID: UUID, items: [(MenuItem, Int)], note: String?) async throws -> UUID {
        struct Line: Encodable { let menu_item_id: UUID; let quantity: Int }
        struct Params: Encodable {
            let p_cook: UUID
            let p_items: [Line]
            let p_note: String?
        }
        do {
            return try await client
                .rpc("post_order", params: Params(
                    p_cook: cookID,
                    p_items: items.map { Line(menu_item_id: $0.0.id, quantity: $0.1) },
                    p_note: note
                ))
                .execute()
                .value
        } catch {
            throw Self.translate(error)
        }
    }

    public func shareAddress(in threadID: UUID) async throws {
        struct Params: Encodable { let p_thread: UUID }
        try await client.rpc("share_address", params: Params(p_thread: threadID)).execute()
    }

    public func address(in threadID: UUID) async throws -> RevealedAddress {
        struct Params: Encodable { let p_thread: UUID }
        let rows: [RevealedAddress] = try await client
            .rpc("thread_address", params: Params(p_thread: threadID))
            .execute()
            .value
        guard let address = rows.first else { throw MessageSendError.addressNotAvailable }
        return address
    }

    public func markPickedUp(in threadID: UUID) async throws {
        struct Params: Encodable { let p_thread: UUID }
        try await client.rpc("mark_picked_up", params: Params(p_thread: threadID)).execute()
    }

    public func state(of threadID: UUID) async throws -> ThreadState? {
        struct Params: Encodable { let p_thread: UUID }
        let rows: [ThreadState] = try await client
            .rpc("thread_state", params: Params(p_thread: threadID))
            .execute()
            .value
        return rows.first
    }

    public func openOrders() async throws -> [OpenOrder] {
        try await client.rpc("open_orders").execute().value
    }

    public func liveConversations() -> AsyncStream<Void> {
        // No filter: the inbox cares about every thread, and RLS already scopes
        // the subscription to the ones this person is in. A filter here would
        // have to name a conversation, which is exactly what we don't know yet.
        let channel = client.channel("inbox:\(UUID().uuidString)")
        let inserts = channel.postgresChange(InsertAction.self, table: "messages")

        return AsyncStream { continuation in
            let task = Task {
                await channel.subscribe()
                for await _ in inserts { continuation.yield(()) }
                continuation.finish()
            }
            continuation.onTermination = { [client] _ in
                task.cancel()
                Task { await client.removeChannel(channel) }
            }
        }
    }

    public func liveMessages(in threadID: UUID) -> AsyncStream<Void> {
        let channel = client.channel("thread:\(threadID.uuidString)")
        // The filter narrows what crosses the wire; RLS is what makes it safe.
        // A client can put any conversation id in a filter — `messages_parties_read`
        // is the reason doing so returns nothing (`migrations/049`).
        let inserts = channel.postgresChange(
            InsertAction.self,
            table: "messages",
            filter: "conversation_id=eq.\(threadID.uuidString)"
        )

        return AsyncStream { continuation in
            let task = Task {
                await channel.subscribe()
                for await _ in inserts { continuation.yield(()) }
                continuation.finish()
            }
            // Leaving a thread must close its socket. Without this every thread
            // opened in a session stays subscribed for the life of the app.
            continuation.onTermination = { [client] _ in
                task.cancel()
                Task { await client.removeChannel(channel) }
            }
        }
    }

    public func registerDeviceToken(_ token: String) async throws {
        struct Params: Encodable { let p_token: String; let p_environment: String }
        #if DEBUG
        let environment = "development"
        #else
        let environment = "production"
        #endif
        try await client
            .rpc("register_device_token", params: Params(p_token: token, p_environment: environment))
            .execute()
    }

    public func forgetDeviceToken(_ token: String) async throws {
        struct Params: Encodable { let p_token: String }
        try await client.rpc("forget_device_token", params: Params(p_token: token)).execute()
    }

    public func registerActivityToken(threadID: UUID, token: String, activityID: String) async throws {
        struct Params: Encodable {
            let p_thread: UUID
            let p_token: String
            let p_activity_id: String
            let p_environment: String
        }
        // A development-signed build gets sandbox tokens; sending those to
        // production APNs fails with BadDeviceToken, which is a confusing way
        // to discover a build-config mismatch. So the build says which it is.
        #if DEBUG
        let environment = "development"
        #else
        let environment = "production"
        #endif
        try await client
            .rpc("register_thread_activity_token", params: Params(
                p_thread: threadID, p_token: token,
                p_activity_id: activityID, p_environment: environment
            ))
            .execute()
    }

    /// SQLSTATE → intent. The codes are assigned in `migrations/041`; keep the
    /// two in step, and note that PostgREST reports a *missing* function as a
    /// 404 rather than an error code, which is not the same thing as a refusal.
    private static func translate(_ error: Error) -> Error {
        guard let pg = error as? PostgrestError else { return error }
        switch pg.code {
        case "P0002": return MessageSendError.gate(.needsAccount)
        case "P0003": return MessageSendError.gate(.needsProfile)
        case "P0001": return MessageSendError.rateLimited
        // Permission denied means the caller has no usable session, since the
        // function is granted to `authenticated` and nobody else. Same prompt as
        // P0002 — showing "permission denied" to someone who simply has not
        // signed in describes the mechanism instead of the fix.
        case "42501": return MessageSendError.gate(.needsAccount)
        default:      return error
        }
    }
}

/// Development double. Mirrors the server's *rules*, not just its shape — the
/// gate especially, or the UI gets built against a send that always succeeds.
public final class InMemoryMessageRepository: MessageRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var threads: [Conversation] = []
    private var byThread: [UUID: [Message]] = [:]
    private var gateState: MessagingGate?
    private let me: UUID

    public init(me: UUID = UUID(), gate: MessagingGate? = nil, seeded: [Conversation] = []) {
        self.me = me
        self.gateState = gate
        self.threads = seeded
    }

    public func setGate(_ gate: MessagingGate?) {
        lock.withLock { gateState = gate }
    }

    public func conversations() async throws -> [Conversation] {
        lock.withLock { threads.sorted { $0.lastAt > $1.lastAt } }
    }

    public func messages(in threadID: UUID) async throws -> [Message] {
        lock.withLock { byThread[threadID] ?? [] }
    }

    @discardableResult
    public func send(to cookID: UUID, body: String, claimID: UUID?) async throws -> UUID {
        if let gateState { throw MessageSendError.gate(gateState) }
        return try lock.withLock {
            let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw MessageSendError.rateLimited }
            // One thread per (cook, buyer) pair, like the unique index.
            let thread = threads.first { $0.cookID == cookID && $0.buyerID == me }
            let id = thread?.id ?? UUID()
            if thread == nil {
                threads.append(Conversation(
                    id: id, cookID: cookID, buyerID: me, otherName: "Cook",
                    otherAvatar: nil, lastBody: trimmed, lastKind: .text,
                    lastPayload: nil, lastAt: .now,
                    unread: 0, iAmTheCook: false
                ))
            }
            let message = Message(
                id: UUID(), conversationID: id, senderID: me,
                body: trimmed, createdAt: .now, readAt: nil
            )
            byThread[id, default: []].append(message)
            return message.id
        }
    }

    @discardableResult
    public func reply(in threadID: UUID, body: String) async throws -> UUID {
        if let gateState { throw MessageSendError.gate(gateState) }
        return lock.withLock {
            let message = Message(
                id: UUID(), conversationID: threadID, senderID: me,
                body: body.trimmingCharacters(in: .whitespacesAndNewlines),
                createdAt: .now, readAt: nil
            )
            byThread[threadID, default: []].append(message)
            return message.id
        }
    }

    public func markRead(_ threadID: UUID) async throws {}

    public func unreadTotal() async throws -> Int { 0 }

    public func gate() async throws -> MessagingGate? {
        lock.withLock { gateState }
    }

    public func hideConversation(_ threadID: UUID) async throws {
        threads.removeAll { $0.id == threadID }
    }

    public func blockBuyer(in threadID: UUID) async throws {
        lock.withLock { threads.removeAll { $0.id == threadID } }
    }

    public func unblockBuyer(_ buyerID: UUID) async throws {}
    public func blockedBuyers() async throws -> [BlockedBuyer] { [] }

    public func reportBuyer(
        in threadID: UUID, kind: BuyerReportKind, note: String?, alsoBlock: Bool
    ) async throws {
        if alsoBlock { try await blockBuyer(in: threadID) }
    }

    @discardableResult
    public func postOrder(to cookID: UUID, items: [(MenuItem, Int)], note: String?) async throws -> UUID {
        if let gateState { throw MessageSendError.gate(gateState) }
        // Mirrors the server: the summary and total are computed from the menu,
        // so the double can't be used to build a UI against client-set prices.
        let summary = items.map { "\($0.1)× \($0.0.displayName())" }.joined(separator: ", ")
        let total = items.reduce(0) { $0 + $1.0.price.amountCents * $1.1 }
        return try await send(
            to: cookID,
            body: String(format: "%@ · $%.2f", summary, Double(total) / 100),
            claimID: nil
        )
    }

    public func shareAddress(in threadID: UUID) async throws {}
    public func address(in threadID: UUID) async throws -> RevealedAddress {
        throw MessageSendError.addressNotAvailable
    }
    public func markPickedUp(in threadID: UUID) async throws {}
    public func state(of threadID: UUID) async throws -> ThreadState? { nil }
    public func registerActivityToken(threadID: UUID, token: String, activityID: String) async throws {}
    public func openOrders() async throws -> [OpenOrder] { [] }
    public func liveMessages(in threadID: UUID) -> AsyncStream<Void> { .finished }
    public func liveConversations() -> AsyncStream<Void> { .finished }
    public func registerDeviceToken(_ token: String) async throws {}
    public func forgetDeviceToken(_ token: String) async throws {}
}

import Foundation
#if SWIFT_PACKAGE
import AnkyProtocol
#endif

/// Status mirror of the server's level ledger (`GET /level/status`).
struct LevelServerStatus: Codable, Equatable {
    let totalSeconds: Int
    let level: Int
    let secondsIntoLevel: Int
    let secondsRequired: Int
    let percent: Double
    let nextLevel: Int
    let nextPaintingPhase: LevelPaintingPhase
    let nextPaintingTitle: String?
    let nextPalette: [String]?
    let pendingCeremonyLevel: Int?
}

/// Reports sealed sessions (hash + seconds only, never writing) to the server
/// ledger and reads level status back. Same signing plumbing as MirrorClient.
struct LevelSyncClient {
    let baseURL: URL
    var session: URLSession = .shared

    init(
        baseURL: URL? = URL(string: MirrorConfiguration.currentBaseURL()),
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL ?? URL(string: MirrorConfiguration.defaultBaseURL)!
        self.session = session
    }

    enum LevelSyncError: Error, Equatable {
        case invalidResponse
        case server(statusCode: Int)
    }

    @discardableResult
    func reportSessions(
        _ sessions: [LevelUnreportedSession],
        identity: WriterIdentity
    ) async throws -> LevelServerStatus {
        struct ReportBody: Encodable {
            let sessions: [LevelUnreportedSession]
        }
        let body = try JSONEncoder().encode(ReportBody(sessions: sessions))
        var request = try signedRequest(path: "level/sessions", body: body, identity: identity)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await session.data(for: request)
        try Self.ensureSuccess(response)
        struct ReportEnvelope: Decodable {
            let status: LevelServerStatus
        }
        guard let envelope = try? JSONDecoder().decode(ReportEnvelope.self, from: data) else {
            throw LevelSyncError.invalidResponse
        }
        return envelope.status
    }

    func fetchStatus(identity: WriterIdentity) async throws -> LevelServerStatus {
        var request = try signedRequest(path: "level/status", body: Data(), identity: identity)
        request.httpMethod = "GET"

        let (data, response) = try await session.data(for: request)
        try Self.ensureSuccess(response)
        struct StatusEnvelope: Decodable {
            let status: LevelServerStatus
        }
        guard let envelope = try? JSONDecoder().decode(StatusEnvelope.self, from: data) else {
            throw LevelSyncError.invalidResponse
        }
        return envelope.status
    }

    /// Asks the server to distill + paint the package for `level`. The text
    /// is the writing since the last level-up — transient on the server,
    /// distilled once, forgotten. Returns the server's phase for the level.
    @discardableResult
    func prepare(level: Int, text: String, identity: WriterIdentity) async throws -> String {
        struct PrepareBody: Encodable {
            let level: Int
            let text: String
        }
        let body = try JSONEncoder().encode(PrepareBody(level: level, text: text))
        var request = try signedRequest(path: "level/prepare", body: body, identity: identity)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await session.data(for: request)
        try Self.ensureSuccess(response)
        struct PrepareEnvelope: Decodable {
            let phase: String?
        }
        let envelope = try? JSONDecoder().decode(PrepareEnvelope.self, from: data)
        return envelope?.phase ?? "generationPending"
    }

    /// Tells the ledger the unveiling was witnessed. Idempotent server-side.
    func reportCeremonyShown(level: Int, identity: WriterIdentity) async throws {
        struct CeremonyBody: Encodable {
            let level: Int
        }
        let body = try JSONEncoder().encode(CeremonyBody(level: level))
        var request = try signedRequest(path: "level/ceremony-shown", body: body, identity: identity)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (_, response) = try await session.data(for: request)
        try Self.ensureSuccess(response)
    }

    /// Fetches one file of a level's painting package (signed empty body).
    func fetchAsset(level: Int, file: String, identity: WriterIdentity) async throws -> Data {
        var request = try signedRequest(
            path: "level/assets/\(level)/\(file)",
            body: Data(),
            identity: identity
        )
        request.httpMethod = "GET"
        let (data, response) = try await session.data(for: request)
        try Self.ensureSuccess(response)
        return data
    }

    /// Analytics only (phase-2 §2): the emergency breath completed. One
    /// signed event, nothing stored server-side, never surfaced to anyone.
    func reportEmergencyUnlock(identity: WriterIdentity) async throws {
        let body = Data("{}".utf8)
        var request = try signedRequest(path: "events/emergency-unlock", body: body, identity: identity)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (_, response) = try await session.data(for: request)
        try Self.ensureSuccess(response)
    }

    // MARK: Subscription truth and the funnel

    /// The server's answer after an identify: its webhook-maintained
    /// entitlement for this wallet. `expiresAtMs` nil is a valid entitled
    /// state (open-ended promotional or lifetime grants).
    struct SubscriptionServerState: Codable, Equatable {
        let entitled: Bool
        let productId: String?
        let expiresAtMs: Int64?
        let store: String?
        let periodType: String?
    }

    /// Tells the mirror that this wallet is the RevenueCat appUserID. The
    /// EIP-712 headers prove the wallet; RevenueCat webhooks carry the
    /// entitlement truth server-side. The server rejects any attempt to
    /// attach a different appUserID to the authenticated account.
    @discardableResult
    func identifySubscription(identity: WriterIdentity) async throws -> SubscriptionServerState {
        struct IdentifyBody: Encodable {
            let appUserId: String
        }
        let body = try JSONEncoder().encode(IdentifyBody(appUserId: identity.address))
        var request = try signedRequest(path: "subscription/identify", body: body, identity: identity)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await session.data(for: request)
        try Self.ensureSuccess(response)
        guard let state = try? JSONDecoder().decode(SubscriptionServerState.self, from: data) else {
            throw LevelSyncError.invalidResponse
        }
        return state
    }

    /// One signed funnel event (phase-3 §6). Whitelisted names server-side;
    /// hashed account, event, origin — never anything about writing.
    func reportFunnelEvent(
        _ event: String,
        origin: String? = nil,
        identity: WriterIdentity
    ) async throws {
        struct FunnelBody: Encodable {
            let event: String
            let origin: String?
        }
        let body = try JSONEncoder().encode(FunnelBody(event: event, origin: origin))
        var request = try signedRequest(path: "events/funnel", body: body, identity: identity)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (_, response) = try await session.data(for: request)
        try Self.ensureSuccess(response)
    }

    /// Drains the unreported queue: posts a batch, marks acknowledged hashes
    /// reported, and adopts the server total if it is ahead of this install.
    static func flushUnreported(
        store: LevelProgressStore = LevelProgressStore(),
        identityStore: WriterIdentityStore = WriterIdentityStore(),
        client: LevelSyncClient = LevelSyncClient()
    ) async {
        let pending = store.unreportedSessions()
        guard !pending.isEmpty, let identity = try? identityStore.loadOrCreate() else {
            return
        }
        guard let status = try? await client.reportSessions(pending, identity: identity) else {
            return
        }
        store.markReported(hashes: pending.map(\.hash))
        store.adoptServerTotalIfHigher(status.totalSeconds)
    }

    private func signedRequest(path: String, body: Data, identity: WriterIdentity) throws -> URLRequest {
        let signed = try AnkyPostSigner.sign(body: body, identity: identity)
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.setValue(signed.identityVersion, forHTTPHeaderField: "X-Anky-Identity-Version")
        request.setValue(signed.accountId, forHTTPHeaderField: "X-Anky-Account")
        request.setValue(signed.signatureType, forHTTPHeaderField: "X-Anky-Signature-Type")
        request.setValue(signed.signature, forHTTPHeaderField: "X-Anky-Signature")
        request.setValue(signed.requestTime, forHTTPHeaderField: "X-Anky-Request-Time")
        request.setValue(signed.client, forHTTPHeaderField: "X-Anky-Client")
        return request
    }

    private static func ensureSuccess(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw LevelSyncError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw LevelSyncError.server(statusCode: http.statusCode)
        }
    }
}

/// Fire-and-forget funnel reporting (phase-3 §6). Analytics never block or
/// break the practice: failures are silently dropped, the app never waits.
enum AnkyFunnel {
    static let ceremonyOneShown = "ceremony_1_shown"
    static let boundaryReached = "boundary_reached"
    static let veilTapped = "veil_tapped"
    static let paywallShown = "paywall_shown"
    static let trialStarted = "trial_started"
    static let subscribed = "subscribed"
    static let restored = "restored"
    static let lapsed = "lapsed"

    static func report(
        _ event: String,
        origin: String? = nil,
        identityStore: WriterIdentityStore = WriterIdentityStore(),
        client: LevelSyncClient = LevelSyncClient()
    ) {
        Task.detached(priority: .utility) {
            guard let identity = try? identityStore.loadOrCreate() else { return }
            try? await client.reportFunnelEvent(event, origin: origin, identity: identity)
        }
    }
}

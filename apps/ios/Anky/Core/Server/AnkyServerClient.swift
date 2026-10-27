//
//  AnkyServerClient.swift
//  Anky
//
//  The few things Anky asks its server, each signed with the writer's
//  invisible account key (EIP-712 over the exact body bytes):
//
//    POST /access/status   the free-access ledger and server time
//    POST /anky            a reflection — subscribers only, on explicit request
//    GET  /live/capabilities, POST /live/start, POST /live/stop
//
//  Nothing is sent in the background except the access status check, which
//  carries no writing at all — only `{"start": true|false}`.
//

import Foundation
#if SWIFT_PACKAGE
import AnkyProtocol
#endif

enum AnkyServer {
    static let baseURL = URL(string: "https://mirror-production-a23c.up.railway.app")!
}

enum AnkyServerError: Error, Equatable {
    case invalidResponse
    /// The server refused because the account is not a verified subscriber
    /// (HTTP 402). The server checks on its own; the app only mirrors it.
    case entitlementRequired
    case notConfigured
    case rateLimited
    case server(status: Int, code: String?)
    case offline
}

struct AccessStatusResponse: Decodable, Equatable {
    struct FreeAccessInfo: Decodable, Equatable {
        let days: Int
        let startedAtMs: Int64?
        let endsAtMs: Int64?
        let active: Bool
    }

    struct EntitlementInfo: Decodable, Equatable {
        let entitled: Bool
        let productId: String?
        let expiresAtMs: Int64?
    }

    let serverNowMs: Int64
    let freeAccess: FreeAccessInfo
    let entitlement: EntitlementInfo
    let entitlementUnknown: Bool?

    var serverNow: Date { Date(timeIntervalSince1970: TimeInterval(serverNowMs) / 1000) }
    var freeAccessStartedAt: Date? {
        freeAccess.startedAtMs.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) }
    }
}

struct LiveStartResponse: Decodable, Equatable {
    struct Ingest: Decodable, Equatable {
        let rtmpsUrl: String
        let streamKey: String
        let whipUrl: String?
    }

    let liveId: String
    let ingest: Ingest
    let viewerUrl: String
    let maxDurationSeconds: Int
}

struct ReflectionResult: Equatable {
    let hash: String
    let markdown: String
}

struct AnkyServerClient {
    var baseURL: URL = AnkyServer.baseURL
    var session: URLSession = .shared

    // MARK: Access

    func accessStatus(start: Bool, identity: WriterIdentity) async throws -> AccessStatusResponse {
        let body = try JSONSerialization.data(withJSONObject: ["start": start], options: [.sortedKeys])
        let data = try await send(path: "access/status", body: body, contentType: "application/json", identity: identity)
        guard let decoded = try? JSONDecoder().decode(AccessStatusResponse.self, from: data) else {
            throw AnkyServerError.invalidResponse
        }
        return decoded
    }

    // MARK: Reflection (subscribers only — enforced by the server)

    func reflect(ankyBytes: Data, identity: WriterIdentity, appVersion: String?) async throws -> ReflectionResult {
        var headers = ["X-Anky-Intent": "reflection", "Accept": "text/plain"]
        if let appVersion { headers["X-Anky-App-Version"] = appVersion }
        let (data, response) = try await sendRaw(
            path: "anky",
            body: ankyBytes,
            contentType: "text/plain; charset=utf-8",
            identity: identity,
            extraHeaders: headers
        )
        guard let markdown = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !markdown.isEmpty else {
            throw AnkyServerError.invalidResponse
        }
        // Older servers answered "no provider reachable" with a 200 and a
        // placeholder text. That is a failure, never a reflection to keep.
        if Self.isPlaceholderReflection(markdown) {
            throw AnkyServerError.server(status: 503, code: "REFLECTION_PROVIDER_UNAVAILABLE")
        }
        let hash = response.value(forHTTPHeaderField: "X-Anky-Hash") ?? AnkyHasher.sha256Hex(ankyBytes)
        return ReflectionResult(hash: hash, markdown: markdown)
    }

    // MARK: Live

    func liveAvailable() async -> Bool {
        var request = URLRequest(url: baseURL.appendingPathComponent("live/capabilities"))
        request.timeoutInterval = 8
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        return object["available"] as? Bool ?? false
    }

    func startLive(sessionID: UUID, audience: String, identity: WriterIdentity) async throws -> LiveStartResponse {
        let body = try JSONSerialization.data(
            withJSONObject: ["sessionId": sessionID.uuidString.lowercased(), "audience": audience],
            options: [.sortedKeys]
        )
        let data = try await send(path: "live/start", body: body, contentType: "application/json", identity: identity)
        guard let decoded = try? JSONDecoder().decode(LiveStartResponse.self, from: data) else {
            throw AnkyServerError.invalidResponse
        }
        return decoded
    }

    func stopLive(liveId: String, identity: WriterIdentity) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["liveId": liveId], options: [.sortedKeys])
        _ = try await send(path: "live/stop", body: body, contentType: "application/json", identity: identity)
    }

    // MARK: Transport

    private func send(path: String, body: Data, contentType: String, identity: WriterIdentity) async throws -> Data {
        try await sendRaw(path: path, body: body, contentType: contentType, identity: identity, extraHeaders: [:]).0
    }

    private func sendRaw(
        path: String,
        body: Data,
        contentType: String,
        identity: WriterIdentity,
        extraHeaders: [String: String]
    ) async throws -> (Data, HTTPURLResponse) {
        let request = try Self.signedRequest(
            url: baseURL.appendingPathComponent(path),
            body: body,
            contentType: contentType,
            identity: identity,
            extraHeaders: extraHeaders
        )
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where Self.offlineCodes.contains(error.code) {
            throw AnkyServerError.offline
        }
        guard let http = response as? HTTPURLResponse else { throw AnkyServerError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw Self.error(status: http.statusCode, body: data)
        }
        return (data, http)
    }

    static func signedRequest(
        url: URL,
        body: Data,
        contentType: String,
        identity: WriterIdentity,
        extraHeaders: [String: String] = [:],
        requestTime: UInt64? = nil
    ) throws -> URLRequest {
        let signed = try requestTime.map {
            try AnkyPostSigner.sign(body: body, identity: identity, requestTime: $0)
        } ?? AnkyPostSigner.sign(body: body, identity: identity)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.timeoutInterval = 60
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue(signed.identityVersion, forHTTPHeaderField: "X-Anky-Identity-Version")
        request.setValue(signed.accountId, forHTTPHeaderField: "X-Anky-Account")
        request.setValue(signed.signatureType, forHTTPHeaderField: "X-Anky-Signature-Type")
        request.setValue(signed.signature, forHTTPHeaderField: "X-Anky-Signature")
        request.setValue(signed.requestTime, forHTTPHeaderField: "X-Anky-Request-Time")
        request.setValue(signed.client, forHTTPHeaderField: "X-Anky-Client")
        for (field, value) in extraHeaders {
            request.setValue(value, forHTTPHeaderField: field)
        }
        return request
    }

    static func error(status: Int, body: Data) -> AnkyServerError {
        let code: String? = {
            guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return nil }
            if let error = object["error"] as? [String: Any] { return error["code"] as? String }
            return object["error"] as? String
        }()
        switch (status, code) {
        case (402, _), (_, "ENTITLEMENT_REQUIRED"): return .entitlementRequired
        case (503, "LIVE_NOT_CONFIGURED"): return .notConfigured
        case (429, _): return .rateLimited
        default: return .server(status: status, code: code)
        }
    }

    static func isPlaceholderReflection(_ markdown: String) -> Bool {
        markdown.lowercased().hasPrefix("# mirror unavailable")
            || markdown.contains("could not safely reach a confirmed private reflection provider")
    }

    private static let offlineCodes: Set<URLError.Code> = [
        .notConnectedToInternet, .networkConnectionLost, .timedOut,
        .cannotFindHost, .cannotConnectToHost, .dataNotAllowed, .internationalRoamingOff
    ]
}

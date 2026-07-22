import Foundation
#if SWIFT_PACKAGE
import AnkyProtocol
#endif

struct MirrorClient {
    let baseURL: URL
    var session: URLSession = .shared

    enum Intent: String {
        case reflection
        case nudge
    }

    func askAnky(
        bytes: Data,
        identity: WriterIdentity,
        appVersion: String? = nil,
        intent: Intent = .reflection,
        surface: String? = nil,
        progress: ((MirrorProgressEvent) async -> Void)? = nil,
        reflectionChunk: ((MirrorReflectionChunkEvent) async -> Void)? = nil
    ) async throws -> MirrorResponsePayload {
        let request = try makeRequest(
            bytes: bytes,
            identity: identity,
            appVersion: appVersion,
            intent: intent,
            surface: surface
        )
        let (stream, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw MirrorClientError.invalidResponse
        }

        if !(200..<300).contains(http.statusCode) {
            let data = try await Self.collect(stream)
            if let envelope = try? JSONDecoder().decode(MirrorErrorEnvelope.self, from: data) {
                throw MirrorClientError.server(envelope.error.payload)
            }
            throw MirrorClientError.server(.fallback)
        }

        var currentEvent: String?
        var dataLines: [String] = []

        func flushEvent() async throws -> MirrorResponsePayload? {
            guard let currentEvent else {
                dataLines.removeAll()
                return nil
            }
            let payload = dataLines.joined(separator: "\n")
            dataLines.removeAll()
            switch currentEvent {
            case "update":
                if let data = payload.data(using: .utf8),
                   let event = try? JSONDecoder().decode(MirrorProgressEvent.self, from: data) {
                    await progress?(event)
                }
                return nil
            case "reflection_chunk":
                if let data = payload.data(using: .utf8),
                   let event = try? JSONDecoder().decode(MirrorReflectionChunkEvent.self, from: data) {
                    await reflectionChunk?(event)
                }
                return nil
            case "reflection":
                guard let data = payload.data(using: .utf8),
                      let event = try? JSONDecoder().decode(MirrorReflectionEvent.self, from: data) else {
                    throw MirrorClientError.invalidResponse
                }
                let reflection = event.markdown.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !reflection.isEmpty else {
                    throw MirrorClientError.invalidResponse
                }
                let hash = event.headers.value(forHTTPHeaderField: "X-Anky-Hash") ?? AnkyHasher.sha256Hex(bytes)
                let tags = event.tags ?? event.headers
                    .value(forHTTPHeaderField: "X-Anky-Tags")
                    .flatMap(Self.tags)
                    ?? []
                return MirrorResponsePayload(
                    hash: hash,
                    title: Self.title(fromMarkdown: reflection),
                    reflection: reflection,
                    tags: tags
                )
            case "error":
                throw MirrorClientError.server(Self.errorPayload(fromSSEPayload: payload))
            default:
                return nil
            }
        }

        for try await line in stream.lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            if trimmedLine.isEmpty {
                if let payload = try await flushEvent() {
                    return payload
                }
                currentEvent = nil
                continue
            }
            if trimmedLine.hasPrefix("event:") {
                if currentEvent != nil {
                    if let payload = try await flushEvent() {
                        return payload
                    }
                }
                currentEvent = String(trimmedLine.dropFirst("event:".count)).trimmingCharacters(in: .whitespaces)
            } else if trimmedLine.hasPrefix("data:") {
                dataLines.append(String(trimmedLine.dropFirst("data:".count)).trimmingCharacters(in: .whitespaces))
            }
        }

        if let payload = try await flushEvent() {
            return payload
        }
        throw MirrorClientError.invalidResponse
    }

    private func makeRequest(
        bytes: Data,
        identity: WriterIdentity,
        appVersion: String?,
        intent: Intent,
        surface: String? = nil
    ) throws -> URLRequest {
        let signed = try AnkyPostSigner.sign(body: bytes, identity: identity)
        var request = URLRequest(url: baseURL.appendingPathComponent("anky"))
        request.httpMethod = "POST"
        request.httpBody = bytes
        request.setValue("text/plain; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue(signed.identityVersion, forHTTPHeaderField: "X-Anky-Identity-Version")
        request.setValue(signed.accountId, forHTTPHeaderField: "X-Anky-Account")
        request.setValue(signed.signatureType, forHTTPHeaderField: "X-Anky-Signature-Type")
        request.setValue(signed.signature, forHTTPHeaderField: "X-Anky-Signature")
        request.setValue(signed.requestTime, forHTTPHeaderField: "X-Anky-Request-Time")
        request.setValue(signed.client, forHTTPHeaderField: "X-Anky-Client")
        request.setValue(intent.rawValue, forHTTPHeaderField: "X-Anky-Intent")
        if let appVersion {
            request.setValue(appVersion, forHTTPHeaderField: "X-Anky-App-Version")
        }
        if let surface {
            request.setValue(surface, forHTTPHeaderField: "X-Anky-Surface")
        }
        return request
    }

    private static func collect(_ bytes: URLSession.AsyncBytes) async throws -> Data {
        var data = Data()
        for try await byte in bytes {
            data.append(contentsOf: [byte])
        }
        return data
    }

    private static func tags(_ value: String) -> [String]? {
        guard let data = value.data(using: .utf8),
              let tags = try? JSONDecoder().decode([String].self, from: data) else {
            return nil
        }
        return tags
    }

    private static func errorPayload(fromSSEPayload payload: String) -> MirrorServerErrorPayload {
        guard let data = payload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .fallback
        }
        if let body = object["body"] as? [String: Any],
           let error = body["error"] as? [String: Any],
           let message = error["message"] as? String {
            return MirrorServerErrorPayload(code: error["code"] as? String, message: message)
        }
        if let message = object["message"] as? String {
            return MirrorServerErrorPayload(code: object["code"] as? String, message: message)
        }
        return .fallback
    }

    private static func title(fromMarkdown markdown: String) -> String {
        let lines = markdown.split(whereSeparator: \.isNewline).map(String.init)
        let heading = lines.first { $0.hasPrefix("# ") }?
            .dropFirst(2)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = lines.first?.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = heading?.isEmpty == false ? heading : fallback
        return title?.isEmpty == false ? title! : "reflection"
    }
}

struct MirrorProgressEvent: Codable, Equatable {
    let stage: String
    let message: String?
}

struct MirrorReflectionChunkEvent: Codable, Equatable {
    let chunk: String
    let generatedCharacters: Int
}

struct MirrorResponsePayload: Codable, Equatable {
    let hash: String
    let title: String
    let reflection: String
    let tags: [String]
}

struct MirrorServerErrorPayload: Equatable {
    let code: String?
    let message: String

    static let fallback = MirrorServerErrorPayload(
        code: nil,
        message: "Anky could not return a reflection right now."
    )

    var isEntitlementDenied: Bool {
        // ENTITLEMENT_REQUIRED is the boundary's only denial for a
        // non-entitled account. Free clients never ask, so this is the
        // defensive mapping for stale state: it reads as the veil, never
        // as an error.
        code == "ENTITLEMENT_REQUIRED"
    }
}

enum MirrorClientError: Error, LocalizedError, Equatable {
    case invalidURL
    case invalidResponse
    case hashMismatch
    case server(MirrorServerErrorPayload)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The mirror URL is not valid."
        case .invalidResponse:
            return "The mirror returned an invalid response."
        case .hashMismatch:
            return "The mirror response did not match this .anky."
        case .server(let payload):
            return payload.message
        }
    }

    var serverPayload: MirrorServerErrorPayload? {
        guard case .server(let payload) = self else { return nil }
        return payload
    }
}

private struct MirrorErrorEnvelope: Decodable {
    let error: MirrorError
}

private struct MirrorError: Decodable {
    let code: String?
    let message: String

    var payload: MirrorServerErrorPayload {
        MirrorServerErrorPayload(code: code, message: message)
    }
}

private struct MirrorReflectionEvent: Decodable {
    let markdown: String
    let tags: [String]?
    let headers: [String: String]
}

private extension Dictionary where Key == String, Value == String {
    func value(forHTTPHeaderField field: String) -> String? {
        first { key, _ in key.caseInsensitiveCompare(field) == .orderedSame }?.value
    }
}

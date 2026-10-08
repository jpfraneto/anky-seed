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
        ageYears: Int? = nil,
        progress: ((MirrorProgressEvent) async -> Void)? = nil,
        reflectionChunk: ((MirrorReflectionChunkEvent) async -> Void)? = nil
    ) async throws -> MirrorResponsePayload {
        let request = try makeRequest(
            bytes: bytes,
            identity: identity,
            appVersion: appVersion,
            intent: intent,
            surface: surface,
            ageYears: ageYears
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
        var streamedReflection = ""
        var serverReportedComplete = false

        // SSE is deliberately the transport so the writing can begin to come
        // back before generation ends. If the connection loses only its final
        // envelope after the server has announced completion, the streamed
        // markdown is already the complete reflection and must not be thrown
        // away (or paid for/generated a second time).
        func recoveredCompletedStream() -> MirrorResponsePayload? {
            let reflection = streamedReflection.trimmingCharacters(in: .whitespacesAndNewlines)
            guard serverReportedComplete, !reflection.isEmpty else { return nil }
            return MirrorResponsePayload(
                hash: AnkyHasher.sha256Hex(bytes),
                title: Self.title(fromMarkdown: reflection),
                reflection: reflection,
                tags: [],
                inference: nil
            )
        }

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
                    if event.stage == "complete" {
                        serverReportedComplete = true
                    }
                    await progress?(event)
                }
                return nil
            case "reflection_chunk":
                if let data = payload.data(using: .utf8),
                   let event = try? JSONDecoder().decode(MirrorReflectionChunkEvent.self, from: data) {
                    streamedReflection += event.chunk
                    await reflectionChunk?(event)
                }
                return nil
            case "reflection":
                guard let data = payload.data(using: .utf8),
                      let event = try? JSONDecoder().decode(MirrorReflectionEvent.self, from: data) else {
                    if let recovered = recoveredCompletedStream() {
                        return recovered
                    }
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
                let inference = Self.inferenceReceipt(from: event.headers)
                return MirrorResponsePayload(
                    hash: hash,
                    title: Self.title(fromMarkdown: reflection),
                    reflection: reflection,
                    tags: tags,
                    inference: inference
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
        if let recovered = recoveredCompletedStream() {
            return recovered
        }
        throw MirrorClientError.invalidResponse
    }

    private func makeRequest(
        bytes: Data,
        identity: WriterIdentity,
        appVersion: String?,
        intent: Intent,
        surface: String? = nil,
        ageYears: Int? = nil
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
        if let ageYears, (0...120).contains(ageYears) {
            request.setValue(String(ageYears), forHTTPHeaderField: "X-Anky-Age-Years")
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

    private static func inferenceReceipt(from headers: [String: String]) -> AnkyInferenceReceipt? {
        guard let accessValue = headers.value(forHTTPHeaderField: "X-Anky-Inference-Access"),
              let access = AnkyInferenceReceipt.Access(rawValue: accessValue),
              let provider = headers.value(forHTTPHeaderField: "X-Anky-Inference-Provider") else {
            return nil
        }
        let cost = headers.value(forHTTPHeaderField: "X-Anky-Inference-Cost-USD").flatMap(Double.init)
        return AnkyInferenceReceipt(
            access: access,
            provider: provider,
            model: headers.value(forHTTPHeaderField: "X-Anky-Inference-Model"),
            costUsd: cost
        )
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
    let inference: AnkyInferenceReceipt?

    init(
        hash: String,
        title: String,
        reflection: String,
        tags: [String],
        inference: AnkyInferenceReceipt? = nil
    ) {
        self.hash = hash
        self.title = title
        self.reflection = reflection
        self.tags = tags
        self.inference = inference
    }
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

struct AnkyConversationClient {
    let baseURL: URL
    var session: URLSession = .shared

    func reply(
        writing: String,
        reflection: String,
        messages: [AnkyConversationMessage],
        identity: WriterIdentity,
        ageYears: Int?
    ) async throws -> ConversationReply {
        let payload = ConversationRequestPayload(
            writing: writing,
            reflection: reflection,
            messages: messages.map { .init(role: $0.role.rawValue, content: $0.content) },
            ageYears: ageYears
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let body = try encoder.encode(payload)
        let signed = try AnkyPostSigner.sign(body: body, identity: identity)

        var request = URLRequest(url: baseURL.appendingPathComponent("conversation"))
        request.httpMethod = "POST"
        request.httpBody = body
        request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(signed.identityVersion, forHTTPHeaderField: "X-Anky-Identity-Version")
        request.setValue(signed.accountId, forHTTPHeaderField: "X-Anky-Account")
        request.setValue(signed.signatureType, forHTTPHeaderField: "X-Anky-Signature-Type")
        request.setValue(signed.signature, forHTTPHeaderField: "X-Anky-Signature")
        request.setValue(signed.requestTime, forHTTPHeaderField: "X-Anky-Request-Time")
        request.setValue(signed.client, forHTTPHeaderField: "X-Anky-Client")
        request.setValue(AnkyAppVersion.headerValue, forHTTPHeaderField: "X-Anky-App-Version")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw MirrorClientError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            if let envelope = try? JSONDecoder().decode(MirrorErrorEnvelope.self, from: data) {
                throw MirrorClientError.server(envelope.error.payload)
            }
            throw MirrorClientError.server(.fallback)
        }
        guard let result = try? JSONDecoder().decode(ConversationResponsePayload.self, from: data) else {
            throw MirrorClientError.invalidResponse
        }
        let answer = result.message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty else { throw MirrorClientError.invalidResponse }
        return ConversationReply(message: answer, inference: result.inference)
    }
}

struct ConversationReply {
    let message: String
    let inference: AnkyInferenceReceipt?
}

private struct ConversationRequestPayload: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    let writing: String
    let reflection: String
    let messages: [Message]
    let ageYears: Int?
}

private struct ConversationResponsePayload: Decodable {
    let message: String
    let inference: AnkyInferenceReceipt?
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

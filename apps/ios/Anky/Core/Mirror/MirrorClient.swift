import Foundation
#if SWIFT_PACKAGE
import AnkyProtocol
#endif

struct MirrorClient {
    let baseURL: URL
    var session: URLSession = .shared

    func askAnky(
        bytes: Data,
        identity: WriterIdentity,
        trialProof: String? = nil,
        appVersion: String? = nil
    ) async throws -> MirrorResponsePayload {
        let signed = try AnkyPostSigner.sign(body: bytes, identity: identity)
        var request = URLRequest(url: baseURL.appendingPathComponent("anky"))
        request.httpMethod = "POST"
        request.httpBody = bytes
        request.setValue("text/plain; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("text/markdown, text/plain", forHTTPHeaderField: "Accept")
        request.setValue(signed.identityVersion, forHTTPHeaderField: "X-Anky-Identity-Version")
        request.setValue(signed.accountId, forHTTPHeaderField: "X-Anky-Account")
        request.setValue(signed.signatureType, forHTTPHeaderField: "X-Anky-Signature-Type")
        request.setValue(signed.signature, forHTTPHeaderField: "X-Anky-Signature")
        request.setValue(signed.requestTime, forHTTPHeaderField: "X-Anky-Request-Time")
        request.setValue(signed.client, forHTTPHeaderField: "X-Anky-Client")
        if let appVersion {
            request.setValue(appVersion, forHTTPHeaderField: "X-Anky-App-Version")
        }
        if let trialProof {
            request.setValue(trialProof, forHTTPHeaderField: "X-Anky-Trial-Proof")
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw MirrorClientError.invalidResponse
        }

        if (200..<300).contains(http.statusCode) {
            guard let reflection = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !reflection.isEmpty else {
                throw MirrorClientError.invalidResponse
            }
            let hash = http.value(forHTTPHeaderField: "X-Anky-Hash") ?? AnkyHasher.sha256Hex(bytes)
            let creditsRemaining = http.value(forHTTPHeaderField: "X-Anky-Credits-Remaining").flatMap(Self.creditsRemaining)
            return MirrorResponsePayload(
                hash: hash,
                title: Self.title(fromMarkdown: reflection),
                reflection: reflection,
                creditsRemaining: creditsRemaining
            )
        }

        if let envelope = try? JSONDecoder().decode(MirrorErrorEnvelope.self, from: data) {
            throw MirrorClientError.server(envelope.error.message)
        }
        throw MirrorClientError.server("Anky could not return a reflection right now.")
    }

    private static func creditsRemaining(_ value: String) -> Int? {
        value == "null" ? nil : Int(value)
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

struct MirrorResponsePayload: Codable, Equatable {
    let hash: String
    let title: String
    let reflection: String
    let creditsRemaining: Int?
}

enum MirrorClientError: Error, LocalizedError, Equatable {
    case invalidURL
    case invalidResponse
    case hashMismatch
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The mirror URL is not valid."
        case .invalidResponse:
            return "The mirror returned an invalid response."
        case .hashMismatch:
            return "The mirror response did not match this .anky."
        case .server(let message):
            return message
        }
    }
}

private struct MirrorErrorEnvelope: Decodable {
    let error: MirrorError
}

private struct MirrorError: Decodable {
    let message: String
}

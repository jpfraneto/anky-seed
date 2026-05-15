import Foundation

struct MirrorClient {
    let baseURL: URL
    var session: URLSession = .shared

    func askAnky(bytes: Data, identity: WriterIdentity) async throws -> MirrorResponsePayload {
        let signed = try AnkyPostSigner.sign(body: bytes, identity: identity)
        var request = URLRequest(url: baseURL.appendingPathComponent("anky"))
        request.httpMethod = "POST"
        request.httpBody = bytes
        request.setValue("text/plain; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(signed.publicKey, forHTTPHeaderField: "X-Anky-Public-Key")
        request.setValue(signed.signature, forHTTPHeaderField: "X-Anky-Signature")
        request.setValue(signed.requestTime, forHTTPHeaderField: "X-Anky-Request-Time")
        request.setValue("ios", forHTTPHeaderField: "X-Anky-Client")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw MirrorClientError.invalidResponse
        }

        if (200..<300).contains(http.statusCode) {
            return try JSONDecoder().decode(MirrorResponsePayload.self, from: data)
        }

        if let envelope = try? JSONDecoder().decode(MirrorErrorEnvelope.self, from: data) {
            throw MirrorClientError.server(envelope.error.message)
        }
        throw MirrorClientError.server("Anky could not return a reflection right now.")
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

import XCTest
@testable import AnkyCore
@testable import AnkyProtocol

final class MirrorClientTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    func testMirrorClientSendsExactAnkyBodyAndSignatureHeaders() async throws {
        let body = Data("1770000000000 h\n480000 i".utf8)
        let expectedHash = AnkyHasher.sha256Hex(body)
        let identity = WriterIdentity.generate()

        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "http://127.0.0.1:3000/anky")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "text/plain; charset=utf-8")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "text/event-stream")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Anky-Client"), "ios")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Anky-Intent"), "reflection")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Anky-App-Version"), "1.0(1)")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Anky-Trial-Proof"), "trial-proof")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Anky-Identity-Version"), "anky.base.eoa.v1")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Anky-Account"), identity.accountId)
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Anky-Signature-Type"), "eip712")
            XCTAssertNotNil(request.value(forHTTPHeaderField: "X-Anky-Signature"))
            XCTAssertNotNil(request.value(forHTTPHeaderField: "X-Anky-Request-Time"))
            XCTAssertNil(request.value(forHTTPHeaderField: "X-Anky-Public-Key"))
            XCTAssertEqual(request.ankyTestBodyData(), body)

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: [
                    "Content-Type": "text/event-stream; charset=utf-8"
                ]
            )!
            var payload = Data("event: update\ndata: {\"stage\":\"request_received\",\"message\":\"received\"}\n\n".utf8)
            payload.append(Data("event: reflection_chunk\ndata: {\"chunk\":\"# Small \",\"generatedCharacters\":8}\n\n".utf8))
            payload.append(Data("event: reflection_chunk\ndata: {\"chunk\":\"Thread\",\"generatedCharacters\":14}\n\n".utf8))
            payload.append(sseReflection(
                markdown: "# Small Thread\n\nHere is what I saw.",
                hash: expectedHash,
                creditsRemaining: "null",
                tags: ["steady thread"]
            ))
            return (response, payload)
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = MirrorClient(baseURL: URL(string: "http://127.0.0.1:3000")!, session: session)
        var streamedChunks: [MirrorReflectionChunkEvent] = []

        let response = try await client.askAnky(
            bytes: body,
            identity: identity,
            trialProof: "trial-proof",
            appVersion: "1.0(1)",
            reflectionChunk: { event in
                streamedChunks.append(event)
            }
        )

        XCTAssertEqual(response.hash, expectedHash)
        XCTAssertEqual(response.title, "Small Thread")
        XCTAssertEqual(response.reflection, "# Small Thread\n\nHere is what I saw.")
        XCTAssertEqual(response.tags, ["steady thread"])
        XCTAssertNil(response.creditsRemaining)
        XCTAssertEqual(streamedChunks, [
            MirrorReflectionChunkEvent(chunk: "# Small ", generatedCharacters: 8),
            MirrorReflectionChunkEvent(chunk: "Thread", generatedCharacters: 14)
        ])
    }

    func testMirrorClientCanRequestNudgeIntent() async throws {
        let body = Data("1770000000000 h\n4000 i".utf8)
        let expectedHash = AnkyHasher.sha256Hex(body)
        let identity = WriterIdentity.generate()

        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Anky-Intent"), "nudge")
            XCTAssertEqual(request.ankyTestBodyData(), body)

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: [
                    "Content-Type": "text/event-stream; charset=utf-8"
                ]
            )!
            let payload = sseReflection(
                markdown: "follow the warm sentence.",
                hash: expectedHash,
                creditsRemaining: "6"
            )
            return (response, payload)
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = MirrorClient(baseURL: URL(string: "http://127.0.0.1:3000")!, session: session)

        let response = try await client.askAnky(bytes: body, identity: identity, intent: .nudge)

        XCTAssertEqual(response.hash, expectedHash)
        XCTAssertEqual(response.reflection, "follow the warm sentence.")
        XCTAssertEqual(response.creditsRemaining, 6)
    }

    func testMirrorResponseParsesUpdatedCreditBalance() async throws {
        let body = Data("1770000000000 h\n480000 i".utf8)
        let expectedHash = AnkyHasher.sha256Hex(body)
        let identity = WriterIdentity.generate()

        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: [
                    "Content-Type": "text/event-stream; charset=utf-8"
                ]
            )!
            let payload = sseReflection(
                markdown: "# Small Thread\n\nHere is what I saw.",
                hash: expectedHash,
                creditsRemaining: "7"
            )
            return (response, payload)
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = MirrorClient(baseURL: URL(string: "http://127.0.0.1:3000")!, session: session)

        let response = try await client.askAnky(bytes: body, identity: identity)

        XCTAssertEqual(response.creditsRemaining, 7)
    }

    func testMirrorClientPreservesServerErrorCode() async throws {
        let body = Data("1770000000000 h\n480000 i".utf8)
        let identity = WriterIdentity.generate()
        let message = "This device already used its free Anky reflections. Buy credits to reflect more writing."

        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 402,
                httpVersion: nil,
                headerFields: [
                    "Content-Type": "application/json; charset=utf-8"
                ]
            )!
            let payload = Data("""
            {"error":{"code":"TRIAL_ALREADY_CLAIMED","message":"\(message)"}}
            """.utf8)
            return (response, payload)
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = MirrorClient(baseURL: URL(string: "http://127.0.0.1:3000")!, session: session)

        do {
            _ = try await client.askAnky(bytes: body, identity: identity)
            XCTFail("Expected the mirror client to throw the server error.")
        } catch let error as MirrorClientError {
            XCTAssertEqual(error.serverPayload?.code, "TRIAL_ALREADY_CLAIMED")
            XCTAssertEqual(error.serverPayload?.message, message)
            XCTAssertTrue(error.serverPayload?.isTrialAlreadyClaimed == true)
            XCTAssertTrue(error.serverPayload?.isCreditDenied == true)
            XCTAssertEqual(error.errorDescription, message)
        }
    }

    func testDeviceCheckProofProviderDoesNotCrashWhenUnavailable() async {
        let token = await DeviceCheckTrialProofProvider.makeToken()
        if token != nil {
            XCTAssertFalse(token!.isEmpty)
        }
    }
}

private func sseReflection(
    markdown: String,
    hash: String,
    creditsRemaining: String,
    tags: [String] = []
) -> Data {
    let object: [String: Any] = [
        "markdown": markdown,
        "tags": tags,
        "headers": [
            "X-Anky-Hash": hash,
            "X-Anky-Credits-Remaining": creditsRemaining
        ]
    ]
    let json = String(data: try! JSONSerialization.data(withJSONObject: object), encoding: .utf8)!
    return Data("event: reflection\ndata: \(json)\n\n".utf8)
}

private final class MockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private extension URLRequest {
    func ankyTestBodyData() -> Data? {
        if let httpBody {
            return httpBody
        }

        guard let stream = httpBodyStream else {
            return nil
        }

        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 {
                break
            }
            data.append(buffer, count: count)
        }
        return data
    }
}

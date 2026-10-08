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
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Anky-Age-Years"), "16")
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
                tags: ["steady thread"],
                inferenceHeaders: [
                    "X-Anky-Inference-Access": "free",
                    "X-Anky-Inference-Provider": "openrouter",
                    "X-Anky-Inference-Model": "free/example-model",
                    "X-Anky-Inference-Cost-USD": "0.00000000"
                ]
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
            appVersion: "1.0(1)",
            ageYears: 16,
            reflectionChunk: { event in
                streamedChunks.append(event)
            }
        )

        XCTAssertEqual(response.hash, expectedHash)
        XCTAssertEqual(response.title, "Small Thread")
        XCTAssertEqual(response.reflection, "# Small Thread\n\nHere is what I saw.")
        XCTAssertEqual(response.tags, ["steady thread"])
        XCTAssertEqual(response.inference?.access, .free)
        XCTAssertEqual(response.inference?.provider, "openrouter")
        XCTAssertEqual(response.inference?.model, "free/example-model")
        XCTAssertEqual(response.inference?.costUsd, 0)
        XCTAssertEqual(streamedChunks, [
            MirrorReflectionChunkEvent(chunk: "# Small ", generatedCharacters: 8),
            MirrorReflectionChunkEvent(chunk: "Thread", generatedCharacters: 14)
        ])
    }

    /// Opt-in production seam check. It is skipped in ordinary test runs and
    /// uses a throwaway identity. Set the value to `full` for the complete fixture.
    func testLiveProductionMirrorStreamWhenExplicitlyEnabled() async throws {
        let liveMode = ProcessInfo.processInfo.environment["ANKY_LIVE_MIRROR_TEST"]
        guard liveMode == "1" || liveMode == "full" else {
            throw XCTSkip("Set ANKY_LIVE_MIRROR_TEST=1 to exercise the live SSE seam.")
        }
        let body: Data
        if liveMode == "full" {
            let testDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            body = try Data(contentsOf: testDirectory
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("protocol/fixtures/valid-complete.anky"))
        } else {
            body = Data("1770000000000 h\n216 i".utf8)
        }
        let identity = WriterIdentity.generate()
        var stages: [String] = []
        var chunks: [String] = []
        let startedAt = Date()
        var firstProgressLatency: TimeInterval?
        var firstChunkLatency: TimeInterval?

        let response = try await MirrorClient(
            baseURL: URL(string: MirrorConfiguration.defaultBaseURL)!
        ).askAnky(
            bytes: body,
            identity: identity,
            appVersion: "live-seam-test",
            surface: "axis",
            progress: {
                firstProgressLatency = firstProgressLatency ?? Date().timeIntervalSince(startedAt)
                stages.append($0.stage)
            },
            reflectionChunk: {
                firstChunkLatency = firstChunkLatency ?? Date().timeIntervalSince(startedAt)
                chunks.append($0.chunk)
            }
        )

        XCTAssertEqual(response.hash, AnkyHasher.sha256Hex(body))
        XCTAssertFalse(response.reflection.isEmpty)
        XCTAssertFalse(chunks.joined().isEmpty)
        XCTAssertTrue(stages.contains("complete"))
        print("Live mirror first progress: \(firstProgressLatency ?? -1)s; chunks: \(chunks.count); first chunk: \(firstChunkLatency ?? -1)s; complete: \(Date().timeIntervalSince(startedAt))s")
    }

    func testConversationClientSignsJSONAndSendsOnlyDerivedAge() async throws {
        let identity = WriterIdentity.generate()
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "http://127.0.0.1:3000/conversation")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            XCTAssertNotNil(request.value(forHTTPHeaderField: "X-Anky-Signature"))
            let body = try XCTUnwrap(request.ankyTestBodyData())
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(json["ageYears"] as? Int, 16)
            XCTAssertNil(json["birthDate"])
            XCTAssertEqual((json["messages"] as? [[String: Any]])?.first?["content"] as? String, "what do you see?")

            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data("""
                {"message":"A quieter choice is appearing.","inference":{"access":"free","provider":"openrouter","model":"free/example-model","costUsd":0}}
                """.utf8))
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let client = AnkyConversationClient(
            baseURL: URL(string: "http://127.0.0.1:3000")!,
            session: URLSession(configuration: configuration)
        )
        let reply = try await client.reply(
            writing: "I keep circling.",
            reflection: "The circle has patience.",
            messages: [AnkyConversationMessage(role: .user, content: "what do you see?")],
            identity: identity,
            ageYears: 16
        )
        XCTAssertEqual(reply.message, "A quieter choice is appearing.")
        XCTAssertEqual(reply.inference?.disclosureLine, "free intelligence · free/example-model · $0")
    }

    func testMirrorConfigurationNormalizesAndPersistsHTTPSBaseURL() throws {
        let suite = "MirrorClientTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let url = try MirrorConfiguration.save("  https://example.com/anky/  ", defaults: defaults)

        XCTAssertEqual(url.absoluteString, "https://example.com/anky")
        XCTAssertEqual(MirrorConfiguration.currentBaseURL(defaults: defaults), "https://example.com/anky")
        MirrorConfiguration.reset(defaults: defaults)
        XCTAssertEqual(MirrorConfiguration.currentBaseURL(defaults: defaults), MirrorConfiguration.defaultBaseURL)
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
                hash: expectedHash
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
    }

    func testMirrorClientKeepsACompletedStreamWhenFinalEnvelopeIsLost() async throws {
        let body = Data("1770000000000 h\n480000 i".utf8)
        let expectedHash = AnkyHasher.sha256Hex(body)
        let identity = WriterIdentity.generate()

        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "text/event-stream; charset=utf-8"]
            )!
            let payload = Data("""
                event: reflection_chunk
                data: {"chunk":"# The Thread\\n\\n","generatedCharacters":14}

                event: update
                data: {"stage":"complete","message":"done"}

                event: reflection_chunk
                data: {"chunk":"It came all the way back.","generatedCharacters":39}

                """.utf8)
            return (response, payload)
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let client = MirrorClient(
            baseURL: URL(string: "http://127.0.0.1:3000")!,
            session: URLSession(configuration: configuration)
        )

        let response = try await client.askAnky(bytes: body, identity: identity)

        XCTAssertEqual(response.hash, expectedHash)
        XCTAssertEqual(response.title, "The Thread")
        XCTAssertEqual(response.reflection, "# The Thread\n\nIt came all the way back.")
        XCTAssertEqual(response.tags, [])
        XCTAssertNil(response.inference)
    }

    func testMirrorClientPreservesServerErrorCode() async throws {
        let body = Data("1770000000000 h\n480000 i".utf8)
        let identity = WriterIdentity.generate()
        let message = "The mirror is resting."

        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 503,
                httpVersion: nil,
                headerFields: [
                    "Content-Type": "application/json; charset=utf-8"
                ]
            )!
            let payload = Data("""
            {"error":{"code":"MIRROR_FAILED","message":"\(message)"}}
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
            XCTAssertEqual(error.serverPayload?.code, "MIRROR_FAILED")
            XCTAssertEqual(error.serverPayload?.message, message)
            XCTAssertFalse(error.serverPayload?.isEntitlementDenied == true)
            XCTAssertEqual(error.errorDescription, message)
        }
    }

    func testEntitlementRequiredDenyReadsAsEntitlementDenied() async throws {
        let body = Data("1770000000000 h\n480000 i".utf8)
        let identity = WriterIdentity.generate()
        let message = "Reflections require an active subscription."

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
            {"error":{"code":"ENTITLEMENT_REQUIRED","message":"\(message)"}}
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
            XCTAssertEqual(error.serverPayload?.code, "ENTITLEMENT_REQUIRED")
            XCTAssertTrue(error.serverPayload?.isEntitlementDenied == true)
            XCTAssertEqual(error.errorDescription, message)
        }
    }
}

private func sseReflection(
    markdown: String,
    hash: String,
    tags: [String] = [],
    inferenceHeaders: [String: String] = [:]
) -> Data {
    var headers = inferenceHeaders
    headers["X-Anky-Hash"] = hash
    let object: [String: Any] = [
        "markdown": markdown,
        "tags": tags,
        "headers": headers
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

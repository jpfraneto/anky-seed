import XCTest
@testable import AnkyCore
@testable import AnkyProtocol

final class MirrorClientTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    func testMirrorClientSendsExactAnkyBodyAndSignatureHeaders() async throws {
        let body = Data("1770000000000 h\n472000 i\n8000".utf8)
        let expectedHash = AnkyHasher.sha256Hex(body)
        let identity = WriterIdentity.generate()

        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "http://127.0.0.1:3000/anky")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "text/plain; charset=utf-8")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Anky-Client"), "ios")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Anky-App-Version"), "1.0(1)")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Anky-Trial-Proof"), "trial-proof")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Anky-Public-Key"), identity.publicKey)
            XCTAssertNotNil(request.value(forHTTPHeaderField: "X-Anky-Signature"))
            XCTAssertNotNil(request.value(forHTTPHeaderField: "X-Anky-Request-Time"))
            XCTAssertEqual(request.ankyTestBodyData(), body)

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            let payload = Data("""
            {"hash":"\(expectedHash)","title":"Small Thread","reflection":"Here is what I saw.","creditsRemaining":null}
            """.utf8)
            return (response, payload)
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = MirrorClient(baseURL: URL(string: "http://127.0.0.1:3000")!, session: session)

        let response = try await client.askAnky(
            bytes: body,
            identity: identity,
            trialProof: "trial-proof",
            appVersion: "1.0(1)"
        )

        XCTAssertEqual(response.hash, expectedHash)
        XCTAssertEqual(response.title, "Small Thread")
    }

    func testDeviceCheckProofProviderDoesNotCrashWhenUnavailable() async {
        let token = await DeviceCheckTrialProofProvider.makeToken()
        if token != nil {
            XCTAssertFalse(token!.isEmpty)
        }
    }
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

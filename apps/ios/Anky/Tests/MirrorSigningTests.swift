import XCTest
@testable import AnkyCore
@testable import AnkyProtocol

final class MirrorSigningTests: XCTestCase {
    func testCanonicalSignatureMessageMatchesServerContract() {
        let message = AnkyPostSigner.canonicalMessage(
            requestTime: "1770000000000",
            bodySha256: "abc123"
        )

        XCTAssertEqual(message, [
            "ANKY_POST_V1",
            "method:POST",
            "path:/anky",
            "request_time:1770000000000",
            "body_sha256:abc123"
        ].joined(separator: "\n"))
    }

    func testExactBodyHashUsesRawAnkyBytes() throws {
        let body = Data("1770000000000 h\n0042 e\n8000".utf8)
        let identity = WriterIdentity.generate()
        let signed = try AnkyPostSigner.sign(
            body: body,
            identity: identity,
            requestTime: "1770000000000"
        )

        XCTAssertEqual(signed.bodySha256, AnkyHasher.sha256Hex(body))
        XCTAssertNotEqual(signed.bodySha256, AnkyHasher.sha256Hex("1770000000000 h\n0042 e\n8000\n"))
    }
}

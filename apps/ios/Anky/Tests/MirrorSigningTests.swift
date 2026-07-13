import XCTest
@testable import AnkyCore
@testable import AnkyProtocol

final class MirrorSigningTests: XCTestCase {
    func testFixtureBodyHashUsesExactRawAnkyBytes() throws {
        let fixture = try AnkyIdentityFixtureLoader.mainnet()
        let body = Data(fixture.body.utf8)
        let bodyHash = "0x" + AnkyHasher.sha256Hex(body)

        XCTAssertEqual(bodyHash, fixture.bodySha256)
        XCTAssertNotEqual(bodyHash, "0x" + AnkyHasher.sha256Hex(Data(fixture.body.dropLast().utf8)))
    }

    func testFixtureEIP712SignatureMatchesContractExactly() throws {
        let fixture = try AnkyIdentityFixtureLoader.mainnet()
        let identity = try WriterIdentity(
            recoveryPhrase: try RecoveryPhrase(text: fixture.mnemonic),
            chainId: fixture.chainId
        )
        let signed = try AnkyPostSigner.sign(
            body: Data(fixture.body.utf8),
            identity: identity,
            requestTime: fixture.requestTime,
            client: fixture.client
        )

        XCTAssertEqual(signed.identityVersion, fixture.identityVersion)
        XCTAssertEqual(signed.accountId, fixture.accountId)
        XCTAssertEqual(signed.signatureType, "eip712")
        XCTAssertEqual(signed.bodySha256, fixture.bodySha256)
        XCTAssertEqual(signed.signature, fixture.signature)

        let digest = try AnkyPostSigner.eip712Digest(
            identity: identity,
            bodySha256: fixture.bodySha256,
            requestTime: fixture.requestTime,
            client: fixture.client
        )
        XCTAssertEqual(
            WriterIdentity.recoverAddress(digest: digest, signature: signed.signature),
            fixture.recoveredAddress
        )
    }
}

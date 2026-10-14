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

    func testAccountKeyCryptoMatchesPublishedVectors() throws {
        XCTAssertEqual(
            AccountKeyCrypto.hexLowercase(AccountKeyCrypto.keccak256(Data())),
            "c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470"
        )
        XCTAssertEqual(
            AccountKeyCrypto.hexLowercase(AccountKeyCrypto.keccak256(Data("abc".utf8))),
            "4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45"
        )

        let identity = try WriterIdentity(recoveryPhrase: try RecoveryPhrase(
            text: "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
        ))
        XCTAssertEqual(identity.address, "0x9858EfFD232B4033E47d90003D41EC34EcaEda94")

        let digest = AccountKeyCrypto.keccak256(Data("anky".utf8))
        let signature = try identity.signDigest(digest)
        XCTAssertEqual(WriterIdentity.recoverAddress(digest: digest, signature: signature), identity.address)
    }
}

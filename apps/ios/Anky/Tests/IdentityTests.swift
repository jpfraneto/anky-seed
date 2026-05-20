import XCTest
@testable import AnkyCore

final class IdentityTests: XCTestCase {
    func testFixtureMnemonicDerivesBaseAddressAndAccountId() throws {
        let fixture = try AnkyIdentityFixtureLoader.mainnet()
        let phrase = try RecoveryPhrase(text: fixture.mnemonic)
        let identity = try WriterIdentity(recoveryPhrase: phrase, chainId: fixture.chainId)

        XCTAssertEqual(identity.address, fixture.address)
        XCTAssertEqual(identity.accountId, fixture.accountId)
        XCTAssertEqual(identity.descriptor.identityVersion, "anky.base.eoa.v1")
        XCTAssertEqual(identity.descriptor.accountKind, "eoa")
        XCTAssertEqual(identity.descriptor.chainId, fixture.chainId)
        XCTAssertEqual(identity.descriptor.signingScheme, "eip712")
        XCTAssertEqual(identity.descriptor.curve, "secp256k1")
        XCTAssertEqual(identity.descriptor.recovery, "bip39-english-12-word")
        XCTAssertEqual(identity.descriptor.derivationPath, fixture.derivationPath)
    }

    func testEIP55ChecksumNormalizesAccountAddress() throws {
        let fixture = try AnkyIdentityFixtureLoader.mainnet()
        let checksumAddress = try WriterIdentity.checksumAddress(fixture.address.lowercased())

        XCTAssertEqual(checksumAddress, fixture.address)
        XCTAssertEqual(checksumAddress, fixture.accountId)
    }

    func testRecoveryPhraseGeneratesTwelveWords() throws {
        let phrase = try RecoveryPhrase.generate()

        XCTAssertEqual(phrase.words.count, 12)
        XCTAssertEqual(phrase.text.split(separator: " ").count, 12)
    }

    func testImportedRecoveryPhraseRestoresSameBaseIdentity() throws {
        let fixture = try AnkyIdentityFixtureLoader.mainnet()
        let store = WriterIdentityStore(keychain: KeychainClient(service: "lat.memetics.anky.tests.\(UUID().uuidString)"))
        let imported = try store.importRecoveryPhrase(fixture.mnemonic)
        let loaded = try store.loadOrCreate()
        let loadedPhrase = try store.loadOrCreateRecoveryPhrase()

        XCTAssertEqual(imported.address, fixture.address)
        XCTAssertEqual(imported.accountId, fixture.accountId)
        XCTAssertEqual(loaded.accountId, fixture.accountId)
        XCTAssertEqual(loadedPhrase.text, fixture.mnemonic)
    }

    func testLegacyRawIdentityMaterialIsNotUsedForNewMirrorIdentity() throws {
        let service = "lat.memetics.anky.tests.\(UUID().uuidString)"
        let keychain = KeychainClient(service: service)
        try keychain.save(Data(repeating: 0x42, count: 32), account: "writer-ed25519-v1")

        let identity = try WriterIdentityStore(keychain: keychain).loadLegacyOrCreateRecoveryIdentity()

        XCTAssertEqual(identity.descriptor.identityVersion, "anky.base.eoa.v1")
        XCTAssertEqual(identity.descriptor.accountKind, "eoa")
        XCTAssertTrue(identity.accountId.hasPrefix("0x"))
    }
}

import XCTest
@testable import AnkyCore

final class IdentityTests: XCTestCase {
    func testGeneratedIdentitySignsAndVerifiesCanonicalMessage() throws {
        let identity = WriterIdentity.generate()
        let message = "ANKY_POST_V1\nmethod:POST\npath:/anky\nrequest_time:1770000000000\nbody_sha256:abc123"
        let signature = try identity.sign(message)

        XCTAssertEqual(Base58.decode(identity.publicKey)?.count, 32)
        XCTAssertEqual(Base58.decode(signature)?.count, 64)
        XCTAssertTrue(identity.verifies(message, signature: signature))
    }

    func testRecoveryPhraseGeneratesTwelveWords() throws {
        let phrase = try RecoveryPhrase.generate()

        XCTAssertEqual(phrase.words.count, 12)
        XCTAssertEqual(phrase.text.split(separator: " ").count, 12)
    }

    func testRecoveryPhraseDerivesStableIdentity() throws {
        let phrase = try RecoveryPhrase(text: "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about")
        let first = try WriterIdentity(recoveryPhrase: phrase)
        let second = try WriterIdentity(recoveryPhrase: phrase)

        XCTAssertEqual(first.publicKey, second.publicKey)
    }

    func testImportedRecoveryPhraseReplacesStoredIdentity() throws {
        let store = WriterIdentityStore(keychain: KeychainClient(service: "lat.memetics.anky.tests.\(UUID().uuidString)"))
        let phrase = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
        let imported = try store.importRecoveryPhrase(phrase)
        let loaded = try store.loadOrCreate()
        let loadedPhrase = try store.loadOrCreateRecoveryPhrase()

        XCTAssertEqual(imported.publicKey, loaded.publicKey)
        XCTAssertEqual(loadedPhrase.text, phrase)
    }
}

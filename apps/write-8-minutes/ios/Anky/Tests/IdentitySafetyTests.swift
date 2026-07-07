import XCTest
@testable import AnkyCore

/// Fix 10 of the 2026-07-06 pre-submission audit: the identity
/// minimum-safe set — BIP39 checksum on import, never overwrite the
/// current wallet in place, consult the iCloud Keychain backup before
/// minting a new wallet on a fresh install.
final class IdentitySafetyTests: XCTestCase {
    private func freshStore() -> (WriterIdentityStore, KeychainClient) {
        let keychain = KeychainClient(service: "lat.memetics.anky.tests.\(UUID().uuidString)")
        return (WriterIdentityStore(keychain: keychain), keychain)
    }

    // MARK: (a) BIP39 checksum

    func testGeneratedPhraseHasValidChecksum() throws {
        for _ in 0..<8 {
            let phrase = try RecoveryPhrase.generate()
            XCTAssertTrue(phrase.hasValidChecksum)
        }
    }

    func testOneWordTypoFailsChecksumOnImport() throws {
        let (store, _) = freshStore()
        var words = try RecoveryPhrase.generate().words
        // A dictionary-valid substitution: swap the first word for a
        // different list word (still 12 valid words, checksum now broken
        // in 15 of 16 cases — retry until it is).
        for candidate in BIP39WordList.english where candidate != words[0] {
            var typo = words
            typo[0] = candidate
            if !(try RecoveryPhrase(words: typo)).hasValidChecksum {
                words = typo
                break
            }
        }
        XCTAssertThrowsError(try store.importRecoveryPhrase(words.joined(separator: " "))) { error in
            XCTAssertEqual(error as? RecoveryPhraseError, .invalidChecksum)
        }
    }

    func testInvalidChecksumImportLeavesCurrentIdentityUntouched() throws {
        let (store, _) = freshStore()
        let original = try store.loadOrCreate()
        var typo = try store.loadOrCreateRecoveryPhrase().words
        for candidate in BIP39WordList.english where candidate != typo[0] {
            var attempt = typo
            attempt[0] = candidate
            if !(try RecoveryPhrase(words: attempt)).hasValidChecksum {
                typo = attempt
                break
            }
        }
        XCTAssertThrowsError(try store.importRecoveryPhrase(typo.joined(separator: " ")))
        XCTAssertEqual(try store.loadOrCreate().accountId, original.accountId)
    }

    func testKnownFixturePhrasePassesChecksum() throws {
        // The canonical BIP39 test vector (entropy 0x00…00).
        let phrase = try RecoveryPhrase(
            text: "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about",
            validatingChecksum: true
        )
        XCTAssertTrue(phrase.hasValidChecksum)
        // The same words with the checksum word wrong must fail.
        XCTAssertThrowsError(try RecoveryPhrase(
            text: "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon",
            validatingChecksum: true
        )) { error in
            XCTAssertEqual(error as? RecoveryPhraseError, .invalidChecksum)
        }
    }

    // MARK: (b) import never destroys the previous wallet

    func testImportSnapshotsThePreviousPhrase() throws {
        let (store, _) = freshStore()
        let originalPhrase = try store.loadOrCreateRecoveryPhrase()
        let incoming = try RecoveryPhrase.generate()

        let imported = try store.importRecoveryPhrase(incoming.text)
        XCTAssertEqual(try store.loadOrCreateRecoveryPhrase().text, incoming.text)
        XCTAssertEqual(try store.loadOrCreate().accountId, imported.accountId)
        XCTAssertEqual(store.previousRecoveryPhraseText(), originalPhrase.text)
    }

    func testReimportingTheCurrentPhraseKeepsNoStaleSnapshot() throws {
        let (store, _) = freshStore()
        let phrase = try store.loadOrCreateRecoveryPhrase()
        try store.importRecoveryPhrase(phrase.text)
        XCTAssertNil(store.previousRecoveryPhraseText())
        XCTAssertEqual(try store.loadOrCreateRecoveryPhrase().text, phrase.text)
    }

    // MARK: (c) fresh install consults the iCloud Keychain backup

    func testFreshInstallAdoptsICloudKeychainBackupInsteadOfMinting() throws {
        let (store, keychain) = freshStore()
        let veteran: WriterIdentity
        do {
            veteran = try store.loadOrCreate()
            try store.backUpRecoveryPhraseToICloudKeychain()
        } catch KeychainError.unhandled(errSecMissingEntitlement) {
            throw XCTSkip("Synchronizable Keychain requires an entitled app host.")
        }

        // Simulate the fresh install: the device-only phrase is gone, the
        // synchronizable backup rode the iCloud Keychain.
        try keychain.delete(account: "writer-base-eoa-recovery-phrase-v1")

        let restored = try store.loadOrCreate()
        XCTAssertEqual(restored.accountId, veteran.accountId, "a stranger wallet must not be minted over an existing backup")
    }

    func testFreshInstallWithoutBackupStillMintsCleanly() throws {
        let (store, _) = freshStore()
        let identity = try store.loadOrCreate()
        XCTAssertFalse(identity.accountId.isEmpty)
        XCTAssertEqual(try store.loadOrCreate().accountId, identity.accountId)
    }
}

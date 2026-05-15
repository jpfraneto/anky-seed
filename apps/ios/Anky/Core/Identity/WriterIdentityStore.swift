import Foundation

struct WriterIdentityStore {
    private let keychain: KeychainClient
    private let rawKeyAccount = "writer-ed25519-v1"
    private let recoveryPhraseAccount = "writer-recovery-phrase-v1"

    init(keychain: KeychainClient = KeychainClient()) {
        self.keychain = keychain
    }

    func loadOrCreate() throws -> WriterIdentity {
        if let phrase = try loadRecoveryPhrase() {
            return try WriterIdentity(recoveryPhrase: phrase)
        }

        let generated = try WriterIdentity.generateRecoveryIdentity()
        try keychain.save(Data(generated.phrase.text.utf8), account: recoveryPhraseAccount)
        try? keychain.delete(account: rawKeyAccount)
        return generated.identity
    }

    func loadOrCreateRecoveryPhrase() throws -> RecoveryPhrase {
        if let phrase = try loadRecoveryPhrase() {
            return phrase
        }

        let generated = try WriterIdentity.generateRecoveryIdentity()
        try keychain.save(Data(generated.phrase.text.utf8), account: recoveryPhraseAccount)
        try? keychain.delete(account: rawKeyAccount)
        return generated.phrase
    }

    @discardableResult
    func importRecoveryPhrase(_ phraseText: String) throws -> WriterIdentity {
        let phrase = try RecoveryPhrase(text: phraseText)
        let identity = try WriterIdentity(recoveryPhrase: phrase)
        try keychain.save(Data(phrase.text.utf8), account: recoveryPhraseAccount)
        try? keychain.delete(account: rawKeyAccount)
        return identity
    }

    private func loadRecoveryPhrase() throws -> RecoveryPhrase? {
        guard let data = try keychain.data(for: recoveryPhraseAccount),
              let phraseText = String(data: data, encoding: .utf8) else {
            return nil
        }
        return try RecoveryPhrase(text: phraseText)
    }

    func hasRecoveryPhrase() -> Bool {
        (try? loadRecoveryPhrase()) != nil
    }

    func migrateLegacyIdentityIfNeeded() throws {
        guard try loadRecoveryPhrase() == nil else {
            return
        }
        let generated = try WriterIdentity.generateRecoveryIdentity()
        try keychain.save(Data(generated.phrase.text.utf8), account: recoveryPhraseAccount)
        try? keychain.delete(account: rawKeyAccount)
    }

    func legacyRawIdentityIfNeeded() throws -> WriterIdentity? {
        guard try loadRecoveryPhrase() == nil,
              let existing = try keychain.data(for: rawKeyAccount) else {
            return nil
        }
        return try WriterIdentity(rawPrivateKey: existing)
    }

    func loadLegacyOrCreateRecoveryIdentity() throws -> WriterIdentity {
        if let phrase = try loadRecoveryPhrase() {
            return try WriterIdentity(recoveryPhrase: phrase)
        }

        if let legacy = try legacyRawIdentityIfNeeded() {
            return legacy
        }

        let generated = try WriterIdentity.generateRecoveryIdentity()
        try keychain.save(Data(generated.phrase.text.utf8), account: recoveryPhraseAccount)
        return generated.identity
    }

    func resetForDevelopment() throws {
        try keychain.delete(account: rawKeyAccount)
        try keychain.delete(account: recoveryPhraseAccount)
    }
}

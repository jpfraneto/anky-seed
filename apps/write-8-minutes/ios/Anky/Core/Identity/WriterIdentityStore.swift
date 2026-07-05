import Foundation

struct WriterIdentityStore {
    private let keychain: KeychainClient
    private let legacyRawKeyAccount = "writer-ed25519-v1"
    private let recoveryPhraseAccount = "writer-base-eoa-recovery-phrase-v1"
    private let iCloudRecoveryPhraseBackupAccount = "writer-base-eoa-recovery-phrase-icloud-backup-v1"

    init(keychain: KeychainClient = KeychainClient()) {
        self.keychain = keychain
    }

    func loadOrCreate() throws -> WriterIdentity {
        if let phrase = try loadRecoveryPhrase() {
            return try WriterIdentity(recoveryPhrase: phrase)
        }

        let generated = try WriterIdentity.generateRecoveryIdentity()
        try keychain.save(Data(generated.phrase.text.utf8), account: recoveryPhraseAccount)
        try? keychain.delete(account: legacyRawKeyAccount)
        return generated.identity
    }

    func loadOrCreateRecoveryPhrase() throws -> RecoveryPhrase {
        if let phrase = try loadRecoveryPhrase() {
            return phrase
        }

        let generated = try WriterIdentity.generateRecoveryIdentity()
        try keychain.save(Data(generated.phrase.text.utf8), account: recoveryPhraseAccount)
        try? keychain.delete(account: legacyRawKeyAccount)
        return generated.phrase
    }

    @discardableResult
    func importRecoveryPhrase(_ phraseText: String) throws -> WriterIdentity {
        let phrase = try RecoveryPhrase(text: phraseText)
        let identity = try WriterIdentity(recoveryPhrase: phrase)
        try keychain.save(Data(phrase.text.utf8), account: recoveryPhraseAccount)
        try? keychain.delete(account: legacyRawKeyAccount)
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

    func hasICloudRecoveryPhraseBackup() -> Bool {
        (try? keychain.data(for: iCloudRecoveryPhraseBackupAccount, synchronizable: true)) != nil
    }

    @discardableResult
    func recoverFromICloudKeychainBackup() throws -> WriterIdentity {
        guard let data = try keychain.data(for: iCloudRecoveryPhraseBackupAccount, synchronizable: true),
              let phraseText = String(data: data, encoding: .utf8) else {
            throw WriterIdentityStoreError.missingICloudBackup
        }
        return try importRecoveryPhrase(phraseText)
    }

    func backUpRecoveryPhraseToICloudKeychain() throws {
        let phrase = try loadOrCreateRecoveryPhrase()
        try keychain.save(
            Data(phrase.text.utf8),
            account: iCloudRecoveryPhraseBackupAccount,
            synchronizable: true
        )
        guard let backedUpData = try keychain.data(for: iCloudRecoveryPhraseBackupAccount, synchronizable: true),
              String(data: backedUpData, encoding: .utf8) == phrase.text else {
            throw WriterIdentityStoreError.iCloudBackupVerificationFailed
        }
    }

    func migrateLegacyIdentityIfNeeded() throws {
        guard try loadRecoveryPhrase() == nil else {
            return
        }
        let generated = try WriterIdentity.generateRecoveryIdentity()
        try keychain.save(Data(generated.phrase.text.utf8), account: recoveryPhraseAccount)
        try? keychain.delete(account: legacyRawKeyAccount)
    }

    func loadLegacyOrCreateRecoveryIdentity() throws -> WriterIdentity {
        if let phrase = try loadRecoveryPhrase() {
            return try WriterIdentity(recoveryPhrase: phrase)
        }

        let generated = try WriterIdentity.generateRecoveryIdentity()
        try keychain.save(Data(generated.phrase.text.utf8), account: recoveryPhraseAccount)
        try? keychain.delete(account: legacyRawKeyAccount)
        return generated.identity
    }

    func resetForDevelopment(includeICloudBackup: Bool = false) throws {
        try keychain.delete(account: legacyRawKeyAccount)
        try keychain.delete(account: recoveryPhraseAccount)
        if includeICloudBackup {
            try keychain.delete(account: iCloudRecoveryPhraseBackupAccount, synchronizable: true)
        }
    }
}

enum WriterIdentityStoreError: Error, Equatable {
    case missingICloudBackup
    case iCloudBackupVerificationFailed
}

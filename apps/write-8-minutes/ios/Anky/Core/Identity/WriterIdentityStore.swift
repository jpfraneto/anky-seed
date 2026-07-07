import Foundation

struct WriterIdentityStore {
    private let keychain: KeychainClient
    private let legacyRawKeyAccount = "writer-ed25519-v1"
    private let recoveryPhraseAccount = "writer-base-eoa-recovery-phrase-v1"
    private let iCloudRecoveryPhraseBackupAccount = "writer-base-eoa-recovery-phrase-icloud-backup-v1"
    /// Import staging: the incoming phrase lands here first, the outgoing
    /// phrase is snapshotted here — the primary account is only ever
    /// switched after both writes verified.
    private let pendingImportAccount = "writer-base-eoa-recovery-phrase-import-pending-v1"
    private let previousRecoveryPhraseAccount = "writer-base-eoa-recovery-phrase-previous-v1"

    init(keychain: KeychainClient = KeychainClient()) {
        self.keychain = keychain
    }

    func loadOrCreate() throws -> WriterIdentity {
        if let phrase = try loadRecoveryPhrase() {
            return try WriterIdentity(recoveryPhrase: phrase)
        }
        return try adoptICloudBackupOrGenerate().identity
    }

    func loadOrCreateRecoveryPhrase() throws -> RecoveryPhrase {
        if let phrase = try loadRecoveryPhrase() {
            return phrase
        }
        return try adoptICloudBackupOrGenerate().phrase
    }

    /// A fresh install whose iCloud Keychain still carries the opt-in
    /// backup is the SAME writer — adopt that phrase instead of minting a
    /// stranger wallet that detaches the subscription and server history.
    private func adoptICloudBackupOrGenerate() throws -> (identity: WriterIdentity, phrase: RecoveryPhrase) {
        if let data = try? keychain.data(for: iCloudRecoveryPhraseBackupAccount, synchronizable: true),
           let phraseText = String(data: data, encoding: .utf8),
           let phrase = try? RecoveryPhrase(text: phraseText),
           let identity = try? WriterIdentity(recoveryPhrase: phrase) {
            try keychain.save(Data(phrase.text.utf8), account: recoveryPhraseAccount)
            try? keychain.delete(account: legacyRawKeyAccount)
            return (identity, phrase)
        }

        let generated = try WriterIdentity.generateRecoveryIdentity()
        try keychain.save(Data(generated.phrase.text.utf8), account: recoveryPhraseAccount)
        try? keychain.delete(account: legacyRawKeyAccount)
        return (generated.identity, generated.phrase)
    }

    @discardableResult
    func importRecoveryPhrase(_ phraseText: String) throws -> WriterIdentity {
        try switchToPhrase(try RecoveryPhrase(text: phraseText, validatingChecksum: true))
    }

    @discardableResult
    private func switchToPhrase(_ phrase: RecoveryPhrase) throws -> WriterIdentity {
        let identity = try WriterIdentity(recoveryPhrase: phrase)
        let incoming = Data(phrase.text.utf8)

        // Stage the incoming phrase and snapshot the current one before the
        // switch — the wallet being replaced must survive any failure here.
        try keychain.save(incoming, account: pendingImportAccount)
        guard try keychain.data(for: pendingImportAccount) == incoming else {
            throw WriterIdentityStoreError.importVerificationFailed
        }
        if let current = try keychain.data(for: recoveryPhraseAccount), current != incoming {
            try keychain.save(current, account: previousRecoveryPhraseAccount)
            guard try keychain.data(for: previousRecoveryPhraseAccount) == current else {
                throw WriterIdentityStoreError.importVerificationFailed
            }
        }
        try keychain.save(incoming, account: recoveryPhraseAccount)
        guard try keychain.data(for: recoveryPhraseAccount) == incoming else {
            throw WriterIdentityStoreError.importVerificationFailed
        }
        try? keychain.delete(account: pendingImportAccount)
        try? keychain.delete(account: legacyRawKeyAccount)
        return identity
    }

    /// The phrase that was active before the most recent import, if any —
    /// the escape hatch from an import that replaced the wrong wallet.
    func previousRecoveryPhraseText() -> String? {
        guard let data = try? keychain.data(for: previousRecoveryPhraseAccount) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
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
        // The backup holds an existing identity, not keyboard input — no
        // checksum strictness, matching the fresh-install adoption path, so
        // a pre-validation import stays recoverable here too.
        return try switchToPhrase(try RecoveryPhrase(text: phraseText))
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
        _ = try adoptICloudBackupOrGenerate()
    }

    func loadLegacyOrCreateRecoveryIdentity() throws -> WriterIdentity {
        if let phrase = try loadRecoveryPhrase() {
            return try WriterIdentity(recoveryPhrase: phrase)
        }
        return try adoptICloudBackupOrGenerate().identity
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
    case importVerificationFailed
}

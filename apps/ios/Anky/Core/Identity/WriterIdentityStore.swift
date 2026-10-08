import Foundation

/// Deriving a `WriterIdentity` from its recovery phrase is deliberately
/// expensive: BIP39 stretches the phrase through 2048 rounds of
/// HMAC-SHA512, then BIP32 walks five levels of HD derivation and a
/// secp256k1 multiply produces the address. Measured at ~410ms in a debug
/// build and ~12ms optimized — per call.
///
/// It is also perfectly deterministic: one phrase always yields one
/// identity. Nothing was memoizing it, so every `loadOrCreate()` in the app
/// paid the full cost, and two of them landed on the launch path before the
/// first frame. This caches the result for the lifetime of the process.
///
/// Keyed by the phrase itself and cleared whenever the stored phrase is
/// replaced (import, iCloud adoption, development reset), so a wallet swap
/// can never be served a stale identity.
///
/// Note this keeps the derived private key resident in memory for the
/// process lifetime rather than re-deriving it per use. The key already
/// lived in memory across every view model that held an identity; this
/// makes that residency explicit and single-instance.
private enum WriterIdentityCache {
    private static let lock = NSLock()
    private static var phraseText: String?
    private static var chainId: UInt64?
    private static var identity: WriterIdentity?

    static func identity(
        for phrase: RecoveryPhrase,
        chainId requestedChainId: UInt64
    ) throws -> WriterIdentity {
        lock.lock()
        if let cached = identity, phraseText == phrase.text, chainId == requestedChainId {
            lock.unlock()
            return cached
        }
        lock.unlock()

        // Derived outside the lock: it is slow, and a redundant derivation
        // under contention is cheaper than serializing every caller behind it.
        let derived = try WriterIdentity(recoveryPhrase: phrase, chainId: requestedChainId)

        lock.lock()
        phraseText = phrase.text
        chainId = requestedChainId
        identity = derived
        lock.unlock()
        return derived
    }

    static func invalidate() {
        lock.lock()
        phraseText = nil
        chainId = nil
        identity = nil
        lock.unlock()
    }
}

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
            return try Self.identity(for: phrase)
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
           let identity = try? Self.identity(for: phrase) {
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
        // The active wallet is being replaced: whatever is memoized now
        // describes the outgoing one.
        WriterIdentityCache.invalidate()
        let identity = try Self.identity(for: phrase)
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
            return try Self.identity(for: phrase)
        }
        return try adoptICloudBackupOrGenerate().identity
    }

    /// Every derivation in this type funnels through here so the expensive
    /// BIP39 + BIP32 walk happens at most once per phrase per process.
    private static func identity(for phrase: RecoveryPhrase) throws -> WriterIdentity {
        try WriterIdentityCache.identity(for: phrase, chainId: WriterIdentity.productionChainId)
    }

    func resetForDevelopment(includeICloudBackup: Bool = false) throws {
        WriterIdentityCache.invalidate()
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

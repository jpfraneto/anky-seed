import Foundation

struct AnkyIdentityDescriptor: Equatable {
    let identityVersion: String
    let accountKind: String
    let chainId: UInt64
    let address: String
    let accountId: String
    let signingScheme: String
    let curve: String
    let recovery: String
    let derivationPath: String
}

struct WriterIdentity {
    static let identityVersion = "anky.base.eoa.v1"
    static let accountKind = "eoa"
    static let productionChainId: UInt64 = 8453
    static let testChainId: UInt64 = 84532
    static let derivationPath = "m/44'/60'/0'/0/0"
    static let signingScheme = "eip712"
    static let curve = "secp256k1"
    static let recovery = "bip39-english-12-word"

    private let privateKey: Data
    let chainId: UInt64
    let address: String

    var accountId: String {
        address
    }

    var descriptor: AnkyIdentityDescriptor {
        AnkyIdentityDescriptor(
            identityVersion: Self.identityVersion,
            accountKind: Self.accountKind,
            chainId: chainId,
            address: address,
            accountId: accountId,
            signingScheme: Self.signingScheme,
            curve: Self.curve,
            recovery: Self.recovery,
            derivationPath: Self.derivationPath
        )
    }

    init(recoveryPhrase: RecoveryPhrase, chainId: UInt64 = Self.productionChainId) throws {
        guard recoveryPhrase.hasValidChecksum,
              let seed = AccountKeyCrypto.seed(fromPhrase: recoveryPhrase.text),
              let privateKey = AccountKeyCrypto.derivePrivateKey(seed: seed, path: Self.derivationPath) else {
            throw WriterIdentityError.couldNotDeriveBaseIdentity
        }

        try self.init(privateKey: privateKey, chainId: chainId)
    }

    private init(privateKey: Data, chainId: UInt64) throws {
        guard let publicKey = AccountKeyCrypto.publicKey(privateKey: privateKey, compressed: false),
              let address = AccountKeyCrypto.accountId(uncompressedPublicKey: publicKey) else {
            throw WriterIdentityError.couldNotDeriveBaseIdentity
        }

        self.privateKey = privateKey
        self.chainId = chainId
        self.address = address
    }

    static func generate() -> WriterIdentity {
        let generated = try! generateRecoveryIdentity()
        return generated.identity
    }

    static func generateRecoveryIdentity(chainId: UInt64 = Self.productionChainId) throws -> (identity: WriterIdentity, phrase: RecoveryPhrase) {
        let phrase = try RecoveryPhrase.generate()
        return (try WriterIdentity(recoveryPhrase: phrase, chainId: chainId), phrase)
    }

    static func checksumAddress(_ address: String) throws -> String {
        guard let checksummed = AccountKeyCrypto.checksummed(address) else {
            throw WriterIdentityError.invalidAddress
        }
        return checksummed
    }

    func signDigest(_ digest: Data) throws -> String {
        guard digest.count == 32 else {
            throw WriterIdentityError.invalidDigest
        }
        guard let signature = AccountKeyCrypto.signRecoverable(digest: digest, privateKey: privateKey) else {
            throw WriterIdentityError.couldNotSign
        }
        return AccountKeyCrypto.prefixedHex(signature)
    }

    static func recoverAddress(digest: Data, signature: String) -> String? {
        guard let signatureData = AccountKeyCrypto.data(fromHex: signature),
              let publicKey = AccountKeyCrypto.recoverPublicKey(digest: digest, signature: signatureData) else {
            return nil
        }
        return AccountKeyCrypto.accountId(uncompressedPublicKey: publicKey)
    }
}

enum WriterIdentityError: Error, Equatable {
    case couldNotDeriveBaseIdentity
    case invalidAddress
    case invalidDigest
    case couldNotSign
}

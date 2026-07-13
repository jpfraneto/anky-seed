import CryptoSwift
import Foundation
import Web3Core
import web3swift

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
        guard let seed = BIP39.seedFromMmemonics(recoveryPhrase.text),
              let rootNode = HDNode(seed: seed),
              let derivedNode = rootNode.derive(path: Self.derivationPath, derivePrivateKey: true),
              let privateKey = derivedNode.privateKey else {
            throw WriterIdentityError.couldNotDeriveBaseIdentity
        }

        try self.init(privateKey: privateKey, chainId: chainId)
    }

    private init(privateKey: Data, chainId: UInt64) throws {
        guard SECP256K1.verifyPrivateKey(privateKey: privateKey),
              let secp256k1PublicKey = SECP256K1.privateToPublic(privateKey: privateKey, compressed: false),
              let ethereumAddress = Utilities.publicToAddress(secp256k1PublicKey) else {
            throw WriterIdentityError.couldNotDeriveBaseIdentity
        }

        self.privateKey = privateKey
        self.chainId = chainId
        self.address = ethereumAddress.address
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
        guard let ethereumAddress = EthereumAddress(address) else {
            throw WriterIdentityError.invalidAddress
        }
        return ethereumAddress.address
    }

    func signDigest(_ digest: Data) throws -> String {
        guard digest.count == 32 else {
            throw WriterIdentityError.invalidDigest
        }
        let signature = SECP256K1.signForRecovery(hash: digest, privateKey: privateKey).serializedSignature
        guard let signature else {
            throw WriterIdentityError.couldNotSign
        }
        return signature.toHexString().addHexPrefix()
    }

    static func recoverAddress(digest: Data, signature: String) -> String? {
        guard let signatureData = Data.fromHex(signature),
              let address = Utilities.hashECRecover(hash: digest, signature: signatureData) else {
            return nil
        }
        return address.address
    }
}

enum WriterIdentityError: Error, Equatable {
    case couldNotDeriveBaseIdentity
    case invalidAddress
    case invalidDigest
    case couldNotSign
}

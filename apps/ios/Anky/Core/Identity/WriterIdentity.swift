import CryptoKit
import Foundation

struct WriterIdentity {
    private let privateKey: Curve25519.Signing.PrivateKey

    var publicKey: String {
        Base58.encode(privateKey.publicKey.rawRepresentation)
    }

    var rawPrivateKey: Data {
        privateKey.rawRepresentation
    }

    init(privateKey: Curve25519.Signing.PrivateKey) {
        self.privateKey = privateKey
    }

    init(rawPrivateKey: Data) throws {
        self.privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: rawPrivateKey)
    }

    init(recoveryPhrase: RecoveryPhrase) throws {
        self.privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: recoveryPhrase.signingSeed())
    }

    static func generate() -> WriterIdentity {
        WriterIdentity(privateKey: Curve25519.Signing.PrivateKey())
    }

    static func generateRecoveryIdentity() throws -> (identity: WriterIdentity, phrase: RecoveryPhrase) {
        let phrase = try RecoveryPhrase.generate()
        return (try WriterIdentity(recoveryPhrase: phrase), phrase)
    }

    func sign(_ message: String) throws -> String {
        let signature = try privateKey.signature(for: Data(message.utf8))
        return Base58.encode(signature)
    }

    func verifies(_ message: String, signature: String) -> Bool {
        guard let signatureData = Base58.decode(signature) else {
            return false
        }
        return privateKey.publicKey.isValidSignature(signatureData, for: Data(message.utf8))
    }
}

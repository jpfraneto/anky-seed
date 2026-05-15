package inc.anky.android.core.identity

import org.bouncycastle.crypto.params.Ed25519PrivateKeyParameters
import org.bouncycastle.crypto.params.Ed25519PublicKeyParameters
import org.bouncycastle.crypto.signers.Ed25519Signer

class WriterIdentity private constructor(
    private val privateKey: Ed25519PrivateKeyParameters,
) {
    val publicKeyBytes: ByteArray = privateKey.generatePublicKey().encoded
    val publicKey: String = Base58.encode(publicKeyBytes)

    fun sign(message: String): String {
        val signer = Ed25519Signer()
        val messageBytes = message.toByteArray(Charsets.UTF_8)
        signer.init(true, privateKey)
        signer.update(messageBytes, 0, messageBytes.size)
        return Base58.encode(signer.generateSignature())
    }

    fun verifies(message: String, signature: String): Boolean {
        val signatureBytes = Base58.decode(signature) ?: return false
        if (signatureBytes.size != 64) return false
        val verifier = Ed25519Signer()
        val messageBytes = message.toByteArray(Charsets.UTF_8)
        verifier.init(false, Ed25519PublicKeyParameters(publicKeyBytes, 0))
        verifier.update(messageBytes, 0, messageBytes.size)
        return verifier.verifySignature(signatureBytes)
    }

    companion object {
        fun fromSeed(seed: ByteArray): WriterIdentity {
            require(seed.size == 32) { "Ed25519 seed must be 32 bytes." }
            return WriterIdentity(Ed25519PrivateKeyParameters(seed, 0))
        }

        fun fromRecoveryPhrase(phrase: RecoveryPhrase): WriterIdentity =
            fromSeed(phrase.signingSeed())

        fun generateRecoveryIdentity(): Pair<WriterIdentity, RecoveryPhrase> {
            val phrase = RecoveryPhrase.generate()
            return fromRecoveryPhrase(phrase) to phrase
        }
    }
}

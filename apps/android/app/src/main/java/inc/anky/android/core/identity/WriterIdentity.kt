package inc.anky.android.core.identity

import org.web3j.crypto.Bip32ECKeyPair
import org.web3j.crypto.Credentials
import org.web3j.crypto.Keys
import org.web3j.crypto.MnemonicUtils
import org.web3j.crypto.Sign

const val AnkyBaseIdentityVersion = "anky.base.eoa.v1"
const val AnkyBaseMainnetChainId = 8453L
const val AnkyBaseSepoliaChainId = 84532L
const val AnkyBaseDerivationPath = "m/44'/60'/0'/0/0"

data class AnkyIdentityDescriptor(
    val identityVersion: String = AnkyBaseIdentityVersion,
    val accountKind: String = "eoa",
    val chainId: Long = AnkyBaseMainnetChainId,
    val accountId: String,
    val address: String,
    val signingScheme: String = "eip712",
    val curve: String = "secp256k1",
    val recovery: String = "bip39-english-12-word",
    val derivationPath: String = AnkyBaseDerivationPath,
)

class WriterIdentity private constructor(
    private val keyPair: Bip32ECKeyPair,
    val chainId: Long = AnkyBaseMainnetChainId,
) {
    private val credentials: Credentials = Credentials.create(keyPair)
    val address: String = Keys.toChecksumAddress(credentials.address)
    val accountId: String = address
    val descriptor: AnkyIdentityDescriptor = AnkyIdentityDescriptor(
        chainId = chainId,
        accountId = accountId,
        address = address,
    )

    fun signDigest(digest32: ByteArray): String {
        require(digest32.size == 32) { "EIP-712 digest must be 32 bytes." }
        val signature = Sign.signMessage(digest32, keyPair, false)
        return "0x" +
            signature.r.hex() +
            signature.s.hex() +
            signature.v.hex()
    }

    companion object {
        const val IdentityVersion = AnkyBaseIdentityVersion
        const val BaseMainnetChainId = AnkyBaseMainnetChainId
        const val BaseSepoliaChainId = AnkyBaseSepoliaChainId
        const val DerivationPath = AnkyBaseDerivationPath

        private val HardenedBit = Bip32ECKeyPair.HARDENED_BIT
        private val BaseDerivationPath = intArrayOf(
            44 or HardenedBit,
            60 or HardenedBit,
            0 or HardenedBit,
            0,
            0,
        )

        fun fromRecoveryPhrase(phrase: RecoveryPhrase, chainId: Long = BaseMainnetChainId): WriterIdentity {
            val seed = MnemonicUtils.generateSeed(phrase.text, "")
            val master = Bip32ECKeyPair.generateKeyPair(seed)
            return WriterIdentity(Bip32ECKeyPair.deriveKeyPair(master, BaseDerivationPath), chainId)
        }

        fun generateRecoveryIdentity(): Pair<WriterIdentity, RecoveryPhrase> {
            val phrase = RecoveryPhrase.generate()
            return fromRecoveryPhrase(phrase) to phrase
        }
    }
}

private fun ByteArray.hex(): String = joinToString(separator = "") { "%02x".format(it) }

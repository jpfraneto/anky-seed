package inc.anky.android.core.identity

import java.security.SecureRandom
import org.web3j.crypto.MnemonicUtils

data class RecoveryPhrase(val words: List<String>) {
    val text: String = words.joinToString(separator = " ")

    init {
        require(words.size == 12) { "Recovery phrase must contain 12 words." }
        require(words.all { BIP39WordList.english.contains(it) }) { "Recovery phrase contains an unsupported word." }
    }

    fun signingSeed(): ByteArray = MnemonicUtils.generateSeed(text, "")

    companion object {
        fun parse(text: String): RecoveryPhrase =
            RecoveryPhrase(text.lowercase().trim().split(Regex("\\s+")).filter { it.isNotEmpty() })

        fun generate(random: SecureRandom = SecureRandom()): RecoveryPhrase {
            val entropy = ByteArray(16)
            random.nextBytes(entropy)
            return parse(MnemonicUtils.generateMnemonic(entropy))
        }
    }
}

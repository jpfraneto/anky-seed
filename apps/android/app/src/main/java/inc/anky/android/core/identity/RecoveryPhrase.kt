package inc.anky.android.core.identity

import java.security.MessageDigest
import java.security.SecureRandom
import org.web3j.crypto.MnemonicUtils

data class RecoveryPhrase(val words: List<String>) {
    val text: String = words.joinToString(separator = " ")

    init {
        require(words.size == 12) { "Recovery phrase must contain 12 words." }
        require(words.all { BIP39WordList.english.contains(it) }) { "Recovery phrase contains an unsupported word." }
    }

    fun signingSeed(): ByteArray = MnemonicUtils.generateSeed(text, "")

    /**
     * BIP39: the final 4 bits of a 12-word phrase are the top 4 bits of
     * SHA256 over its 128 entropy bits. Mirrors iOS RecoveryPhrase.hasValidChecksum
     * (ios/Anky/Core/Identity/RecoveryPhrase.swift).
     */
    val hasValidChecksum: Boolean
        get() {
            if (words.size != 12) return false
            val bits = BooleanArray(132)
            words.forEachIndexed { wordIndex, word ->
                val index = BIP39WordList.english.indexOf(word)
                if (index < 0) return false
                for (bit in 0 until 11) {
                    bits[wordIndex * 11 + bit] = (index shr (10 - bit)) and 1 == 1
                }
            }
            val entropy = ByteArray(16)
            for (position in 0 until 128) {
                if (bits[position]) {
                    entropy[position / 8] = (entropy[position / 8].toInt() or (1 shl (7 - position % 8))).toByte()
                }
            }
            val checksumByte = MessageDigest.getInstance("SHA-256").digest(entropy)[0].toInt() and 0xFF
            for (offset in 0 until 4) {
                val expected = (checksumByte shr (7 - offset)) and 1 == 1
                if (bits[128 + offset] != expected) return false
            }
            return true
        }

    companion object {
        fun parse(text: String): RecoveryPhrase =
            RecoveryPhrase(text.lowercase().trim().split(Regex("\\s+")).filter { it.isNotEmpty() })

        /**
         * For phrases typed by a human (import): a dictionary-valid one-word
         * typo must fail here instead of silently deriving a stranger wallet.
         * Stored phrases keep loading through the non-validating [parse] so a
         * pre-validation import can never brick an existing identity. Mirrors
         * iOS RecoveryPhrase(text:validatingChecksum:).
         */
        fun parse(text: String, validatingChecksum: Boolean): RecoveryPhrase {
            val phrase = parse(text)
            require(!validatingChecksum || phrase.hasValidChecksum) { "Recovery phrase checksum is invalid." }
            return phrase
        }

        fun generate(random: SecureRandom = SecureRandom()): RecoveryPhrase {
            val entropy = ByteArray(16)
            random.nextBytes(entropy)
            return parse(MnemonicUtils.generateMnemonic(entropy))
        }
    }
}

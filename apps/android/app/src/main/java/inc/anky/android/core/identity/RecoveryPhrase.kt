package inc.anky.android.core.identity

import inc.anky.android.core.protocol.AnkyHasher
import java.security.SecureRandom

data class RecoveryPhrase(val words: List<String>) {
    val text: String = words.joinToString(separator = " ")

    init {
        require(words.size == 12) { "Recovery phrase must contain 12 words." }
        require(words.all { BIP39WordList.english.contains(it) }) { "Recovery phrase contains an unsupported word." }
    }

    fun signingSeed(): ByteArray =
        AnkyHasher.sha256Hex("ANKY_RECOVERY_PHRASE_V1\n$text")
            .chunked(2)
            .map { it.toInt(16).toByte() }
            .toByteArray()

    companion object {
        fun parse(text: String): RecoveryPhrase =
            RecoveryPhrase(text.lowercase().trim().split(Regex("\\s+")).filter { it.isNotEmpty() })

        fun generate(random: SecureRandom = SecureRandom()): RecoveryPhrase {
            val words = List(12) { BIP39WordList.english[random.nextInt(BIP39WordList.english.size)] }
            return RecoveryPhrase(words)
        }
    }
}

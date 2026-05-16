package inc.anky.android.core.identity

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.io.File
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class WriterIdentityStore(
    context: Context,
) {
    private val directory = File(context.filesDir, "Anky").also { it.mkdirs() }
    private val encryptedPhraseFile = File(directory, "identity.enc")
    private val ivFile = File(directory, "identity.iv")

    fun loadOrCreate(): WriterIdentity {
        loadRecoveryPhrase()?.let { return WriterIdentity.fromRecoveryPhrase(it) }
        val (identity, phrase) = WriterIdentity.generateRecoveryIdentity()
        saveRecoveryPhrase(phrase)
        return identity
    }

    fun loadOrCreateRecoveryPhrase(): RecoveryPhrase {
        loadRecoveryPhrase()?.let { return it }
        val (_, phrase) = WriterIdentity.generateRecoveryIdentity()
        saveRecoveryPhrase(phrase)
        return phrase
    }

    fun importRecoveryPhrase(text: String): WriterIdentity {
        val phrase = RecoveryPhrase.parse(text)
        saveRecoveryPhrase(phrase)
        return WriterIdentity.fromRecoveryPhrase(phrase)
    }

    fun hasRecoveryPhrase(): Boolean = loadRecoveryPhrase() != null

    fun resetForDevelopment() {
        encryptedPhraseFile.delete()
        ivFile.delete()
        runCatching {
            java.security.KeyStore.getInstance("AndroidKeyStore").apply { load(null) }.deleteEntry(KeyAlias)
        }
    }

    private fun loadRecoveryPhrase(): RecoveryPhrase? {
        if (!encryptedPhraseFile.exists() || !ivFile.exists()) return null
        val cipher = Cipher.getInstance(Transformation)
        cipher.init(Cipher.DECRYPT_MODE, getOrCreateKey(), GCMParameterSpec(128, ivFile.readBytes()))
        val clear = cipher.doFinal(encryptedPhraseFile.readBytes()).toString(Charsets.UTF_8)
        return RecoveryPhrase.parse(clear)
    }

    private fun saveRecoveryPhrase(phrase: RecoveryPhrase) {
        val cipher = Cipher.getInstance(Transformation)
        cipher.init(Cipher.ENCRYPT_MODE, getOrCreateKey())
        encryptedPhraseFile.writeBytes(cipher.doFinal(phrase.text.toByteArray(Charsets.UTF_8)))
        ivFile.writeBytes(cipher.iv)
    }

    private fun getOrCreateKey(): SecretKey {
        val keyStore = java.security.KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (keyStore.getKey(KeyAlias, null) as? SecretKey)?.let { return it }

        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        val spec = KeyGenParameterSpec.Builder(
            KeyAlias,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setRandomizedEncryptionRequired(true)
            .build()
        generator.init(spec)
        return generator.generateKey()
    }

    companion object {
        private const val KeyAlias = "inc.anky.android.writer-identity-v1"
        private const val Transformation = "AES/GCM/NoPadding"
    }
}

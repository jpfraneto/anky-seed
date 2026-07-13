package inc.anky.android.core.storage

import android.content.Context
import inc.anky.android.core.identity.RecoveryPhrase
import inc.anky.android.core.identity.WriterIdentityStore
import java.io.File
import java.security.SecureRandom
import java.time.Instant
import java.time.format.DateTimeParseException
import java.util.Base64
import javax.crypto.Cipher
import javax.crypto.Mac
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec
import org.json.JSONObject

data class AndroidEncryptedBackupStatus(
    val isEnabled: Boolean,
    val lastBackupDate: Instant?,
)

enum class AndroidEncryptedBackupError(val copy: String) {
    NoLocalData("There is no writing to back up yet."),
    MissingBackup("No Anky encrypted backup was found."),
    InvalidEnvelope("The encrypted backup could not be read."),
    EncryptionFailed("The encrypted backup could not be encrypted."),
    DecryptionFailed("The encrypted backup could not be decrypted."),
}

class AndroidEncryptedBackupException(
    val reason: AndroidEncryptedBackupError,
) : IllegalStateException(reason.copy)

class AndroidEncryptedBackupStore(
    private val backupExporter: BackupExporting,
    private val backupImporter: BackupImporter,
    private val recoveryPhraseProvider: () -> RecoveryPhrase,
    private val backupFile: File,
    private val statusFile: File,
    private val now: () -> Instant = { Instant.now() },
    private val randomBytes: (Int) -> ByteArray = { count -> secureRandomBytes(count) },
) {
    constructor(
        context: Context,
        identityStore: WriterIdentityStore,
        backupExporter: BackupExporting,
        backupImporter: BackupImporter,
    ) : this(
        backupExporter = backupExporter,
        backupImporter = backupImporter,
        recoveryPhraseProvider = { identityStore.loadOrCreateRecoveryPhrase() },
        backupFile = File(File(context.filesDir, "Anky"), "Backups/anky-private-backup.v1"),
        statusFile = File(File(context.filesDir, "Anky"), "Backups/encrypted-backup-status.json"),
    )

    fun status(): AndroidEncryptedBackupStatus =
        runCatching {
            val json = JSONObject(statusFile.readText(Charsets.UTF_8))
            AndroidEncryptedBackupStatus(
                isEnabled = json.optBoolean("isEnabled", false),
                lastBackupDate = json.optString("lastBackupDate")
                    .takeIf { it.isNotBlank() }
                    ?.let { Instant.parse(it) },
            )
        }.getOrDefault(AndroidEncryptedBackupStatus(isEnabled = false, lastBackupDate = null))

    fun setEnabled(isEnabled: Boolean) {
        writeStatus(status().copy(isEnabled = isEnabled))
    }

    fun hasRestorableBackup(): Boolean = backupFile.isFile

    fun enableAndBackUpNow() {
        setEnabled(true)
        backUpNow()
    }

    fun backUpIfEnabled() {
        if (status().isEnabled) {
            runCatching { backUpNow() }
        }
    }

    fun backUpNow() {
        val phrase = recoveryPhraseProvider()
        val zip = backupExporter.exportArchiveZip()
            ?: throw AndroidEncryptedBackupException(AndroidEncryptedBackupError.NoLocalData)
        val backupCreatedAt = now()
        val envelope = encrypt(zip.readBytes(), phrase, backupCreatedAt)
        backupFile.parentFile?.mkdirs()
        backupFile.writeText(envelope.toJson().toString(2), Charsets.UTF_8)
        writeStatus(status().copy(lastBackupDate = backupCreatedAt))
    }

    fun deleteBackupAndDisable() {
        backupFile.delete()
        statusFile.delete()
    }

    fun restore(): BackupImportResult {
        if (!backupFile.isFile) {
            throw AndroidEncryptedBackupException(AndroidEncryptedBackupError.MissingBackup)
        }
        val phrase = recoveryPhraseProvider()
        val envelope = readEnvelope()
        val zipBytes = decrypt(envelope, phrase)
        val result = backupImporter.importBackupBytes(zipBytes, "anky-backup.zip")
        val restoredAt = now()
        writeStatus(AndroidEncryptedBackupStatus(isEnabled = true, lastBackupDate = restoredAt))
        return result
    }

    private fun readEnvelope(): AndroidEncryptedBackupEnvelope =
        runCatching {
            AndroidEncryptedBackupEnvelope.fromJson(JSONObject(backupFile.readText(Charsets.UTF_8)))
        }.getOrElse {
            throw AndroidEncryptedBackupException(AndroidEncryptedBackupError.InvalidEnvelope)
        }

    private fun writeStatus(status: AndroidEncryptedBackupStatus) {
        statusFile.parentFile?.mkdirs()
        statusFile.writeText(
            JSONObject()
                .put("isEnabled", status.isEnabled)
                .put("lastBackupDate", status.lastBackupDate?.toString())
                .toString(2),
            Charsets.UTF_8,
        )
    }

    private fun encrypt(data: ByteArray, recoveryPhrase: RecoveryPhrase, createdAt: Instant): AndroidEncryptedBackupEnvelope {
        val salt = randomBytes(16)
        val iv = randomBytes(12)
        val key = hkdfSha256(
            inputKeyMaterial = recoveryPhrase.text.toByteArray(Charsets.UTF_8),
            salt = salt,
            info = EncryptionInfo,
            outputByteCount = 32,
        )
        return runCatching {
            val cipher = Cipher.getInstance(Transformation)
            cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(128, iv))
            AndroidEncryptedBackupEnvelope(
                version = 1,
                algorithm = Algorithm,
                createdAt = createdAt,
                salt = salt,
                payload = iv + cipher.doFinal(data),
            )
        }.getOrElse {
            throw AndroidEncryptedBackupException(AndroidEncryptedBackupError.EncryptionFailed)
        }
    }

    private fun decrypt(envelope: AndroidEncryptedBackupEnvelope, recoveryPhrase: RecoveryPhrase): ByteArray {
        if (envelope.version != 1 || envelope.algorithm != Algorithm || envelope.payload.size <= 12) {
            throw AndroidEncryptedBackupException(AndroidEncryptedBackupError.InvalidEnvelope)
        }
        return runCatching {
            val iv = envelope.payload.copyOfRange(0, 12)
            val encrypted = envelope.payload.copyOfRange(12, envelope.payload.size)
            val key = hkdfSha256(
                inputKeyMaterial = recoveryPhrase.text.toByteArray(Charsets.UTF_8),
                salt = envelope.salt,
                info = EncryptionInfo,
                outputByteCount = 32,
            )
            val cipher = Cipher.getInstance(Transformation)
            cipher.init(Cipher.DECRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(128, iv))
            cipher.doFinal(encrypted)
        }.getOrElse {
            throw AndroidEncryptedBackupException(AndroidEncryptedBackupError.DecryptionFailed)
        }
    }

    private data class AndroidEncryptedBackupEnvelope(
        val version: Int,
        val algorithm: String,
        val createdAt: Instant,
        val salt: ByteArray,
        val payload: ByteArray,
    ) {
        fun toJson(): JSONObject =
            JSONObject()
                .put("version", version)
                .put("algorithm", algorithm)
                .put("createdAt", createdAt.toString())
                .put("salt", Base64.getEncoder().encodeToString(salt))
                .put("payload", Base64.getEncoder().encodeToString(payload))

        companion object {
            fun fromJson(json: JSONObject): AndroidEncryptedBackupEnvelope {
                val createdAt = try {
                    Instant.parse(json.getString("createdAt"))
                } catch (_: DateTimeParseException) {
                    throw AndroidEncryptedBackupException(AndroidEncryptedBackupError.InvalidEnvelope)
                }
                return AndroidEncryptedBackupEnvelope(
                    version = json.getInt("version"),
                    algorithm = json.getString("algorithm"),
                    createdAt = createdAt,
                    salt = Base64.getDecoder().decode(json.getString("salt")),
                    payload = Base64.getDecoder().decode(json.getString("payload")),
                )
            }
        }
    }

    private companion object {
        private const val Algorithm = "AES-GCM-HKDF-SHA256"
        private const val Transformation = "AES/GCM/NoPadding"
        private val EncryptionInfo = "anky.private.icloud.backup.v1".toByteArray(Charsets.UTF_8)

        fun secureRandomBytes(count: Int): ByteArray =
            ByteArray(count).also { SecureRandom().nextBytes(it) }

        fun hkdfSha256(
            inputKeyMaterial: ByteArray,
            salt: ByteArray,
            info: ByteArray,
            outputByteCount: Int,
        ): ByteArray {
            val prk = hmacSha256(salt, inputKeyMaterial)
            val output = ByteArray(outputByteCount)
            var previous = ByteArray(0)
            var generated = 0
            var counter = 1
            while (generated < outputByteCount) {
                val input = previous + info + byteArrayOf(counter.toByte())
                previous = hmacSha256(prk, input)
                val bytesToCopy = minOf(previous.size, outputByteCount - generated)
                previous.copyInto(output, destinationOffset = generated, endIndex = bytesToCopy)
                generated += bytesToCopy
                counter += 1
            }
            return output
        }

        fun hmacSha256(key: ByteArray, data: ByteArray): ByteArray {
            val mac = Mac.getInstance("HmacSHA256")
            mac.init(SecretKeySpec(key, "HmacSHA256"))
            return mac.doFinal(data)
        }
    }
}

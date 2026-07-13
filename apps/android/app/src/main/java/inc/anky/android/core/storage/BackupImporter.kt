package inc.anky.android.core.storage

import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction
import java.time.Instant
import java.util.zip.ZipException
import java.util.zip.ZipInputStream

data class BackupImportResult(
    val ankyCount: Int,
    val reflectionCount: Int,
)

class BackupImporter(
    private val context: Context?,
    private val archive: LocalAnkyArchive,
    private val reflectionStore: ReflectionStore,
    private val indexStore: SessionIndexStore,
    private val recordEarlierFirstOpenDate: ((Instant) -> Unit)? = null,
) {
    fun importBackup(uri: Uri): BackupImportResult {
        val bytes = context?.contentResolver?.openInputStream(uri)?.use { it.readBytes() }
            ?: error("Could not open that backup.")
        return importBackupBytes(bytes, displayName(uri))
    }

    internal fun importBackupBytes(bytes: ByteArray, fileName: String? = null): BackupImportResult {
        val imported = importBackupData(bytes, fileName.extensionOrNull())
        if (imported.result.ankyCount == 0 && imported.result.reflectionCount == 0) {
            error("No .anky files or reflections were found in that import.")
        }
        imported.earliestAnkyDate?.let { recordEarlierFirstOpenDate?.invoke(it) }
        indexStore.rebuild(archive, reflectionStore)
        return imported.result
    }

    private fun importBackupData(bytes: ByteArray, extension: String?): ImportedBackupData =
        when (extension) {
            "zip" -> importZip(bytes)
            "anky" -> {
                val saved = importAnky(bytes)
                ImportedBackupData(
                    result = BackupImportResult(ankyCount = 1, reflectionCount = 0),
                    earliestAnkyDate = saved.createdAt,
                )
            }
            "json" -> {
                if (importReflection(bytes)) {
                    ImportedBackupData(
                        result = BackupImportResult(ankyCount = 0, reflectionCount = 1),
                        earliestAnkyDate = null,
                    )
                } else {
                    error("That backup could not be read.")
                }
            }
            null -> {
                if (looksLikeZip(bytes)) {
                    importZip(bytes)
                } else {
                    importSingleFile(bytes)
                }
            }
            else -> error("Choose a .zip backup, .anky file, or exported reflection JSON.")
        }

    private fun importZip(bytes: ByteArray): ImportedBackupData {
        if (!hasEndOfCentralDirectory(bytes)) error("That zip backup appears to be corrupt.")

        val entryDataByPath = mutableMapOf<String, ByteArray>()
        val entryDateByPath = mutableMapOf<String, Instant>()
        try {
            ZipInputStream(bytes.inputStream()).use { zip ->
                while (true) {
                    val entry = zip.nextEntry ?: break
                    if (!entry.isDirectory && isSafeBackupPath(entry.name)) {
                        entryDataByPath[entry.name] = zip.readCurrentEntry()
                        if (entry.time >= 0) {
                            entryDateByPath[entry.name] = Instant.ofEpochMilli(entry.time)
                        }
                    }
                    zip.closeEntry()
                }
            }
        } catch (error: ZipException) {
            throw zipImportError(error)
        }

        val importedHashByBackupHash = mutableMapOf<String, String>()
        var ankyCount = 0
        var earliestAnkyDate: Instant? = null
        entryDataByPath
            .filterKeys { it.endsWith(".anky", ignoreCase = true) }
            .forEach { (path, entryBytes) ->
                val text = decodeUtf8StrictOrNull(entryBytes) ?: return@forEach
                val saved = archive.save(normalizedImportedAnkyText(text))
                val backupHash = File(path).name.removeSuffix(".anky")
                importedHashByBackupHash[backupHash] = saved.hash
                earliestAnkyDate = minInstant(earliestAnkyDate, saved.createdAt)
                ankyCount += 1
            }

        var reflectionCount = 0
        entryDataByPath
            .filterKeys { it.endsWith(".reflection.md", ignoreCase = true) }
            .forEach { (path, entryBytes) ->
                if (importLegacyReflection(path, entryBytes, entryDataByPath, entryDateByPath, importedHashByBackupHash)) {
                    reflectionCount += 1
                }
            }

        entryDataByPath.values.forEach { entryBytes ->
            if (importReflection(entryBytes)) reflectionCount += 1
        }

        return ImportedBackupData(
            result = BackupImportResult(ankyCount = ankyCount, reflectionCount = reflectionCount),
            earliestAnkyDate = earliestAnkyDate,
        )
    }

    private fun importSingleFile(bytes: ByteArray): ImportedBackupData =
        if (importReflection(bytes)) {
            ImportedBackupData(
                result = BackupImportResult(ankyCount = 0, reflectionCount = 1),
                earliestAnkyDate = null,
            )
        } else {
            val saved = importAnky(bytes)
            ImportedBackupData(
                result = BackupImportResult(ankyCount = 1, reflectionCount = 0),
                earliestAnkyDate = saved.createdAt,
            )
        }

    private fun importAnky(bytes: ByteArray): SavedAnky {
        val text = normalizedImportedAnkyText(decodeUtf8Strict(bytes))
        return archive.save(text)
    }

    private fun importReflection(bytes: ByteArray): Boolean =
        runCatching {
            val json = JSONObject(decodeUtf8Strict(bytes))
            val reflection = LocalReflection(
                hash = json.getString("hash"),
                title = json.getString("title"),
                reflection = json.getString("reflection"),
                createdAt = Instant.parse(json.getString("createdAt")),
                creditsRemaining = if (json.isNull("creditsRemaining")) null else json.getInt("creditsRemaining"),
                tags = json.optJSONArray("tags").stringList(),
            )
            reflectionStore.save(reflection)
        }.isSuccess

    private fun importLegacyReflection(
        path: String,
        bytes: ByteArray,
        entryDataByPath: Map<String, ByteArray>,
        entryDateByPath: Map<String, Instant>,
        importedHashByBackupHash: Map<String, String>,
    ): Boolean {
        val filename = File(path).name
        val backupHash = filename.removeSuffix(".reflection.md")
        if (!backupHash.matches(Sha256Hex)) return false
        val localHash = importedHashByBackupHash[backupHash] ?: backupHash
        if (!archiveContains(localHash)) return false

        val prefix = pathPrefix(path)
        val title = entryDataByPath["$prefix$backupHash.title.txt"]
            ?.let(::decodeUtf8StrictOrNull)
            ?.trim()
            ?.takeIf { it.isNotEmpty() }
            ?: "Imported reflection"
        val processing = entryDataByPath["$prefix$backupHash.processing.json"]
            ?.let(::decodeUtf8StrictOrNull)
            ?.let { runCatching { JSONObject(it) }.getOrNull() }
        val createdAt = processing?.optString("created_at")
            ?.takeIf { it.isNotBlank() }
            ?.let { runCatching { Instant.parse(it) }.getOrNull() }
            ?: entryDateByPath[path]
            ?: Instant.now()
        val creditsRemaining = processing
            ?.takeUnless { it.isNull("credits_remaining") }
            ?.optInt("credits_remaining")

        reflectionStore.save(
            LocalReflection(
                hash = localHash,
                title = title,
                reflection = decodeUtf8StrictOrNull(bytes) ?: return false,
                createdAt = createdAt,
                creditsRemaining = creditsRemaining,
                tags = emptyList(),
            ),
        )
        return true
    }

    private fun archiveContains(hash: String): Boolean =
        runCatching { archive.load(hash) }.isSuccess

    private fun looksLikeZip(bytes: ByteArray): Boolean =
        bytes.hasZipSignature(0x03) || bytes.hasZipSignature(0x05)

    private fun ByteArray.hasZipSignature(thirdByte: Int): Boolean =
        size >= 4 &&
            this[0] == 0x50.toByte() &&
            this[1] == 0x4B.toByte() &&
            this[2] == thirdByte.toByte() &&
            this[3] == if (thirdByte == 0x05) 0x06.toByte() else 0x04.toByte()

    private fun hasEndOfCentralDirectory(bytes: ByteArray): Boolean {
        val minimumSize = 22
        if (bytes.size < minimumSize) return false
        val lowerBound = maxOf(0, bytes.size - 65_557)
        var offset = bytes.size - minimumSize
        while (offset >= lowerBound) {
            if (bytes[offset] == 0x50.toByte() &&
                bytes[offset + 1] == 0x4B.toByte() &&
                bytes[offset + 2] == 0x05.toByte() &&
                bytes[offset + 3] == 0x06.toByte()
            ) {
                return true
            }
            offset -= 1
        }
        return false
    }

    private fun zipImportError(error: ZipException): IllegalStateException {
        val message = error.message.orEmpty().lowercase()
        val copy = when {
            "encrypt" in message -> "Encrypted zip backups are not supported."
            "compression" in message || "method" in message -> "That zip backup uses unsupported compression."
            else -> "That zip backup appears to be corrupt."
        }
        return IllegalStateException(copy, error)
    }

    private fun isSafeBackupPath(path: String): Boolean {
        return path.isNotEmpty() &&
            !path.startsWith("/") &&
            !path.contains("..") &&
            !path.contains("\\")
    }

    private fun pathPrefix(path: String): String {
        val slash = path.lastIndexOf('/')
        return if (slash < 0) "" else path.substring(0, slash + 1)
    }

    private fun minInstant(left: Instant?, right: Instant): Instant =
        if (left == null || right.isBefore(left)) right else left

    private fun normalizedImportedAnkyText(text: String): String =
        text
            .replace("\r\n", "\n")
            .split("\n")
            .dropLastWhile { it.isEmpty() }
            .joinToString(separator = "\n") { line ->
                val separator = line.indexOf(' ')
                if (separator < 0) return@joinToString line
                val timeText = line.substring(0, separator)
                val characterText = line.substring(separator + 1)
                if (characterText == "SPACE" || characterText == " ") "$timeText SPACE" else line
            }

    private fun decodeUtf8Strict(bytes: ByteArray): String =
        decodeUtf8StrictOrNull(bytes) ?: error("That backup could not be read.")

    private fun decodeUtf8StrictOrNull(bytes: ByteArray): String? =
        runCatching {
            Charsets.UTF_8
                .newDecoder()
                .onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT)
                .decode(ByteBuffer.wrap(bytes))
                .toString()
        }.getOrNull()

    private fun displayName(uri: Uri): String? {
        val resolver = context?.contentResolver ?: return null
        resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
            val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            if (index >= 0 && cursor.moveToFirst()) {
                return cursor.getString(index)
            }
        }
        return uri.lastPathSegment
    }

    private fun String?.extensionOrNull(): String? {
        val name = this?.substringAfterLast('/', this)?.substringAfterLast('\\', this)?.trim().orEmpty()
        if (name.isEmpty()) return null
        val extension = name.substringAfterLast('.', missingDelimiterValue = "")
            .lowercase()
        return extension.ifBlank { null }
    }

    private companion object {
        val Sha256Hex = Regex("^[0-9a-f]{64}$")
    }
}

private fun org.json.JSONArray?.stringList(): List<String> {
    if (this == null) return emptyList()
    return (0 until length()).mapNotNull { index ->
        optString(index).trim().takeIf { it.isNotEmpty() }
    }
}

private data class ImportedBackupData(
    val result: BackupImportResult,
    val earliestAnkyDate: Instant?,
)

private fun ZipInputStream.readCurrentEntry(): ByteArray {
    val output = ByteArrayOutputStream()
    val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
    while (true) {
        val read = read(buffer)
        if (read <= 0) break
        output.write(buffer, 0, read)
    }
    return output.toByteArray()
}

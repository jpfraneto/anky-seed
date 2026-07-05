package inc.anky.android.core.storage

import android.content.Context
import inc.anky.android.core.protocol.AnkyDuration
import inc.anky.android.core.protocol.AnkyHasher
import inc.anky.android.core.protocol.AnkyParser
import inc.anky.android.core.protocol.AnkyReconstructor
import java.io.File
import java.time.Instant

class LocalAnkyArchive private constructor(
    private val directory: File,
) {
    constructor(context: Context) : this(File(context.filesDir, "Ankys"))

    init {
        directory.mkdirs()
    }

    fun save(ankyText: String): SavedAnky {
        val bytes = ankyText.toByteArray(Charsets.UTF_8)
        val hash = AnkyHasher.sha256Hex(bytes)
        val target = hashFile(hash)
        val artifact = artifactFrom(ankyText, target)
        target.writeBytes(bytes)
        return artifact
    }

    fun load(hash: String): SavedAnky {
        require(hash.matches(Sha256Hex)) { "Invalid .anky hash." }
        val directFile = hashFile(hash)
        if (directFile.exists()) return load(directFile)

        if (canonicalFile().exists()) {
            val canonical = load(canonicalFile())
            if (canonical.hash == hash) return canonical
        }

        return list().firstOrNull { it.hash == hash }
            ?: throw IllegalArgumentException("No local .anky exists for that hash.")
    }

    fun load(file: File): SavedAnky =
        artifactFrom(file.readText(Charsets.UTF_8), file)

    fun list(): List<SavedAnky> {
        val seen = mutableSetOf<String>()
        return directory.listFiles { file -> file.extension == "anky" }
            ?.mapNotNull { runCatching { load(it) }.getOrNull() }
            ?.filter { seen.add(it.hash) }
            ?.sortedByDescending { it.createdAt }
            ?: emptyList()
    }

    fun fileList(): List<File> =
        list().map { it.file }

    fun delete(hash: String) {
        require(hash.matches(Sha256Hex)) { "Invalid .anky hash." }
        val files = listOf(hashFile(hash), canonicalFile()).distinct()
        val deleted = files
            .filter { file -> file.exists() && runCatching { load(file).hash == hash }.getOrDefault(false) }
            .map { file -> file.delete() }
        if (deleted.any { !it }) {
            throw IllegalStateException("Could not delete .anky file.")
        }
    }

    fun clear() {
        directory.listFiles { file -> file.extension == "anky" }
            ?.forEach { it.delete() }
    }

    private fun canonicalFile(): File = File(directory, CanonicalFileName)

    private fun hashFile(hash: String): File = File(directory, "$hash.anky")

    private fun artifactFrom(ankyText: String, file: File): SavedAnky {
        val parsed = AnkyParser.parse(ankyText)
        return SavedAnky(
            file = file,
            hash = AnkyHasher.sha256Hex(ankyText.toByteArray(Charsets.UTF_8)),
            text = ankyText,
            reconstructedText = AnkyReconstructor.reconstructText(parsed),
            durationMs = AnkyDuration.durationMs(parsed),
            isComplete = AnkyDuration.isComplete(parsed),
            createdAt = Instant.ofEpochMilli(parsed.startEpochMs),
        )
    }

    companion object {
        const val CanonicalFileName = "dotAnky.anky"
        private val Sha256Hex = Regex("^[0-9a-f]{64}$")

        fun forDirectory(directory: File): LocalAnkyArchive = LocalAnkyArchive(directory)
    }
}

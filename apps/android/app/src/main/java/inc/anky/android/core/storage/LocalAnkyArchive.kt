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
        val artifact = artifactFrom(ankyText, canonicalFile())
        val bytes = ankyText.toByteArray(Charsets.UTF_8)
        canonicalFile().writeBytes(bytes)
        return artifact
    }

    fun load(hash: String): SavedAnky {
        require(hash.matches(Sha256Hex)) { "Invalid .anky hash." }
        val artifact = load(canonicalFile())
        if (artifact.hash != hash) throw IllegalArgumentException("No local .anky exists for that hash.")
        return artifact
    }

    fun load(file: File): SavedAnky =
        artifactFrom(file.readText(Charsets.UTF_8), file)

    fun list(): List<SavedAnky> =
        if (canonicalFile().exists()) {
            listOfNotNull(runCatching { load(canonicalFile()) }.getOrNull())
        } else {
            emptyList()
        }

    fun fileList(): List<File> =
        if (canonicalFile().exists()) listOf(canonicalFile()) else emptyList()

    fun delete(hash: String) {
        require(hash.matches(Sha256Hex)) { "Invalid .anky hash." }
        val file = canonicalFile()
        val shouldDelete = file.exists() && runCatching { load(file).hash == hash }.getOrDefault(false)
        if (shouldDelete && !file.delete()) {
            throw IllegalStateException("Could not delete .anky file.")
        }
    }

    fun clear() {
        directory.listFiles { file -> file.extension == "anky" }
            ?.forEach { it.delete() }
    }

    private fun canonicalFile(): File = File(directory, CanonicalFileName)

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

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
        val file = File(directory, "$hash.anky")
        val artifact = artifactFrom(ankyText, file)
        file.writeBytes(bytes)
        return artifact
    }

    fun load(hash: String): SavedAnky {
        require(hash.matches(Sha256Hex)) { "Invalid .anky hash." }
        return load(File(directory, "$hash.anky"))
    }

    fun load(file: File): SavedAnky =
        artifactFrom(file.readText(Charsets.UTF_8), file)

    fun list(): List<SavedAnky> =
        directory.listFiles { file -> file.extension == "anky" }
            ?.mapNotNull { runCatching { load(it) }.getOrNull() }
            ?.sortedByDescending { it.createdAt }
            ?: emptyList()

    fun fileList(): List<File> =
        directory.listFiles { file -> file.extension == "anky" }
            ?.sortedBy { it.name }
            ?: emptyList()

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
        private val Sha256Hex = Regex("^[0-9a-f]{64}$")

        fun forDirectory(directory: File): LocalAnkyArchive = LocalAnkyArchive(directory)
    }
}

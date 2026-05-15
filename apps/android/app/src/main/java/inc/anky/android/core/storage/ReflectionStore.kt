package inc.anky.android.core.storage

import android.content.Context
import org.json.JSONObject
import java.io.File
import java.time.Instant

class ReflectionStore private constructor(
    private val directory: File,
) {
    constructor(context: Context) : this(File(File(context.filesDir, "Anky"), "reflections"))

    init {
        directory.mkdirs()
    }

    fun save(reflection: LocalReflection) {
        urlFor(reflection.hash).writeText(reflection.toJson().toString(2), Charsets.UTF_8)
    }

    fun load(hash: String): LocalReflection? {
        val file = urlFor(hash)
        if (!file.exists()) return null
        return runCatching { JSONObject(file.readText(Charsets.UTF_8)).toLocalReflection() }.getOrNull()
    }

    fun list(): List<LocalReflection> =
        directory.listFiles { file -> file.extension == "json" }
            ?.mapNotNull { runCatching { JSONObject(it.readText(Charsets.UTF_8)).toLocalReflection() }.getOrNull() }
            ?.sortedByDescending { it.createdAt }
            ?: emptyList()

    private fun urlFor(hash: String): File = File(directory, "$hash.json")

    companion object {
        fun forDirectory(directory: File): ReflectionStore = ReflectionStore(directory)
    }
}

private fun LocalReflection.toJson(): JSONObject =
    JSONObject()
        .put("hash", hash)
        .put("title", title)
        .put("reflection", reflection)
        .put("createdAt", createdAt.toString())
        .put("creditsRemaining", creditsRemaining)

private fun JSONObject.toLocalReflection(): LocalReflection =
    LocalReflection(
        hash = getString("hash"),
        title = getString("title"),
        reflection = getString("reflection"),
        createdAt = Instant.parse(getString("createdAt")),
        creditsRemaining = if (isNull("creditsRemaining")) null else getInt("creditsRemaining"),
    )

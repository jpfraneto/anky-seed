package inc.anky.android.core.storage

import android.content.Context
import inc.anky.android.core.protocol.AnkyParser
import java.io.File

class ActiveDraftStore private constructor(
    private val file: File,
    private val legacyFile: File? = null,
) {
    constructor(context: Context) : this(
        file = File(File(context.filesDir, "ActiveDrafts"), LocalAnkyArchive.CanonicalFileName),
        legacyFile = File(File(context.filesDir, "Ankys"), LocalAnkyArchive.CanonicalFileName),
    )

    init {
        file.parentFile?.mkdirs()
    }

    fun load(): String? {
        if (file.exists()) return file.readText(Charsets.UTF_8)

        val legacyDraft = legacyFile
            ?.takeIf { it.exists() }
            ?.readText(Charsets.UTF_8)
            ?: return null
        return legacyDraft.takeIf(::isOpenDraft)
    }

    fun save(text: String) {
        file.writeText(text, Charsets.UTF_8)
    }

    fun clear() {
        if (file.exists()) file.delete()
        legacyFile
            ?.takeIf { it.exists() }
            ?.takeIf { runCatching { isOpenDraft(it.readText(Charsets.UTF_8)) }.getOrDefault(false) }
            ?.delete()
    }

    companion object {
        fun forDirectory(directory: File): ActiveDraftStore =
            ActiveDraftStore(File(directory, LocalAnkyArchive.CanonicalFileName))

        fun forDirectories(directory: File, legacyDirectory: File): ActiveDraftStore =
            ActiveDraftStore(
                file = File(directory, LocalAnkyArchive.CanonicalFileName),
                legacyFile = File(legacyDirectory, LocalAnkyArchive.CanonicalFileName),
            )
    }
}

private fun isOpenDraft(text: String): Boolean =
    runCatching { AnkyParser.parse(text).terminalSilenceMs == null }.getOrDefault(false)

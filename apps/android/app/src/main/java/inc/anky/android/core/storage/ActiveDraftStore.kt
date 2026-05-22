package inc.anky.android.core.storage

import android.content.Context
import java.io.File

class ActiveDraftStore private constructor(
    private val file: File,
) {
    constructor(context: Context) : this(File(File(context.filesDir, "Ankys"), LocalAnkyArchive.CanonicalFileName))

    init {
        file.parentFile?.mkdirs()
    }

    fun load(): String? =
        if (file.exists()) file.readText(Charsets.UTF_8) else null

    fun save(text: String) {
        file.writeText(text, Charsets.UTF_8)
    }

    fun clear() {
        if (file.exists()) file.delete()
    }

    companion object {
        fun forDirectory(directory: File): ActiveDraftStore =
            ActiveDraftStore(File(directory, LocalAnkyArchive.CanonicalFileName))
    }
}

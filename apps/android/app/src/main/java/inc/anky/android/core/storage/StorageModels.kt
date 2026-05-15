package inc.anky.android.core.storage

import java.io.File
import java.time.Instant

data class SavedAnky(
    val file: File,
    val hash: String,
    val text: String,
    val reconstructedText: String,
    val durationMs: Long,
    val isComplete: Boolean,
    val createdAt: Instant,
)

data class LocalReflection(
    val hash: String,
    val title: String,
    val reflection: String,
    val createdAt: Instant,
    val creditsRemaining: Int?,
)

data class SessionSummary(
    val hash: String,
    val createdAt: Instant,
    val localFilePath: String,
    val durationMs: Long,
    val isComplete: Boolean,
    val preview: String,
    val wordCount: Int,
    val hasReflection: Boolean,
    val reflectionTitle: String?,
) {
    val title: String
        get() = reflectionTitle ?: if (isComplete) "Anky" else "Fragment"

    companion object {
        fun make(artifact: SavedAnky, reflection: LocalReflection?): SessionSummary =
            SessionSummary(
                hash = artifact.hash,
                createdAt = artifact.createdAt,
                localFilePath = artifact.file.absolutePath,
                durationMs = artifact.durationMs,
                isComplete = artifact.isComplete,
                preview = preview(artifact.reconstructedText),
                wordCount = wordCount(artifact.reconstructedText),
                hasReflection = reflection != null,
                reflectionTitle = reflection?.title,
            )

        fun preview(text: String): String {
            val trimmed = text.trim()
            if (trimmed.isEmpty()) return "No readable text"
            return if (trimmed.length > 96) trimmed.take(96) + "..." else trimmed
        }

        fun wordCount(text: String): Int =
            text.split(Regex("\\s+")).filter { it.isNotBlank() }.size
    }
}

data class SessionDay(
    val dayEpochMs: Long,
    val sessions: List<SessionSummary>,
    val completeCount: Int,
    val fragmentCount: Int,
    val reflectionCount: Int,
)

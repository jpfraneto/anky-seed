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
    val inputStats: WritingInputStats = WritingInputStats.Empty,
)

/**
 * Per-session input counters stored as a `<hash>.input-stats.json` sidecar
 * beside the sealed .anky file. Mirrors iOS WritingInputStats
 * (ios/Anky/Core/Storage/LocalAnkyArchive.swift); a missing sidecar means
 * zero counts.
 */
data class WritingInputStats(
    val backspaceCount: Int = 0,
    val enterCount: Int = 0,
) {
    companion object {
        val Empty = WritingInputStats(backspaceCount = 0, enterCount = 0)
    }
}

data class LocalReflection(
    val hash: String,
    val title: String,
    val reflection: String,
    val createdAt: Instant,
    val creditsRemaining: Int?,
    val tags: List<String> = emptyList(),
)

data class SessionSummary(
    val hash: String,
    val createdAt: Instant,
    val localFilePath: String,
    val durationMs: Long,
    val isComplete: Boolean,
    val preview: String,
    val wordCount: Int,
    val backspaceCount: Int = 0,
    val enterCount: Int = 0,
    val hasReflection: Boolean,
    val reflectionTitle: String?,
    val tags: List<String> = emptyList(),
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
                backspaceCount = artifact.inputStats.backspaceCount,
                enterCount = artifact.inputStats.enterCount,
                hasReflection = reflection != null,
                reflectionTitle = reflection?.title,
                tags = reflection?.tags.orEmpty(),
            )

        fun preview(text: String): String {
            val trimmed = text.trim()
            if (trimmed.isEmpty()) return "No readable text"
            val prefix = trimmed.swiftCharacterPrefix(96)
            return if (prefix.isTruncated) prefix.text + "..." else trimmed
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
    val dayIndex: Int,
    val dayInRegion: Int,
    val cycleDay: Int = 1,
    val region: Int = 1,
) {
    val hasAnky: Boolean
        get() = completeCount > 0

    val showsTrailCompletionMarker: Boolean
        get() = completeCount > 0

    val trailActivitySummary: String
        get() = when {
            sessions.isEmpty() -> "No writing"
            showsTrailCompletionMarker -> "Showed up"
            else -> "No complete anky"
        }
}

private data class SwiftCharacterPrefix(
    val text: String,
    val isTruncated: Boolean,
)

private fun String.swiftCharacterPrefix(limit: Int): SwiftCharacterPrefix {
    var characterCount = 0
    var index = 0
    while (index < length && characterCount < limit) {
        index = nextSwiftCharacterEnd(index)
        characterCount += 1
    }
    return SwiftCharacterPrefix(text = substring(0, index), isTruncated = index < length)
}

private fun String.nextSwiftCharacterEnd(start: Int): Int {
    var index = start
    val first = codePointAt(index)
    index += Character.charCount(first)

    if (first in RegionalIndicators && index < length) {
        val second = codePointAt(index)
        if (second in RegionalIndicators) {
            index += Character.charCount(second)
        }
    }

    index = consumeAttachedMarks(index)
    while (index < length && codePointAt(index) == ZeroWidthJoiner) {
        index += Character.charCount(ZeroWidthJoiner)
        if (index < length) {
            index += Character.charCount(codePointAt(index))
            index = consumeAttachedMarks(index)
        }
    }
    return index
}

private fun String.consumeAttachedMarks(start: Int): Int {
    var index = start
    while (index < length) {
        val codePoint = codePointAt(index)
        if (!codePoint.isAttachedMark()) break
        index += Character.charCount(codePoint)
    }
    return index
}

private fun Int.isAttachedMark(): Boolean {
    val type = Character.getType(this)
    return type == Character.NON_SPACING_MARK.toInt() ||
        type == Character.COMBINING_SPACING_MARK.toInt() ||
        type == Character.ENCLOSING_MARK.toInt() ||
        this in VariationSelectors ||
        this in EmojiModifiers
}

private const val ZeroWidthJoiner = 0x200D
private val RegionalIndicators = 0x1F1E6..0x1F1FF
private val VariationSelectors = 0xFE00..0xFE0F
private val EmojiModifiers = 0x1F3FB..0x1F3FF

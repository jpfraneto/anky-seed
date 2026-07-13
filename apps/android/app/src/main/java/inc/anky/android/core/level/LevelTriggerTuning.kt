package inc.anky.android.core.level

import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.ChronoUnit

/**
 * Minimal chapter-artifact input for distillation and loading excerpts.
 * Decouples the level machinery from the storage layer (LocalAnkyArchive
 * adapts into this at the wiring site).
 */
data class LevelChapterArtifact(
    val createdAtMs: Long,
    val reconstructedText: String,
)

/**
 * Pre-generation trigger tuning — every constant of "when does anky start
 * painting the next level" lives here.
 */
object LevelTriggerTuning {
    /** Trailing window for the writer's daily-output distribution. */
    const val DailyOutputWindowDays = 28

    /**
     * Trigger when seconds remaining in the level drop below this percentile
     * of daily output — days of runway for normal writers, hours for heavy.
     */
    const val DailyOutputPercentile = 0.95

    /**
     * With fewer than this many writing days of history, fall back to
     * triggering at [FallbackProgressFraction] of the level.
     */
    const val MinimumHistoryDays = 7
    const val FallbackProgressFraction = 0.9

    /** Distillation payload cap (characters). The server backstops this too. */
    const val MaxDistillCharacters = 60_000

    /** Should the next painting start generating now? */
    fun shouldPrepareNextPainting(
        progress: AnkyLevel.Progress,
        dailySecondsHistory: List<Long>,
    ): Boolean {
        val secondsRemaining = progress.secondsRequired - progress.secondsIntoLevel
        val writingDays = dailySecondsHistory.filter { it > 0 }
        if (writingDays.size >= MinimumHistoryDays) {
            val sorted = writingDays.sorted()
            val rank = Math.round((sorted.size - 1).toDouble() * DailyOutputPercentile).toInt()
            val p95Daily = sorted[maxOf(0, minOf(sorted.size - 1, rank))]
            return secondsRemaining < p95Daily
        }
        return progress.percent >= FallbackProgressFraction
    }

    /**
     * Seconds written per day over the trailing window, derived from the
     * session index (most recent day last; zero-days included).
     */
    fun dailySecondsHistory(
        summaries: List<LevelSessionStat>,
        nowMs: Long = System.currentTimeMillis(),
        zone: ZoneId = ZoneId.systemDefault(),
    ): List<Long> {
        val today = Instant.ofEpochMilli(nowMs).atZone(zone).toLocalDate()
        val secondsPerDay = mutableMapOf<LocalDate, Long>()
        for (summary in summaries) {
            val day = Instant.ofEpochMilli(summary.createdAtMs).atZone(zone).toLocalDate()
            secondsPerDay[day] = (secondsPerDay[day] ?: 0L) + summary.durationMs / 1000
        }
        return (0 until DailyOutputWindowDays)
            .map { offset -> secondsPerDay[today.minusDays(offset.toLong())] ?: 0L }
            .reversed()
    }

    /**
     * The distillation corpus: reconstructed text of every session sealed
     * since the last level-up, most recent kept when the cap bites. The
     * text leaves the device once, transiently, for the distillation call —
     * never for anything else.
     */
    fun distillText(
        artifacts: List<LevelChapterArtifact>,
        sinceMs: Long?,
    ): String {
        val chapter = artifacts
            .filter { artifact -> sinceMs == null || artifact.createdAtMs > sinceMs }
            .sortedByDescending { it.createdAtMs } // most recent first

        val pieces = mutableListOf<String>()
        var totalCharacters = 0
        for (artifact in chapter) {
            val text = artifact.reconstructedText.trim()
            if (text.isEmpty()) continue
            val remaining = MaxDistillCharacters - totalCharacters
            if (remaining <= 200) break
            val clipped = if (text.length > remaining) text.take(remaining) else text
            pieces.add(clipped)
            totalCharacters += clipped.length + 8
        }
        // Chronological order reads as the chapter it was.
        return pieces.reversed().joinToString("\n\n---\n\n")
    }

    fun loadingExcerpts(
        artifacts: List<LevelChapterArtifact>,
        sinceMs: Long?,
        limit: Int = 4,
    ): List<String> {
        val chapter = artifacts
            .filter { artifact -> sinceMs == null || artifact.createdAtMs > sinceMs }
            .sortedBy { it.createdAtMs }

        val candidates = chapter.mapNotNull { excerpt(it.reconstructedText) }
        if (candidates.size <= limit || limit <= 0) {
            return candidates.take(maxOf(0, limit))
        }

        return (0 until limit).map { index ->
            val position = index.toDouble() / maxOf(1, limit - 1).toDouble()
            val candidateIndex = Math.round(position * (candidates.size - 1).toDouble()).toInt()
            candidates[minOf(candidates.size - 1, maxOf(0, candidateIndex))]
        }
    }

    private fun excerpt(text: String, maxCharacters: Int = 180): String? {
        val normalized = text
            .split(Regex("\\s+"))
            .filter { it.isNotEmpty() }
            .joinToString(" ")
            .trim()
        if (normalized.length < 24) return null
        if (normalized.length <= maxCharacters) return normalized

        var excerpt = ""
        for (word in normalized.split(" ")) {
            val next = if (excerpt.isEmpty()) word else "$excerpt $word"
            if (next.length > maxCharacters) break
            excerpt = next
        }
        return if (excerpt.isEmpty()) normalized.take(maxCharacters) else "$excerpt..."
    }
}

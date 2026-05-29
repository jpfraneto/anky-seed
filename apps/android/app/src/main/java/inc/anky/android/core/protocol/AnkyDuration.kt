package inc.anky.android.core.protocol

import java.time.Instant
import java.time.ZoneOffset

object AnkyDuration {
    const val CompleteRitualMinutes: Int = 8
    const val CompleteRitualMs: Long = CompleteRitualMinutes * 60 * 1000L
    const val TerminalSilenceMs: Long = 8000

    fun durationMs(parsed: ParsedAnky): Long =
        parsed.events.sumOf { it.deltaMs } + (parsed.terminalSilenceMs ?: 0)

    fun isComplete(parsed: ParsedAnky): Boolean =
        durationMs(parsed) >= CompleteRitualMs && parsed.terminalSilenceMs == TerminalSilenceMs

    fun formatted(durationMs: Long): String {
        val totalSeconds = maxOf(0, durationMs / 1000)
        val minutes = totalSeconds / 60
        val seconds = totalSeconds % 60
        return "${minutes}m ${seconds.toString().padStart(2, '0')}s"
    }

    fun clock(durationMs: Long): String {
        val totalSeconds = maxOf(0, durationMs / 1000)
        val minutes = totalSeconds / 60
        val seconds = totalSeconds % 60
        return "$minutes:${seconds.toString().padStart(2, '0')}"
    }

    fun utcDayProgress(at: Instant, secondsPerDay: Long = 86_400): Double {
        val start = at.atZone(ZoneOffset.UTC).toLocalDate().atStartOfDay(ZoneOffset.UTC).toInstant()
        val elapsed = at.epochSecond - start.epochSecond
        return (elapsed.toDouble() / secondsPerDay.toDouble()).coerceIn(0.0, 1.0)
    }
}

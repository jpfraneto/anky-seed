package inc.anky.android.core.protocol

object AnkyDuration {
    const val CompleteRitualMs: Long = 8 * 60 * 1000
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
}

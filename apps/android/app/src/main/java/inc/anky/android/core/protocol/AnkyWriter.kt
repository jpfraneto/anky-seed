package inc.anky.android.core.protocol

class AnkyWriter private constructor(
    private val lines: MutableList<String>,
    private var lastAcceptedEpochMs: Long?,
    var isClosed: Boolean,
) {
    constructor() : this(mutableListOf(), null, false)

    val text: String
        get() = lines.joinToString(separator = "\n")

    val isStarted: Boolean
        get() = lines.isNotEmpty()

    val lastAcceptedMs: Long?
        get() = lastAcceptedEpochMs

    fun accept(glyph: String, epochMs: Long): Boolean {
        if (isClosed || !glyph.isSingleProtocolGlyph()) return false
        val line = if (lastAcceptedEpochMs == null) {
            "$epochMs $glyph"
        } else {
            "${maxOf(0, epochMs - lastAcceptedEpochMs!!)} $glyph"
        }
        lines += line
        lastAcceptedEpochMs = epochMs
        return true
    }

    fun closeWithTerminalSilence() {
        if (!isStarted || isClosed) return
        lines += AnkyDuration.TerminalSilenceMs.toString()
        isClosed = true
    }

    fun prepareToResume(epochMs: Long) {
        if (!isStarted || isClosed) return
        lastAcceptedEpochMs = epochMs
    }

    companion object {
        fun fromDraft(draftText: String): AnkyWriter {
            val parsed = AnkyParser.parse(draftText)
            val lines = draftText
                .replace("\r\n", "\n")
                .split("\n")
                .dropLastWhile { it.isEmpty() }
                .toMutableList()
            val elapsedWithoutTerminal = parsed.events.sumOf { it.deltaMs }
            return AnkyWriter(
                lines = lines,
                lastAcceptedEpochMs = parsed.startEpochMs + elapsedWithoutTerminal,
                isClosed = parsed.terminalSilenceMs == AnkyDuration.TerminalSilenceMs,
            )
        }
    }
}

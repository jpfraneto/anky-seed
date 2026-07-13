package inc.anky.android.core.protocol

class AnkyWriter private constructor(
    private val lines: MutableList<String>,
    private var lastAcceptedEpochMs: Long?,
    var isClosed: Boolean,
    var writingElapsedMs: Long,
) {
    constructor() : this(mutableListOf(), null, false, 0)

    val text: String
        get() = lines.joinToString(separator = "\n")

    val isStarted: Boolean
        get() = lines.isNotEmpty()

    val lastAcceptedMs: Long?
        get() = lastAcceptedEpochMs

    fun accept(glyph: String, epochMs: Long): Boolean {
        if (isClosed || !glyph.isSingleProtocolGlyph()) return false
        val protocolGlyph = glyph.protocolGlyphText()
        val deltaMs = lastAcceptedEpochMs?.let { maxOf(0, epochMs - it) }
        val line = if (lastAcceptedEpochMs == null) {
            "$epochMs $protocolGlyph"
        } else {
            "$deltaMs $protocolGlyph"
        }
        lines += line
        writingElapsedMs += deltaMs ?: 0
        lastAcceptedEpochMs = epochMs
        return true
    }

    /**
     * The protocol cannot represent deletions, so a backspace is recorded as a
     * suffix rewrite: keep the first [keepingPrefixGlyphCount] glyphs and re-type
     * the replacement on top. Mirrors iOS AnkyWriter.replaceSuffix — the
     * replacement is never empty, so the text can never go empty through here.
     * Returns the glyphs that were re-typed (empty when nothing changed).
     */
    fun replaceSuffix(keepingPrefixGlyphCount: Int, replacementText: String, epochMs: Long): List<String> {
        if (isClosed) return emptyList()

        val replacementGlyphs = replacementText
            .filterNot { it == '\n' || it == '\r' }
            .protocolGlyphsOrNull()
            .orEmpty()
        if (replacementGlyphs.isEmpty()) return emptyList()

        val currentEvents = absoluteEvents()
        val keptCount = keepingPrefixGlyphCount.coerceIn(0, currentEvents.size)
        val events = currentEvents.take(keptCount).toMutableList()
        val times = replacementEventTimes(
            glyphCount = replacementGlyphs.size,
            anchorEpochMs = events.lastOrNull()?.epochMs,
            originalStartEpochMs = currentEvents.firstOrNull()?.epochMs,
            insertionEpochMs = epochMs,
        )

        replacementGlyphs.forEachIndexed { index, glyph ->
            events += AbsoluteWritingEvent(epochMs = times[index], glyph = glyph)
        }

        applyAbsoluteEvents(events)
        return replacementGlyphs
    }

    fun closeWithTerminalSilence() {
        if (!isStarted || isClosed) return
        lines += AnkyDuration.TerminalSilenceMs.toString()
        isClosed = true
    }

    private data class AbsoluteWritingEvent(
        val epochMs: Long,
        val glyph: String,
    )

    private fun absoluteEvents(): List<AbsoluteWritingEvent> {
        val parsed = runCatching { AnkyParser.parse(text) }.getOrNull() ?: return emptyList()
        var cursor = parsed.startEpochMs
        return parsed.events.mapIndexed { index, event ->
            if (index > 0) cursor += event.deltaMs
            AbsoluteWritingEvent(epochMs = cursor, glyph = event.glyph)
        }
    }

    private fun replacementEventTimes(
        glyphCount: Int,
        anchorEpochMs: Long?,
        originalStartEpochMs: Long?,
        insertionEpochMs: Long,
    ): List<Long> {
        if (glyphCount <= 0) return emptyList()

        if (anchorEpochMs != null) {
            return distributedTimes(
                startEpochMs = anchorEpochMs,
                endEpochMs = maxOf(anchorEpochMs, insertionEpochMs),
                gapCount = glyphCount,
                includesAnchor = false,
            )
        }

        val startEpochMs = minOf(originalStartEpochMs ?: insertionEpochMs, insertionEpochMs)
        if (glyphCount == 1) return listOf(startEpochMs)

        return distributedTimes(
            startEpochMs = startEpochMs,
            endEpochMs = maxOf(startEpochMs, insertionEpochMs),
            gapCount = glyphCount - 1,
            includesAnchor = true,
        )
    }

    private fun distributedTimes(
        startEpochMs: Long,
        endEpochMs: Long,
        gapCount: Int,
        includesAnchor: Boolean,
    ): List<Long> {
        if (gapCount <= 0) {
            return if (includesAnchor) listOf(startEpochMs) else emptyList()
        }

        val elapsed = maxOf(0, endEpochMs - startEpochMs)
        val baseDelta = elapsed / gapCount
        val remainder = (elapsed % gapCount).toInt()
        var cursor = startEpochMs
        val times = if (includesAnchor) mutableListOf(startEpochMs) else mutableListOf()

        for (index in 0 until gapCount) {
            cursor += baseDelta + if (index < remainder) 1 else 0
            times += cursor
        }

        return times
    }

    private fun applyAbsoluteEvents(events: List<AbsoluteWritingEvent>) {
        val first = events.firstOrNull()
        if (first == null) {
            lines.clear()
            writingElapsedMs = 0
            lastAcceptedEpochMs = null
            return
        }

        val rebuiltLines = mutableListOf("${first.epochMs} ${first.glyph.protocolGlyphText()}")
        var previousEpochMs = first.epochMs
        var elapsed = 0L

        for (event in events.drop(1)) {
            val delta = maxOf(0, event.epochMs - previousEpochMs)
            rebuiltLines += "$delta ${event.glyph.protocolGlyphText()}"
            elapsed += delta
            previousEpochMs = event.epochMs
        }

        lines.clear()
        lines += rebuiltLines
        writingElapsedMs = elapsed
        lastAcceptedEpochMs = previousEpochMs
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
                writingElapsedMs = elapsedWithoutTerminal,
            )
        }
    }
}

private fun String.protocolGlyphText(): String =
    if (this == " ") "SPACE" else this

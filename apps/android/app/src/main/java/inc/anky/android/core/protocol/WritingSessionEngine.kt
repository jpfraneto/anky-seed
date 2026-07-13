package inc.anky.android.core.protocol

/**
 * Immutable view of the writing session, mirroring iOS WritingSessionSnapshot
 * (ios/Anky/Core/WriteBeforeScroll/WritingSessionEngine.swift).
 */
data class WritingSessionSnapshot(
    val protocolText: String,
    val reconstructedText: String,
    val elapsedMs: Long,
    val lastAcceptedMs: Long?,
    val isStarted: Boolean,
    val isClosed: Boolean,
) {
    /**
     * Mirrors iOS UnlockPolicy.hasCompletedQuickSentence: a completed sentence
     * OR enough words that a sentence is clearly underway. The sentence logic
     * is inlined here until an Android UnlockPolicy exists; keep both in sync.
     */
    val hasCompletedSentence: Boolean
        get() = hasCompletedSentenceIn(reconstructedText) ||
            wordCountIn(reconstructedText) >= QuickPassWordThreshold

    val hasUnlockableWriting: Boolean
        get() = reconstructedText.any { !it.isWhitespace() }

    companion object {
        /** iOS UnlockPolicy.quickPassWordThreshold. */
        const val QuickPassWordThreshold = 6

        fun wordCountIn(text: String): Int =
            text.split(WhitespaceSplitter).count { it.isNotEmpty() }

        /**
         * A completed sentence is a `.`, `!`, or `?` whose nearest preceding
         * non-whitespace character is a letter or number — so `hello`, `...`,
         * `!?`, and `     .` never unlock, while `I am here.` and `Enough!` do.
         */
        fun hasCompletedSentenceIn(text: String): Boolean {
            var lastMeaningfulCharacter: Char? = null
            for (character in text) {
                if (character == '.' || character == '!' || character == '?') {
                    val previous = lastMeaningfulCharacter
                    if (previous != null && (previous.isLetter() || previous.isDigit())) {
                        return true
                    }
                }
                if (!character.isWhitespace()) {
                    lastMeaningfulCharacter = character
                }
            }
            return false
        }

        private val WhitespaceSplitter = Regex("\\s+")
    }
}

/**
 * Wraps AnkyWriter with a live reconstructed-text mirror, ported from iOS
 * WritingSessionEngine (ios/Anky/Core/WriteBeforeScroll/WritingSessionEngine.swift).
 */
class WritingSessionEngine private constructor(
    private var writer: AnkyWriter,
    reconstructedText: String,
) {
    constructor() : this(AnkyWriter(), "")

    var reconstructedText: String = reconstructedText
        private set

    val protocolText: String
        get() = writer.text

    val elapsedMs: Long
        get() = writer.writingElapsedMs

    val isStarted: Boolean
        get() = writer.isStarted

    val isClosed: Boolean
        get() = writer.isClosed

    val lastAcceptedMs: Long?
        get() = writer.lastAcceptedMs

    val hasReachedFullAnky: Boolean
        get() = elapsedMs >= AnkyDuration.CompleteRitualMs

    fun snapshot(): WritingSessionSnapshot =
        WritingSessionSnapshot(
            protocolText = protocolText,
            reconstructedText = reconstructedText,
            elapsedMs = elapsedMs,
            lastAcceptedMs = lastAcceptedMs,
            isStarted = isStarted,
            isClosed = isClosed,
        )

    fun accept(text: String, epochMs: Long): List<String> {
        val glyphs = text
            .filterNot { it == '\n' || it == '\r' }
            .protocolGlyphsOrNull()
            .orEmpty()
        if (glyphs.isEmpty()) return emptyList()

        if (glyphs.size == 1) {
            val glyph = glyphs.first()
            if (!writer.accept(glyph, epochMs)) return emptyList()
            reconstructedText += glyph
            return glyphs
        }

        val eventTimes = syntheticEventTimes(glyphCount = glyphs.size, insertionEpochMs = epochMs)
        val accepted = mutableListOf<String>()
        glyphs.forEachIndexed { index, glyph ->
            if (writer.accept(glyph, eventTimes[index])) {
                reconstructedText += glyph
                accepted += glyph
            }
        }
        return accepted
    }

    fun prepareToResume(epochMs: Long) {
        writer.prepareToResume(epochMs)
    }

    fun replaceSuffix(keepingPrefixGlyphCount: Int, replacementText: String, epochMs: Long): List<String> {
        val accepted = writer.replaceSuffix(
            keepingPrefixGlyphCount = keepingPrefixGlyphCount,
            replacementText = replacementText,
            epochMs = epochMs,
        )
        if (accepted.isEmpty()) return emptyList()

        // The writer rebuilt its protocol lines from the kept prefix plus the
        // replacement, so reconstructing from the protocol text is exactly the
        // iOS prefix + accepted rewrite.
        reconstructedText = runCatching {
            AnkyReconstructor.reconstructText(AnkyParser.parse(writer.text))
        }.getOrDefault(reconstructedText)
        return accepted
    }

    fun closeWithTerminalSilence() {
        writer.closeWithTerminalSilence()
    }

    fun reset() {
        writer = AnkyWriter()
        reconstructedText = ""
    }

    fun silenceElapsedMs(epochMs: Long): Long {
        val lastAcceptedMs = lastAcceptedMs ?: return 0
        return maxOf(0, epochMs - lastAcceptedMs)
    }

    private fun syntheticEventTimes(glyphCount: Int, insertionEpochMs: Long): List<Long> {
        val previousAppendMs = writer.lastAcceptedMs
        if (glyphCount <= 1 || previousAppendMs == null) {
            return List(glyphCount) { insertionEpochMs }
        }

        val elapsedSinceLastAppend = maxOf(0, insertionEpochMs - previousAppendMs)
        if (elapsedSinceLastAppend <= 0) {
            return List(glyphCount) { insertionEpochMs }
        }

        val baseDelta = elapsedSinceLastAppend / glyphCount
        val remainder = (elapsedSinceLastAppend % glyphCount).toInt()
        var cursor = previousAppendMs
        return List(glyphCount) { index ->
            cursor += baseDelta + if (index < remainder) 1 else 0
            cursor
        }
    }

    companion object {
        fun fromDraft(draftText: String): WritingSessionEngine {
            val writer = AnkyWriter.fromDraft(draftText)
            val parsed = AnkyParser.parse(draftText)
            return WritingSessionEngine(
                writer = writer,
                reconstructedText = AnkyReconstructor.reconstructText(parsed),
            )
        }
    }
}

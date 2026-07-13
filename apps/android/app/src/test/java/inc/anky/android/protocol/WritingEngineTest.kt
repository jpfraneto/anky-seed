package inc.anky.android.protocol

import inc.anky.android.core.protocol.AnkyDuration
import inc.anky.android.core.protocol.AnkyParser
import inc.anky.android.core.protocol.AnkyReconstructor
import inc.anky.android.core.protocol.AnkyWriter
import inc.anky.android.core.protocol.WritingSessionEngine
import inc.anky.android.core.protocol.WritingSessionSnapshot
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class WritingEngineTest {
    private val base = 1_770_000_000_000L

    @Test
    fun replaceSuffixRebuildsCurrentWordAsGlyphEventsLikeIos() {
        val writer = AnkyWriter()
        writer.accept("t", base)
        writer.accept("e", base + 30)
        writer.accept("h", base + 60)

        val accepted = writer.replaceSuffix(
            keepingPrefixGlyphCount = 0,
            replacementText = "the",
            epochMs = base + 90,
        )

        assertEquals(listOf("t", "h", "e"), accepted)
        val parsed = AnkyParser.parse(writer.text)
        assertEquals("the", AnkyReconstructor.reconstructText(parsed))
        assertEquals(listOf("t", "h", "e"), parsed.events.map { it.glyph })
        assertEquals(90, AnkyDuration.durationMs(parsed))
    }

    @Test
    fun replaceSuffixPreservesPrefixAndInterpolatesCorrectedTailLikeIos() {
        val writer = AnkyWriter()
        "hello teh ".forEachIndexed { index, character ->
            writer.accept(character.toString(), base + index * 20L)
        }

        val accepted = writer.replaceSuffix(
            keepingPrefixGlyphCount = 6,
            replacementText = "the ",
            epochMs = base + 240,
        )

        assertEquals(listOf("t", "h", "e", " "), accepted)
        val parsed = AnkyParser.parse(writer.text)
        assertEquals("hello the ", AnkyReconstructor.reconstructText(parsed))
        assertEquals("hello the ".map { it.toString() }, parsed.events.map { it.glyph })
        assertEquals(240, AnkyDuration.durationMs(parsed))
        assertFalse(writer.text.contains("teh"))
    }

    @Test
    fun replaceSuffixRecordsBackspaceWithoutEverEmptyingTheText() {
        val writer = AnkyWriter()
        writer.accept("h", base)
        writer.accept("i", base + 40)

        // Backspace on "hi": keep prefix N−1 = 1 glyph minus the erased one (0),
        // and re-type the surviving last character.
        val accepted = writer.replaceSuffix(
            keepingPrefixGlyphCount = 0,
            replacementText = "h",
            epochMs = base + 80,
        )

        assertEquals(listOf("h"), accepted)
        val parsed = AnkyParser.parse(writer.text)
        assertEquals("h", AnkyReconstructor.reconstructText(parsed))
        assertTrue(writer.isStarted)
    }

    @Test
    fun replaceSuffixIsRejectedWhenClosedOrEmptyReplacement() {
        val writer = AnkyWriter()
        writer.accept("h", base)
        writer.closeWithTerminalSilence()
        assertEquals(emptyList<String>(), writer.replaceSuffix(0, "x", base + 10))

        val open = AnkyWriter()
        open.accept("h", base)
        assertEquals(emptyList<String>(), open.replaceSuffix(0, "\n\r", base + 10))
        assertEquals("h", AnkyReconstructor.reconstructText(AnkyParser.parse(open.text)))
    }

    @Test
    fun engineAcceptsTextAndTracksReconstructedMirror() {
        val engine = WritingSessionEngine()
        assertFalse(engine.isStarted)

        assertEquals(listOf("h"), engine.accept("h", base))
        assertEquals(listOf("i", " "), engine.accept("i ", base + 40))
        assertEquals(emptyList<String>(), engine.accept("\n", base + 60))

        assertEquals("hi ", engine.reconstructedText)
        assertTrue(engine.isStarted)
        assertFalse(engine.isClosed)
        assertEquals(40, engine.elapsedMs)
        assertEquals(base + 40, engine.lastAcceptedMs)
        assertEquals(
            "hi ",
            AnkyReconstructor.reconstructText(AnkyParser.parse(engine.protocolText)),
        )
    }

    @Test
    fun engineReplaceSuffixKeepsMirrorInSyncWithProtocol() {
        val engine = WritingSessionEngine()
        engine.accept("t", base)
        engine.accept("e", base + 30)
        engine.accept("h", base + 60)

        val accepted = engine.replaceSuffix(
            keepingPrefixGlyphCount = 0,
            replacementText = "the",
            epochMs = base + 90,
        )

        assertEquals(listOf("t", "h", "e"), accepted)
        assertEquals("the", engine.reconstructedText)
        assertEquals(
            engine.reconstructedText,
            AnkyReconstructor.reconstructText(AnkyParser.parse(engine.protocolText)),
        )
    }

    @Test
    fun engineSnapshotCarriesSessionState() {
        val engine = WritingSessionEngine()
        engine.accept("I am here.", base)
        engine.closeWithTerminalSilence()

        val snapshot = engine.snapshot()
        assertEquals("I am here.", snapshot.reconstructedText)
        assertEquals(engine.protocolText, snapshot.protocolText)
        assertTrue(snapshot.isStarted)
        assertTrue(snapshot.isClosed)
        assertTrue(snapshot.hasCompletedSentence)
        assertTrue(snapshot.hasUnlockableWriting)
    }

    @Test
    fun snapshotSentenceRulesMatchIosUnlockPolicy() {
        fun snapshot(text: String) = WritingSessionSnapshot(
            protocolText = "",
            reconstructedText = text,
            elapsedMs = 0,
            lastAcceptedMs = null,
            isStarted = text.isNotEmpty(),
            isClosed = false,
        )

        assertTrue(snapshot("I am here.").hasCompletedSentence)
        assertTrue(snapshot("Enough!").hasCompletedSentence)
        assertFalse(snapshot("hello").hasCompletedSentence)
        assertFalse(snapshot("...").hasCompletedSentence)
        assertFalse(snapshot("!?").hasCompletedSentence)
        assertFalse(snapshot("     .").hasCompletedSentence)
        // Six words trip the quick-pass threshold even with no punctuation.
        assertTrue(snapshot("one two three four five six").hasCompletedSentence)
        assertFalse(snapshot("one two three four five").hasCompletedSentence)

        assertFalse(snapshot("    ").hasUnlockableWriting)
        assertTrue(snapshot(" a").hasUnlockableWriting)
    }

    @Test
    fun engineRestoresFromDraftAndResets() {
        val engine = WritingSessionEngine.fromDraft("$base h\n42 i")
        assertEquals("hi", engine.reconstructedText)
        assertEquals(42, engine.elapsedMs)
        assertFalse(engine.isClosed)
        assertEquals(base + 42, engine.lastAcceptedMs)
        assertEquals(0, engine.silenceElapsedMs(base + 42))
        assertEquals(100, engine.silenceElapsedMs(base + 142))

        engine.prepareToResume(base + 5_000)
        engine.accept("!", base + 5_000)
        assertEquals(42, engine.elapsedMs)
        assertEquals("hi!", engine.reconstructedText)

        engine.reset()
        assertEquals("", engine.reconstructedText)
        assertEquals("", engine.protocolText)
        assertFalse(engine.isStarted)
        assertNull(engine.lastAcceptedMs)
    }

    @Test
    fun engineFullAnkyThresholdMatchesRitualDuration() {
        val engine = WritingSessionEngine.fromDraft("$base h\n${AnkyDuration.CompleteRitualMs} i")
        assertTrue(engine.hasReachedFullAnky)

        val fragment = WritingSessionEngine.fromDraft("$base h\n${AnkyDuration.CompleteRitualMs - 1} i")
        assertFalse(fragment.hasReachedFullAnky)
    }
}

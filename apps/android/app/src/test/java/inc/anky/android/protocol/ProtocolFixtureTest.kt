package inc.anky.android.protocol

import inc.anky.android.core.protocol.AnkyDuration
import inc.anky.android.core.protocol.AnkyHasher
import inc.anky.android.core.protocol.AnkyReconstructor
import inc.anky.android.core.protocol.AnkyValidation
import inc.anky.android.core.protocol.AnkyValidator
import inc.anky.android.core.protocol.AnkyWriter
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ProtocolFixtureTest {
    @Test
    fun validCompleteFixtureMatchesExpected() {
        val text = fixture("valid-complete.anky").readText()
        val validation = AnkyValidator.validate(text)
        assertTrue(validation is AnkyValidation.Valid)
        val valid = validation as AnkyValidation.Valid
        assertTrue(valid.isComplete)
        assertEquals(480000, valid.durationMs)
        assertEquals("hello!", AnkyReconstructor.reconstructText(valid.parsed))
    }

    @Test
    fun validFragmentFixtureMatchesExpected() {
        val text = fixture("valid-fragment.anky").readText()
        val validation = AnkyValidator.validate(text)
        assertTrue(validation is AnkyValidation.Valid)
        val valid = validation as AnkyValidation.Valid
        assertFalse(valid.isComplete)
        assertEquals(216, valid.durationMs)
        assertEquals("hello", AnkyReconstructor.reconstructText(valid.parsed))
    }

    @Test
    fun invalidFixturesAreRejected() {
        assertFalse(AnkyValidator.validate(fixture("invalid-empty.anky").readText()).isValid)
        assertFalse(AnkyValidator.validate(fixture("invalid-malformed.anky").readText()).isValid)
    }

    @Test
    fun writerEmitsDeterministicProtocolLines() {
        val writer = AnkyWriter()
        assertTrue(writer.accept("h", 1770000000000))
        assertTrue(writer.accept("e", 1770000000042))
        assertTrue(writer.accept(" ", 1770000000043))
        assertFalse(writer.accept("\n", 1770000000043))
        writer.closeWithTerminalSilence()
        assertEquals("1770000000000 h\n42 e\n1  \n${AnkyDuration.TerminalSilenceMs}", writer.text)
        val validation = AnkyValidator.validate(writer.text) as AnkyValidation.Valid
        assertEquals("he ", AnkyReconstructor.reconstructText(validation.parsed))
    }

    @Test
    fun writerAcceptsSingleGraphemeClustersLikeSwiftCharacter() {
        val writer = AnkyWriter()

        assertTrue(writer.accept("e\u0301", 1770000000000))
        assertTrue(writer.accept("👍🏽", 1770000000042))
        assertTrue(writer.accept("👨‍👩‍👧‍👦", 1770000000084))
        assertTrue(writer.accept("🇨🇱", 1770000000126))
        assertTrue(writer.accept("\u0301", 1770000000168))
        assertTrue(writer.accept("\u200D", 1770000000210))
        assertTrue(writer.accept("a\u200D", 1770000000252))
        assertFalse(writer.accept("ab", 1770000000127))
        assertFalse(writer.accept("a\n", 1770000000127))

        assertEquals("1770000000000 e\u0301\n42 👍🏽\n42 👨‍👩‍👧‍👦\n42 🇨🇱\n42 \u0301\n42 \u200D\n42 a\u200D", writer.text)
        val validation = AnkyValidator.validate(writer.text) as AnkyValidation.Valid
        assertEquals("e\u0301👍🏽👨‍👩‍👧‍👦🇨🇱\u0301\u200Da\u200D", AnkyReconstructor.reconstructText(validation.parsed))
    }

    @Test
    fun durationFormattingMatchesIosClampingAndShape() {
        assertEquals("0m 00s", AnkyDuration.formatted(-1_000))
        assertEquals("0m 00s", AnkyDuration.formatted(999))
        assertEquals("1m 01s", AnkyDuration.formatted(61_999))
    }

    @Test
    fun hashUsesExactUtf8Bytes() {
        val body = "1770000000000 h\n0042 e\n8000"
        assertNotEquals(
            AnkyHasher.sha256Hex(body.toByteArray(Charsets.UTF_8)),
            AnkyHasher.sha256Hex("$body\n".toByteArray(Charsets.UTF_8)),
        )
    }
}

private fun fixture(name: String): File = findRepoRoot().resolve("protocol/fixtures/$name")

private fun findRepoRoot(): File {
    var current = File(checkNotNull(System.getProperty("user.dir"))).canonicalFile
    while (current.parentFile != null) {
        if (current.resolve("protocol/fixtures").isDirectory) return current
        current = checkNotNull(current.parentFile)
    }
    error("Could not find repo root")
}

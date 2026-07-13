package inc.anky.android.write

import inc.anky.android.feature.write.AnkyNudgeGenerator
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Port checks for ios/Anky/Core/Mirror/AnkyNudgeGenerator.swift. */
class AnkyNudgeGeneratorTest {
    @Test
    fun detectsSpanishByMarkersOrAccents() {
        assertEquals("es", AnkyNudgeGenerator.detectLanguage("hoy no sé qué escribir"))
        assertEquals("es", AnkyNudgeGenerator.detectLanguage("estoy cansado pero quiero seguir con esto"))
        assertEquals("en", AnkyNudgeGenerator.detectLanguage("today I am writing about the sea"))
    }

    @Test
    fun themesFollowTheIosKeywordLadder() {
        assertEquals("fear", AnkyNudgeGenerator.detectTheme("i am scared of this", 500.0, 100))
        assertEquals("love", AnkyNudgeGenerator.detectTheme("my daughter laughed", 500.0, 100))
        assertEquals("work", AnkyNudgeGenerator.detectTheme("the startup is heavy", 500.0, 100))
        assertEquals("stuck", AnkyNudgeGenerator.detectTheme("i feel blocked here", 500.0, 100))
        assertEquals("exhaustion", AnkyNudgeGenerator.detectTheme("so tired tonight", 500.0, 100))
        assertEquals("aspiration", AnkyNudgeGenerator.detectTheme("i imagine a house by the sea", 500.0, 100))
        assertEquals("early", AnkyNudgeGenerator.detectTheme("nothing themed", 100.0, 100))
        assertEquals("brief", AnkyNudgeGenerator.detectTheme("nothing themed", 500.0, 10))
        assertEquals("default", AnkyNudgeGenerator.detectTheme("nothing themed", 500.0, 100))
    }

    @Test
    fun sameWritingKeepsTheSameVoiceAndOffsetRotatesIt() {
        val writing = "the same page of writing"
        val first = AnkyNudgeGenerator.generateNudge(writing, 500.0, 100, offset = 0)
        val again = AnkyNudgeGenerator.generateNudge(writing, 500.0, 100, offset = 0)
        val rotated = AnkyNudgeGenerator.generateNudge(writing, 500.0, 100, offset = 1)
        assertEquals(first, again)
        assertNotEquals(first, rotated)
    }

    @Test
    fun spanishWritingGetsSpanishNudges() {
        val nudge = AnkyNudgeGenerator.generateNudge(
            "estoy cansado pero quiero seguir con esto porque tengo miedo",
            500.0,
            100,
        )
        val spanishFearNudges = listOf(
            "Veo que rodeas algo que no te deja dormir. Sigue escribiendo; va a tomar forma.",
            "Hay un miedo aqui que vienes cargando. Todavia no tienes que nombrarlo.",
            "Eso que temes ya esta en estas palabras. Quedate cerca.",
        )
        assertTrue(nudge, nudge in spanishFearNudges)
    }
}

package inc.anky.android.write

import inc.anky.android.core.protocol.AnkyReconstructor
import inc.anky.android.core.protocol.AnkyValidation
import inc.anky.android.core.protocol.AnkyValidator
import inc.anky.android.feature.write.DevAnkyFixture
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class DevAnkyFixtureTest {
    @Test
    fun builtInDevPasteFixtureIsCompleteAnky() {
        val validation = AnkyValidator.validate(DevAnkyFixture.validArtifact)

        assertTrue(validation is AnkyValidation.Valid)
        val valid = validation as AnkyValidation.Valid
        assertTrue(valid.isComplete)
        assertEquals(480_000, valid.durationMs)
        assertEquals("hello!", AnkyReconstructor.reconstructText(valid.parsed))
    }
}

package inc.anky.android.privacy

import inc.anky.android.core.privacy.PrivacyMessages
import inc.anky.android.core.privacy.SafeLog
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SafeLogTest {
    @Test
    fun rejectsRawAnkyLikeContent() {
        assertFalse(SafeLog.isSafe("1770000000000 secret\n0042 writing"))
    }

    @Test
    fun rejectsSensitiveIdentityAndMirrorFields() {
        assertFalse(SafeLog.isSafe("recovery phrase able about above absent absorb abstract access accident account across action actual"))
        assertFalse(SafeLog.isSafe("seed phrase imported"))
        assertFalse(SafeLog.isSafe("private key loaded"))
        assertFalse(SafeLog.isSafe("X-Anky-Signature=3mJr7AoUXx2Wqd"))
        assertFalse(SafeLog.isSafe("signature=3mJr7AoUXx2Wqd"))
    }

    @Test
    fun rejectsReflectionTextLabels() {
        assertFalse(SafeLog.isSafe("reflection=Here is what I saw."))
        assertFalse(SafeLog.isSafe("saved reflection title Small Thread"))
    }

    @Test
    fun allowsHashesAndStatuses() {
        assertTrue(SafeLog.isSafe("request statusCode=200 ankyHash=abcdef durationMs=480000"))
    }

    @Test
    fun freeCreditMessageContainsNoWritingContent() {
        val message = PrivacyMessages.freeCreditMessage("pubkey", "0.1.0")
        assertTrue(message.contains("hey jp, i'd love to try anky reflections."))
        assertTrue(message.contains("pubkey"))
        assertTrue(message.contains("platform: android"))
        assertTrue(message.contains("app version: 0.1.0"))
        assertFalse(message.contains(".anky"))
        assertFalse(message.contains("writing:"))
    }
}

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
    fun allowsHashesAndStatuses() {
        assertTrue(SafeLog.isSafe("request statusCode=200 ankyHash=abcdef durationMs=480000"))
    }

    @Test
    fun freeCreditMessageContainsNoWritingContent() {
        val message = PrivacyMessages.freeCreditMessage("pubkey", "0.1.0")
        assertTrue(message.contains("pubkey"))
        assertFalse(message.contains(".anky"))
        assertFalse(message.contains("writing:"))
    }
}

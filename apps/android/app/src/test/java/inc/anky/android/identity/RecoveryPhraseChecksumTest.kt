package inc.anky.android.identity

import inc.anky.android.core.identity.RecoveryPhrase
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class RecoveryPhraseChecksumTest {
    private val validPhrase =
        "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
    private val validZooPhrase =
        "zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo wrong"

    /** Dictionary-valid words whose BIP39 checksum does not add up. */
    private val typoPhrase =
        "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon"

    @Test
    fun knownBip39VectorsPassChecksum() {
        assertTrue(RecoveryPhrase.parse(validPhrase).hasValidChecksum)
        assertTrue(RecoveryPhrase.parse(validZooPhrase).hasValidChecksum)
    }

    @Test
    fun generatedPhrasesAlwaysCarryValidChecksums() {
        repeat(8) {
            assertTrue(RecoveryPhrase.generate().hasValidChecksum)
        }
    }

    @Test
    fun importValidationAcceptsValidPhraseAndNormalizesText() {
        val phrase = RecoveryPhrase.parse("  ${validPhrase.uppercase()}  ", validatingChecksum = true)
        assertEquals(validPhrase, phrase.text)
    }

    @Test
    fun importValidationRejectsDictionaryValidOneWordTypo() {
        assertFalse(RecoveryPhrase.parse(typoPhrase).hasValidChecksum)
        try {
            RecoveryPhrase.parse(typoPhrase, validatingChecksum = true)
            fail("Expected checksum rejection on import")
        } catch (expected: IllegalArgumentException) {
            assertTrue(expected.message!!.contains("checksum"))
        }
    }

    @Test
    fun storedPhrasesStillLoadWithoutChecksumValidation() {
        // A pre-validation import must never brick an existing identity:
        // plain parse keeps accepting checksum-invalid, dictionary-valid words.
        val stored = RecoveryPhrase.parse(typoPhrase)
        assertEquals(typoPhrase, stored.text)

        val storedViaFlag = RecoveryPhrase.parse(typoPhrase, validatingChecksum = false)
        assertEquals(typoPhrase, storedViaFlag.text)
    }
}

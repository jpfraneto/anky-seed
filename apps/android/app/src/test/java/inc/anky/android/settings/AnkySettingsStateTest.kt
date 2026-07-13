package inc.anky.android.settings

import inc.anky.android.core.gate.DailyTargetStore
import inc.anky.android.core.gate.WriteBeforeScrollGateSwitchStore
import inc.anky.android.core.gate.WritingAnchorStore
import inc.anky.android.core.storage.AnkyWritingFontChoice
import inc.anky.android.core.storage.AnkyWritingTextSize
import inc.anky.android.core.storage.WritingPreferences
import inc.anky.android.core.storage.WritingPreferencesStore
import inc.anky.android.feature.settings.dailyTargetFootnote
import inc.anky.android.feature.settings.dailyTargetHeadline
import inc.anky.android.feature.settings.encryptedBackupSubtitle
import inc.anky.android.feature.settings.gateStateLine
import inc.anky.android.gate.FakeSharedPreferences
import java.time.Instant
import java.time.ZoneOffset
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Settings-screen store round-trips and pure UI-state derivations (WS8):
 * everything AnkySettingsScreen reads or writes, exercised against the same
 * stores the composable constructs.
 */
class AnkySettingsStateTest {
    @Test
    fun writingPreferencesRoundTripThroughTheStoreKeepIosRawValues() {
        var stored: String? = null
        val store = WritingPreferencesStore.forStorage(read = { stored }, write = { stored = it })

        assertEquals(WritingPreferences.RitualDefault, store.load())

        val tuned = WritingPreferences(
            backspaceAllowed = true,
            autocorrectEnabled = false,
            fontChoice = AnkyWritingFontChoice.Typewriter,
            textSize = AnkyWritingTextSize.Grand,
        )
        store.save(tuned)

        assertEquals(tuned, store.load())
        val payload = checkNotNull(stored)
        // iOS Codable raw values must survive so a device switch keeps the hand.
        assertTrue(payload, payload.contains("\"fontChoice\":\"typewriter\""))
        assertTrue(payload, payload.contains("\"textSize\":\"grand\""))
    }

    @Test
    fun fontAndSizeChipSelectionCoversAllFiveHandsAndFourSteps() {
        assertEquals(5, AnkyWritingFontChoice.entries.size)
        assertEquals(4, AnkyWritingTextSize.entries.size)
        var stored: String? = null
        val store = WritingPreferencesStore.forStorage(read = { stored }, write = { stored = it })
        AnkyWritingFontChoice.entries.forEach { choice ->
            store.update { it.copy(fontChoice = choice) }
            assertEquals(choice, store.load().fontChoice)
        }
        AnkyWritingTextSize.entries.forEach { size ->
            store.update { it.copy(textSize = size) }
            assertEquals(size, store.load().textSize)
        }
    }

    @Test
    fun dailyTargetEditFromSettingsTakesEffectNextLocalDay() {
        val preferences = FakeSharedPreferences()
        val store = DailyTargetStore(preferences)
        val zone = ZoneOffset.UTC
        val today = Instant.parse("2026-07-07T10:00:00Z")

        store.setInitialTarget(8)
        val change = store.requestTargetChange(3, now = today, zoneId = zone)
        assertEquals(8, change.oldMinutes)
        assertEquals(3, change.newMinutes)

        // Today's gate cannot be lowered mid-lock…
        assertEquals(8, store.effectiveTargetMinutes(now = today, zoneId = zone))
        assertEquals(3, store.pendingTargetMinutes(now = today, zoneId = zone))

        // …and tomorrow the pending value is promoted.
        val tomorrow = Instant.parse("2026-07-08T10:00:00Z")
        assertEquals(3, store.effectiveTargetMinutes(now = tomorrow, zoneId = zone))
        assertEquals(null, store.pendingTargetMinutes(now = tomorrow, zoneId = zone))
    }

    @Test
    fun dailyTargetFootnoteAndHeadlineMirrorIosSliderCopy() {
        val defaultFootnote = "Writing this long opens your apps for the rest of the day."
        val pendingFormat = "Today stays at %1\$d min · %2\$d min from tomorrow."

        assertEquals(defaultFootnote, dailyTargetFootnote(8, null, defaultFootnote, pendingFormat))
        assertEquals(defaultFootnote, dailyTargetFootnote(8, 8, defaultFootnote, pendingFormat))
        assertEquals(
            "Today stays at 8 min · 3 min from tomorrow.",
            dailyTargetFootnote(8, 3, defaultFootnote, pendingFormat),
        )
        assertEquals("1 minute a day", dailyTargetHeadline(1, "%1\$d minute a day", "%1\$d minutes a day"))
        assertEquals("8 minutes a day", dailyTargetHeadline(8, "%1\$d minute a day", "%1\$d minutes a day"))
    }

    @Test
    fun writerNameRoundTripsThroughTheAnchorStore() {
        val preferences = FakeSharedPreferences()
        val store = WritingAnchorStore(preferences)

        assertEquals(WritingAnchorStore.DefaultWriterName, store.writerName)

        store.save(writerName = "Jorge", anchorSentence = store.anchorSentence)
        assertEquals("Jorge", store.writerName)

        // Blank input falls back to the default, never an empty header.
        store.save(writerName = "   ", anchorSentence = store.anchorSentence)
        assertEquals(WritingAnchorStore.DefaultWriterName, store.writerName)
    }

    @Test
    fun gateOffSwitchRoundTripsAndDrivesTheSettingsGateLine() {
        val preferences = FakeSharedPreferences()
        val switch = WriteBeforeScrollGateSwitchStore(preferences)

        assertEquals(false, switch.isGateOff)
        switch.setGateOff(true)
        assertEquals(true, switch.isGateOff)

        val offLine = "The gate is off."
        val noSelection = "No apps chosen yet."
        val oneApp = "Gating 1 app until you write."
        val manyFormat = "Gating %1\$d apps until you write."

        assertEquals(offLine, gateStateLine(true, 5, offLine, noSelection, oneApp, manyFormat))
        assertEquals(noSelection, gateStateLine(false, 0, offLine, noSelection, oneApp, manyFormat))
        assertEquals(oneApp, gateStateLine(false, 1, offLine, noSelection, oneApp, manyFormat))
        assertEquals("Gating 5 apps until you write.", gateStateLine(false, 5, offLine, noSelection, oneApp, manyFormat))
    }

    @Test
    fun encryptedBackupSubtitleStatesMatchIosProtectionRow() {
        val off = "Keep an encrypted copy of your archive."
        val on = "Encrypted backup is on."
        val lastFormat = "Encrypted · last backup %1\$s"

        assertEquals(off, encryptedBackupSubtitle(false, null, on, off, lastFormat))
        assertEquals(off, encryptedBackupSubtitle(false, Instant.EPOCH, on, off, lastFormat))
        assertEquals(on, encryptedBackupSubtitle(true, null, on, off, lastFormat))
        val dated = encryptedBackupSubtitle(true, Instant.EPOCH, on, off, lastFormat)
        assertTrue(dated, dated.startsWith("Encrypted · last backup "))
    }
}

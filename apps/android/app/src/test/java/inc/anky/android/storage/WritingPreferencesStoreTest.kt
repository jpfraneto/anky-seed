package inc.anky.android.storage

import inc.anky.android.core.storage.AnkyWritingFontChoice
import inc.anky.android.core.storage.AnkyWritingTextSize
import inc.anky.android.core.storage.WritingPreferences
import inc.anky.android.core.storage.WritingPreferencesStore
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class WritingPreferencesStoreTest {
    private var stored: String? = null
    private val store = WritingPreferencesStore.forStorage(
        read = { stored },
        write = { stored = it },
    )

    @Test
    fun defaultsToRitualPreferencesWhenNothingStored() {
        val preferences = store.load()

        assertEquals(WritingPreferences.RitualDefault, preferences)
        assertFalse(preferences.backspaceAllowed)
        assertTrue(preferences.autocorrectEnabled)
        assertEquals(AnkyWritingFontChoice.Quill, preferences.fontChoice)
        assertEquals(AnkyWritingTextSize.Medium, preferences.textSize)
    }

    @Test
    fun saveLoadRoundTripsAndMatchesIosJsonShape() {
        store.save(
            WritingPreferences(
                backspaceAllowed = true,
                autocorrectEnabled = false,
                fontChoice = AnkyWritingFontChoice.Typewriter,
                textSize = AnkyWritingTextSize.Grand,
            ),
        )

        val json = JSONObject(checkNotNull(stored))
        assertTrue(json.getBoolean("backspaceAllowed"))
        assertFalse(json.getBoolean("autocorrectEnabled"))
        assertEquals("typewriter", json.getString("fontChoice"))
        assertEquals("grand", json.getString("textSize"))

        val loaded = store.load()
        assertTrue(loaded.backspaceAllowed)
        assertFalse(loaded.autocorrectEnabled)
        assertEquals(AnkyWritingFontChoice.Typewriter, loaded.fontChoice)
        assertEquals(AnkyWritingTextSize.Grand, loaded.textSize)
    }

    @Test
    fun corruptOrPartialJsonFallsBackToRitualDefaultLikeIosDecodeFailure() {
        stored = "not json"
        assertEquals(WritingPreferences.RitualDefault, store.load())

        stored = """{"backspaceAllowed":true}"""
        assertEquals(WritingPreferences.RitualDefault, store.load())

        stored = """{"backspaceAllowed":true,"autocorrectEnabled":true,"fontChoice":"comic-sans","textSize":"medium"}"""
        assertEquals(WritingPreferences.RitualDefault, store.load())
    }

    @Test
    fun updateMutatesOnlyTheChangedField() {
        store.update { it.copy(backspaceAllowed = true) }

        val loaded = store.load()
        assertTrue(loaded.backspaceAllowed)
        assertTrue(loaded.autocorrectEnabled)
        assertEquals(AnkyWritingFontChoice.Quill, loaded.fontChoice)
    }

    @Test
    fun rawValuesAndSizesMatchIosExactly() {
        assertEquals(
            listOf("quill", "georgia", "round", "plain", "typewriter"),
            AnkyWritingFontChoice.entries.map { it.rawValue },
        )
        assertEquals(
            listOf("small", "medium", "large", "grand"),
            AnkyWritingTextSize.entries.map { it.rawValue },
        )
        assertEquals(
            listOf(18.0, 21.0, 24.0, 28.0),
            AnkyWritingTextSize.entries.map { it.pointSize },
        )
        assertEquals("anky.writingPreferences.v1", WritingPreferencesStore.Key)
        assertEquals("Quill", AnkyWritingFontChoice.Quill.displayName)
        assertEquals("Grand", AnkyWritingTextSize.Grand.displayName)
    }
}

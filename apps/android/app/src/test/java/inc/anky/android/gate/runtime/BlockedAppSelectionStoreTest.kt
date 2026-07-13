package inc.anky.android.gate.runtime

import inc.anky.android.core.gate.runtime.BlockedApp
import inc.anky.android.core.gate.runtime.BlockedAppSelectionStore
import inc.anky.android.gate.FakeSharedPreferences
import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class BlockedAppSelectionStoreTest {

    private val preferences = FakeSharedPreferences()
    private val store = BlockedAppSelectionStore(preferences)
    private val now = Instant.parse("2026-07-07T12:00:00Z")

    private val apps = listOf(
        BlockedApp(packageName = "com.instagram.android", label = "Instagram"),
        BlockedApp(packageName = "com.twitter.android", label = "X"),
    )

    @Test
    fun `empty store has no selection`() {
        assertEquals(emptyList<BlockedApp>(), store.load())
        assertFalse(store.hasSelection)
        assertEquals(emptySet<String>(), store.blockedPackages())
    }

    @Test
    fun `saves and loads the selection round-trip`() {
        store.save(apps, now)
        assertEquals(apps, store.load())
        assertTrue(store.hasSelection)
        assertEquals(
            setOf("com.instagram.android", "com.twitter.android"),
            store.blockedPackages(),
        )
        assertEquals("Instagram", store.labelFor("com.instagram.android"))
        assertNull(store.labelFor("com.example.unknown"))
    }

    @Test
    fun `persists under the iOS key`() {
        store.save(apps, now)
        assertTrue(preferences.contains("writeBeforeScroll.blockedAppSelection.v1"))
    }

    @Test
    fun `clear removes everything`() {
        store.save(apps, now)
        store.clear()
        assertFalse(store.hasSelection)
    }

    @Test
    fun `corrupted payloads decode to empty, never crash`() {
        assertEquals(emptyList<BlockedApp>(), BlockedAppSelectionStore.decode("not json"))
        assertEquals(emptyList<BlockedApp>(), BlockedAppSelectionStore.decode("{\"apps\":42}"))
        assertEquals(emptyList<BlockedApp>(), BlockedAppSelectionStore.decode(null))
    }

    @Test
    fun `entries without a package name are dropped, labels default to the package`() {
        val raw = """
            {"apps":[
                {"packageName":"com.instagram.android"},
                {"label":"orphan"}
            ],"updatedAt":"2026-07-07T12:00:00Z"}
        """.trimIndent()
        assertEquals(
            listOf(BlockedApp("com.instagram.android", "com.instagram.android")),
            BlockedAppSelectionStore.decode(raw),
        )
    }
}

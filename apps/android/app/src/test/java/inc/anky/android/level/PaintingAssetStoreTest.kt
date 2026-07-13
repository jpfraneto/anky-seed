package inc.anky.android.level

import inc.anky.android.core.level.PaintingAssetStore
import java.io.File
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PaintingAssetStoreTest {
    private fun temporaryStore(): PaintingAssetStore {
        val root = File(System.getProperty("java.io.tmpdir"), "anky-paintings-${UUID.randomUUID()}")
        return PaintingAssetStore(root)
    }

    private val meta = """
    {"title": "The Door", "palette": ["#1d1611", "#714a28", "#d2a47e"], "level": 2, "thresholdSeconds": 480}
    """.trimIndent()

    @Test
    fun installAndReadBackPackage() {
        val store = temporaryStore()
        val png = byteArrayOf(0x89.toByte(), 0x50, 0x4E, 0x47)
        val pkg = store.install(
            level = 2,
            finalPng = png,
            underdrawingPng = png,
            revealMapPng = png,
            metaJson = meta.toByteArray(Charsets.UTF_8),
        )
        assertEquals(2, pkg.level)
        assertEquals("The Door", pkg.title)
        assertEquals(3, pkg.palette.size)
        assertEquals(480L, pkg.thresholdSeconds)
        assertNotNull(store.installedPackage(2))
        assertEquals(listOf(2), store.installedLevels())
        assertTrue(pkg.finalFile.exists())
    }

    @Test
    fun incompletePackageIsNotInstalled() {
        val store = temporaryStore()
        val dir = store.directory(3)
        dir.mkdirs()
        File(dir, "final.png").writeBytes(byteArrayOf(0x00))
        assertNull(store.installedPackage(3))
        assertEquals(emptyList<Int>(), store.installedLevels())
    }

    @Test
    fun reinstallReplacesPackage() {
        val store = temporaryStore()
        val png = byteArrayOf(0x01)
        store.install(level = 2, finalPng = png, underdrawingPng = png, revealMapPng = png, metaJson = meta.toByteArray(Charsets.UTF_8))
        val updatedMeta = meta.replace("The Door", "The Return")
        val pkg = store.install(level = 2, finalPng = png, underdrawingPng = png, revealMapPng = png, metaJson = updatedMeta.toByteArray(Charsets.UTF_8))
        assertEquals("The Return", pkg.title)
    }

    @Test
    fun starterInstallsOnceFromBundledAssets() {
        val store = temporaryStore()
        val png = byteArrayOf(0x89.toByte(), 0x50)
        val starterMeta = meta.replace("\"level\": 2", "\"level\": 1").replace("480", "0")
        var loads = 0
        val loader: (String) -> ByteArray? = { path ->
            loads += 1
            assertTrue(path.startsWith("starterpainting/"))
            if (path.endsWith("meta.json")) starterMeta.toByteArray(Charsets.UTF_8) else png
        }
        val installed = store.installStarterIfNeeded(loader)
        assertNotNull(installed)
        assertEquals(1, installed?.level)
        assertEquals("The Door", installed?.title)
        // Second call reuses the cached package without touching assets.
        val loadsAfterFirst = loads
        assertNotNull(store.installStarterIfNeeded(loader))
        assertEquals(loadsAfterFirst, loads)
    }

    @Test
    fun starterInstallFailsSoftWhenAssetsMissing() {
        val store = temporaryStore()
        assertNull(store.installStarterIfNeeded { null })
        assertEquals(emptyList<Int>(), store.installedLevels())
    }
}

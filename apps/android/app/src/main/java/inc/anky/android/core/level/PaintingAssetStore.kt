package inc.anky.android.core.level

import android.content.Context
import inc.anky.android.core.identity.WriterIdentity
import java.io.File
import java.io.IOException
import java.util.UUID
import org.json.JSONObject

/** One level's painting package on disk: the three images and their meta. */
data class PaintingPackage(
    val level: Int,
    val title: String,
    val palette: List<String>,
    val thresholdSeconds: Long,
    val provider: String?,
    val directory: File,
) {
    val finalFile: File get() = File(directory, "final.png")
    val underdrawingFile: File get() = File(directory, "underdrawing.png")
    val revealMapFile: File get() = File(directory, "revealmap.png")
}

/**
 * Downloads, caches, and lists painting packages.
 *
 * Layout: filesDir/Paintings/<level>/{final,underdrawing,revealmap}.png +
 * meta.json — identical to the server package, cached permanently. Level 1
 * ships in the APK assets (starterpainting/) so a fresh install has a
 * painting before any network round-trip.
 */
class PaintingAssetStore(private val root: File) {
    constructor(context: Context) : this(File(context.filesDir, "Paintings"))

    init {
        root.mkdirs()
    }

    fun directory(level: Int): File = File(root, level.toString())

    /** A package is installed only when all four files are present. */
    fun installedPackage(level: Int): PaintingPackage? {
        val dir = directory(level)
        for (name in PackageFileNames) {
            if (!File(dir, name).exists()) return null
        }
        val meta = runCatching { JSONObject(File(dir, "meta.json").readText(Charsets.UTF_8)) }.getOrNull()
            ?: return null
        return meta.toPaintingPackage(level = level, directory = dir)
    }

    /**
     * Copies the bundled starter painting in as level 1, once.
     * `loadAsset` maps an asset path like `starterpainting/final.png` to its
     * bytes (wired to `context.assets` by the app; a lambda keeps this store
     * JVM-testable).
     */
    fun installStarterIfNeeded(loadAsset: (String) -> ByteArray?): PaintingPackage? {
        installedPackage(1)?.let { return it }
        val bytes = PackageFileNames.map { name ->
            loadAsset("$StarterAssetDirectory/$name") ?: return null
        }
        return runCatching {
            install(
                level = 1,
                finalPng = bytes[0],
                underdrawingPng = bytes[1],
                revealMapPng = bytes[2],
                metaJson = bytes[3],
            )
        }.getOrNull()
    }

    /**
     * Writes a freshly downloaded package atomically-ish: files land in a
     * staging directory, then move into place.
     */
    fun install(
        level: Int,
        finalPng: ByteArray,
        underdrawingPng: ByteArray,
        revealMapPng: ByteArray,
        metaJson: ByteArray,
    ): PaintingPackage {
        val staging = File(root, ".staging-$level-${UUID.randomUUID()}")
        staging.mkdirs()
        try {
            File(staging, "final.png").writeBytes(finalPng)
            File(staging, "underdrawing.png").writeBytes(underdrawingPng)
            File(staging, "revealmap.png").writeBytes(revealMapPng)
            File(staging, "meta.json").writeBytes(metaJson)

            val destination = directory(level)
            destination.deleteRecursively()
            if (!staging.renameTo(destination)) {
                throw IOException("PACKAGE_MOVE_FAILED")
            }
            return installedPackage(level) ?: throw IOException("PACKAGE_CORRUPT")
        } finally {
            staging.deleteRecursively()
        }
    }

    /** Every installed level, ascending — the gallery reads completed ones. */
    fun installedLevels(): List<Int> =
        (root.list() ?: emptyArray())
            .mapNotNull { it.toIntOrNull() }
            .sorted()
            .filter { installedPackage(it) != null }

    /** Downloads and installs a level's package from the server. */
    suspend fun downloadPackage(
        level: Int,
        client: LevelSyncing,
        identity: WriterIdentity,
    ): PaintingPackage {
        installedPackage(level)?.let { return it }
        // Sequential on purpose: each GET signs the same empty body, and two
        // signatures minted in the same millisecond would collide with the
        // server's replay protection.
        val finalPng = client.fetchAsset(level, "final.png", identity)
        val underPng = client.fetchAsset(level, "underdrawing.png", identity)
        val mapPng = client.fetchAsset(level, "revealmap.png", identity)
        val metaJson = client.fetchAsset(level, "meta.json", identity)
        return install(
            level = level,
            finalPng = finalPng,
            underdrawingPng = underPng,
            revealMapPng = mapPng,
            metaJson = metaJson,
        )
    }

    companion object {
        val PackageFileNames = listOf("final.png", "underdrawing.png", "revealmap.png", "meta.json")
        const val StarterAssetDirectory = "starterpainting"
    }
}

private fun JSONObject.toPaintingPackage(level: Int, directory: File): PaintingPackage? {
    val title = optString("title").takeIf { it.isNotEmpty() } ?: return null
    val paletteArray = optJSONArray("palette") ?: return null
    if (!has("level") || !has("thresholdSeconds")) return null
    return PaintingPackage(
        level = level,
        title = title,
        palette = (0 until paletteArray.length()).map { paletteArray.getString(it) },
        thresholdSeconds = getLong("thresholdSeconds"),
        provider = if (has("provider") && !isNull("provider")) optString("provider").takeIf { it.isNotEmpty() } else null,
        directory = directory,
    )
}

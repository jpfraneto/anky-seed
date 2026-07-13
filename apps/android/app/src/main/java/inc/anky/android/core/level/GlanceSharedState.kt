package inc.anky.android.core.level

import java.io.File
import org.json.JSONObject

/**
 * The contract between the app and the future painting widget. The app
 * pre-renders a flat composite of the current painting at its true progress
 * and writes it here; the widget only ever reads. The image lands first
 * under a content-addressed name, the JSON last, so the widget never sees a
 * half-written frame.
 *
 * Android home: `filesDir/Widget/` (single process — no App Group needed);
 * the content shape matches iOS `GlanceSnapshot` field-for-field.
 */
data class GlanceSnapshot(
    val level: Int,
    val percent: Int,
    val updatedAtMs: Long,
    val imageFile: String,
    val isPlaceholder: Boolean,
    /**
     * Phase-3 §5: the free tier's held-100% moment. The widget shows the
     * earned painting with the spiral and "a new painting waits" — truthful
     * at the boundary, routing to the veiled ceremony. Nullable so old
     * snapshots on disk keep decoding.
     */
    val isAtBoundary: Boolean?,
)

object GlanceSharedState {
    const val DirectoryName = "Widget"
    const val SnapshotFileName = "snapshot.json"
    const val TrialThumbFileName = "trial-thumb.png"

    fun directory(filesDir: File): File = File(filesDir, DirectoryName)

    fun imageFileName(level: Int, percent: Int): String = "painting-$level-$percent.png"

    fun loadSnapshot(filesDir: File): GlanceSnapshot? {
        val file = File(directory(filesDir), SnapshotFileName)
        if (!file.exists()) return null
        val json = runCatching { JSONObject(file.readText(Charsets.UTF_8)) }.getOrNull() ?: return null
        return runCatching {
            GlanceSnapshot(
                level = json.getInt("level"),
                percent = json.getInt("percent"),
                updatedAtMs = json.getLong("updatedAtMs"),
                imageFile = json.getString("imageFile"),
                isPlaceholder = json.getBoolean("isPlaceholder"),
                isAtBoundary = if (json.has("isAtBoundary") && !json.isNull("isAtBoundary")) {
                    json.getBoolean("isAtBoundary")
                } else {
                    null
                },
            )
        }.getOrNull()
    }

    fun imageFile(filesDir: File, name: String): File = File(directory(filesDir), name)

    /** Image first, snapshot last; stale painting frames are pruned after. */
    fun write(filesDir: File, snapshot: GlanceSnapshot, imageData: ByteArray) {
        val directory = directory(filesDir)
        directory.mkdirs()
        File(directory, snapshot.imageFile).writeBytes(imageData)
        val json = JSONObject()
            .put("level", snapshot.level)
            .put("percent", snapshot.percent)
            .put("updatedAtMs", snapshot.updatedAtMs)
            .put("imageFile", snapshot.imageFile)
            .put("isPlaceholder", snapshot.isPlaceholder)
        snapshot.isAtBoundary?.let { json.put("isAtBoundary", it) }
        File(directory, SnapshotFileName).writeText(json.toString(), Charsets.UTF_8)

        directory.list()?.forEach { name ->
            if (name.startsWith("painting-") && name != snapshot.imageFile) {
                File(directory, name).delete()
            }
        }
    }

    fun writeTrialThumb(filesDir: File, imageData: ByteArray) {
        val directory = directory(filesDir)
        directory.mkdirs()
        File(directory, TrialThumbFileName).writeBytes(imageData)
    }
}

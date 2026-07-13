package inc.anky.android.feature.painting

import android.graphics.Bitmap
import inc.anky.android.core.level.FallbackRevealRenderer
import inc.anky.android.core.level.GlanceSharedState
import inc.anky.android.core.level.GlanceSnapshot
import inc.anky.android.core.level.LevelProgressStore
import inc.anky.android.core.level.PaintingAssetStore
import java.io.ByteArrayOutputStream
import java.io.File
import kotlin.math.roundToInt

/**
 * Android port of the iOS `GlanceSyncCoordinator` render half: after any
 * progress change (seal credit, stroke beat consumed, ceremony, entitlement
 * flip), pre-render the current painting's composite at its presented
 * progress and hand it to `GlanceSharedState` for the future widget.
 *
 * Blocking file + pixel work — call from Dispatchers.IO/Default. The widget
 * itself is a later workstream; writing the snapshot is this side's whole
 * contract.
 */
object PaintingGlanceSync {

    /** Widget composites don't need full resolution. */
    const val WidgetMaxSide = 512

    fun sync(
        filesDir: File,
        progressStore: LevelProgressStore,
        assetStore: PaintingAssetStore,
        entitled: Boolean,
        nowMs: Long = System.currentTimeMillis(),
    ) {
        runCatching {
            val presented = progressStore.presentedProgress(entitled = entitled)
            val atBoundary = progressStore.isAtBoundary(entitled = entitled)
            val pkg = assetStore.installedPackage(presented.level)
                ?: assetStore.installedLevels().lastOrNull()?.let { assetStore.installedPackage(it) }
                ?: return

            val progress = if (pkg.level < presented.level) 1.0 else presented.percent
            val composite = FallbackRevealRenderer().render(pkg, progress) ?: return
            val scaled = downscale(composite, WidgetMaxSide)

            val percent = (progress * 100).roundToInt().coerceIn(0, 100)
            val snapshot = GlanceSnapshot(
                level = presented.level,
                percent = percent,
                updatedAtMs = nowMs,
                imageFile = GlanceSharedState.imageFileName(presented.level, percent),
                isPlaceholder = false,
                isAtBoundary = atBoundary,
            )
            GlanceSharedState.write(filesDir, snapshot, scaled.toPngBytes())
        }
    }

    private fun downscale(bitmap: Bitmap, maxSide: Int): Bitmap {
        if (bitmap.width <= maxSide && bitmap.height <= maxSide) return bitmap
        val scale = maxSide.toFloat() / maxOf(bitmap.width, bitmap.height)
        return Bitmap.createScaledBitmap(
            bitmap,
            (bitmap.width * scale).roundToInt().coerceAtLeast(1),
            (bitmap.height * scale).roundToInt().coerceAtLeast(1),
            true,
        )
    }

    private fun Bitmap.toPngBytes(): ByteArray =
        ByteArrayOutputStream().use { stream ->
            compress(Bitmap.CompressFormat.PNG, 100, stream)
            stream.toByteArray()
        }
}

package inc.anky.android.feature.painting

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.compose.foundation.Image
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.unit.dp
import inc.anky.android.core.level.PaintingPackage
import inc.anky.android.core.level.RevealRules
import inc.anky.android.ui.lazure.LazurePigments
import kotlin.math.roundToInt
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * One level's painting decoded once into pixel arrays, so compositing at a
 * new progress is a single blend pass (the iOS Metal/CoreImage reveal,
 * ported through core's `RevealRules` — same mask math, same soft edge).
 */
class PaintingRevealAssets private constructor(
    val level: Int,
    val width: Int,
    val height: Int,
    private val underPixels: IntArray,
    private val finalPixels: IntArray,
    private val mapRed: IntArray,
    /** The finished painting, for thumbnails (history rows, widget). */
    val finalBitmap: Bitmap,
) {
    /** Composites underdrawing → final at `progress` (0…1). Off-main only. */
    fun composite(progress: Double): Bitmap {
        val output = IntArray(width * height)
        for (index in output.indices) {
            val mask = RevealRules.mask(progress, mapRed[index] / 255.0)
            val f = finalPixels[index]
            val u = underPixels[index]
            output[index] =
                (RevealRules.blendChannel((u ushr 24) and 0xFF, (f ushr 24) and 0xFF, mask) shl 24) or
                (RevealRules.blendChannel((u shr 16) and 0xFF, (f shr 16) and 0xFF, mask) shl 16) or
                (RevealRules.blendChannel((u shr 8) and 0xFF, (f shr 8) and 0xFF, mask) shl 8) or
                RevealRules.blendChannel(u and 0xFF, f and 0xFF, mask)
        }
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        bitmap.setPixels(output, 0, width, 0, 0, width, height)
        return bitmap
    }

    companion object {
        /**
         * Decodes one package's three images (downsampled to at most
         * `maxSide`), scales underdrawing + reveal map to the final's
         * dimensions (mirroring the iOS extent transforms), and extracts
         * the pixel arrays. Null when any decode fails.
         */
        fun load(pkg: PaintingPackage, maxSide: Int = DefaultMaxSide): PaintingRevealAssets? {
            val final = decodeDownsampled(pkg.finalFile.path, maxSide) ?: return null
            val under = decodeDownsampled(pkg.underdrawingFile.path, maxSide) ?: return null
            val map = decodeDownsampled(pkg.revealMapFile.path, maxSide) ?: return null

            val width = final.width
            val height = final.height
            val underScaled = scaledTo(under, width, height)
            val mapScaled = scaledTo(map, width, height)

            val finalPixels = IntArray(width * height)
            val underPixels = IntArray(width * height)
            val mapPixels = IntArray(width * height)
            final.getPixels(finalPixels, 0, width, 0, 0, width, height)
            underScaled.getPixels(underPixels, 0, width, 0, 0, width, height)
            mapScaled.getPixels(mapPixels, 0, width, 0, 0, width, height)

            // The reveal map is grayscale; the red channel carries the value.
            val mapRed = IntArray(width * height) { (mapPixels[it] shr 16) and 0xFF }
            return PaintingRevealAssets(
                level = pkg.level,
                width = width,
                height = height,
                underPixels = underPixels,
                finalPixels = finalPixels,
                mapRed = mapRed,
                finalBitmap = final,
            )
        }

        const val DefaultMaxSide = 1024
        const val GalleryMaxSide = 512

        private fun decodeDownsampled(path: String, maxSide: Int): Bitmap? {
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(path, bounds)
            if (bounds.outWidth <= 0) return null
            val options = BitmapFactory.Options().apply {
                inSampleSize = JourneyImageSampling.inSampleSize(bounds.outWidth, maxSide)
            }
            return BitmapFactory.decodeFile(path, options)
        }

        private fun scaledTo(bitmap: Bitmap, width: Int, height: Int): Bitmap =
            if (bitmap.width == width && bitmap.height == height) {
                bitmap
            } else {
                Bitmap.createScaledBitmap(bitmap, width, height, true)
            }
    }
}

/**
 * A tiny LRU so the home screen, the ceremony's two paintings, and the
 * gallery share decodes instead of re-reading PNGs. Pixel arrays are the
 * heavy part (~12MB per 1024² level), hence the small capacity.
 */
object PaintingRevealAssetCache {
    private const val Capacity = 4
    private val cache = object : LinkedHashMap<String, PaintingRevealAssets>(Capacity, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, PaintingRevealAssets>) =
            size > Capacity
    }

    @Synchronized
    fun get(pkg: PaintingPackage, maxSide: Int = PaintingRevealAssets.DefaultMaxSide): PaintingRevealAssets? {
        val key = "${pkg.directory.path}@$maxSide"
        cache[key]?.let { return it }
        val loaded = PaintingRevealAssets.load(pkg, maxSide) ?: return null
        cache[key] = loaded
        return loaded
    }
}

/** Loads a package's reveal assets off the main thread. */
@Composable
fun rememberPaintingRevealAssets(
    pkg: PaintingPackage?,
    maxSide: Int = PaintingRevealAssets.DefaultMaxSide,
): PaintingRevealAssets? =
    produceState<PaintingRevealAssets?>(initialValue = null, pkg?.directory?.path, maxSide) {
        value = pkg?.let { withContext(Dispatchers.IO) { PaintingRevealAssetCache.get(it, maxSide) } }
    }.value

/**
 * The composite at a bucketed progress, rendered off-main. Bucketing keeps
 * an animating progress from demanding a full blend every frame; the last
 * requested bucket always lands (LaunchedEffect cancels stale renders).
 */
@Composable
private fun rememberRevealComposite(
    assets: PaintingRevealAssets?,
    progress: Double,
    buckets: Int = 100,
): ImageBitmap? {
    val bucket = (progress.coerceIn(0.0, 1.0) * buckets).roundToInt()
    var composite by remember(assets) { mutableStateOf<ImageBitmap?>(null) }
    LaunchedEffect(assets, bucket) {
        if (assets == null) {
            composite = null
        } else {
            composite = withContext(Dispatchers.Default) {
                assets.composite(bucket.toDouble() / buckets)
            }.asImageBitmap()
        }
    }
    return composite
}

private val PaintingCornerShape = RoundedCornerShape(6.dp)

/**
 * The reusable framed painting: whisper-thin gold frame, palette-tinted
 * glow staining the wall behind it, and the reveal composite inside.
 *
 * Used by the main screen, the post-session strokes beat, the ceremony,
 * and the gallery. Progress is animatable; the lantern is lit at any value.
 * Port of iOS `PaintingView` + `PaintingRevealModifier`'s composite path
 * (Android has no Metal shader; the fallback renderer is the only path).
 */
@Composable
fun PaintingView(
    assets: PaintingRevealAssets?,
    progress: Double,
    modifier: Modifier = Modifier,
    glowTint: Color = LazurePigments.ankyGold,
    glowStrength: Float = 1f,
) {
    val composite = rememberRevealComposite(assets, progress)
    Box(
        modifier
            .aspectRatio(1f)
            // iOS: two soft shadows in the palette's glow. Compose shadows
            // can't be tinted per-color below API 28, so the stain is drawn
            // as radial washes behind the frame (drawBehind is unclipped).
            .drawBehind {
                val glowRadius = PaintingFrameMath.GlowRadiusDp.dp.toPx()
                val center = Offset(size.width / 2f, size.height / 2f + 6.dp.toPx())
                drawRect(
                    brush = Brush.radialGradient(
                        colors = listOf(
                            glowTint.copy(alpha = 0.32f * glowStrength),
                            glowTint.copy(alpha = 0f),
                        ),
                        center = center,
                        radius = size.minDimension / 2f + glowRadius,
                    ),
                    topLeft = Offset(-glowRadius * 2.2f, -glowRadius * 2.2f),
                    size = size.copy(
                        width = size.width + glowRadius * 4.4f,
                        height = size.height + glowRadius * 4.4f,
                    ),
                )
                drawRect(
                    brush = Brush.radialGradient(
                        colors = listOf(
                            glowTint.copy(alpha = 0.18f * glowStrength),
                            glowTint.copy(alpha = 0f),
                        ),
                        center = Offset(size.width / 2f, size.height / 2f),
                        radius = size.minDimension / 2f + glowRadius * 2.2f,
                    ),
                    topLeft = Offset(-glowRadius * 2.2f, -glowRadius * 2.2f),
                    size = size.copy(
                        width = size.width + glowRadius * 4.4f,
                        height = size.height + glowRadius * 4.4f,
                    ),
                )
            }
            .clip(PaintingCornerShape)
            .border(
                width = PaintingFrameMath.BorderWidthDp.dp,
                brush = Brush.linearGradient(
                    colors = listOf(
                        LazurePigments.ankyGoldLight,
                        LazurePigments.ankyGold,
                        LazurePigments.ankyGoldLight.copy(alpha = 0.7f),
                    ),
                ),
                shape = PaintingCornerShape,
            ),
    ) {
        if (composite != null) {
            Image(
                bitmap = composite,
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize(),
            )
        } else {
            // Assets decoding / composite arriving: the deep paper breathes.
            Box(
                Modifier
                    .fillMaxSize()
                    .drawBehind { drawRect(LazurePigments.ankyPaperDeep) },
            )
        }
    }
}

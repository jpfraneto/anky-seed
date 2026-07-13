package inc.anky.android.core.level

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import kotlin.math.roundToInt

/**
 * The reveal rule, exactly as iOS's `FallbackRevealRenderer` defines it:
 * mask = clamp((progress − map) × gain) — white where paint has arrived.
 * A map value below `progress` is revealed; the gain gives a narrow
 * (1/60 ≈ 0.0167 in map units) soft edge instead of a hard threshold.
 *
 * Kept as pure math so the rule itself is unit-testable on the JVM.
 */
object RevealRules {
    const val Gain = 60.0

    /** 0 = underdrawing, 1 = final painting, for one map value at one progress. */
    fun mask(progress: Double, mapValue: Double): Double =
        ((progress - mapValue) * Gain).coerceIn(0.0, 1.0)

    /** Linear interpolation of one 0–255 channel by the mask. */
    fun blendChannel(under: Int, final: Int, mask: Double): Int =
        (under + (final - under) * mask).roundToInt().coerceIn(0, 255)
}

/**
 * Composites underdrawing + final masked by the reveal map at `progress`
 * into a Bitmap — the Android port of iOS's Core Image fallback renderer
 * (the only reveal path on Android; minSdk 26 predates AGSL shaders).
 *
 * Deterministic: pure per-pixel math, no filters, no hardware paths.
 */
class FallbackRevealRenderer {
    /**
     * Renders the composite at `progress` (0…1). The underdrawing and reveal
     * map are scaled to the final painting's dimensions, mirroring the iOS
     * extent transforms.
     */
    fun render(
        underdrawing: Bitmap,
        final: Bitmap,
        revealMap: Bitmap,
        progress: Double,
    ): Bitmap {
        val width = final.width
        val height = final.height
        val under = scaledTo(underdrawing, width, height)
        val map = scaledTo(revealMap, width, height)

        val finalPixels = IntArray(width * height)
        val underPixels = IntArray(width * height)
        val mapPixels = IntArray(width * height)
        final.getPixels(finalPixels, 0, width, 0, 0, width, height)
        under.getPixels(underPixels, 0, width, 0, 0, width, height)
        map.getPixels(mapPixels, 0, width, 0, 0, width, height)

        val output = IntArray(width * height)
        for (index in output.indices) {
            // The reveal map is grayscale; the red channel carries the value.
            val mapValue = ((mapPixels[index] shr 16) and 0xFF) / 255.0
            val m = RevealRules.mask(progress, mapValue)
            val f = finalPixels[index]
            val u = underPixels[index]
            output[index] =
                (RevealRules.blendChannel((u ushr 24) and 0xFF, (f ushr 24) and 0xFF, m) shl 24) or
                (RevealRules.blendChannel((u shr 16) and 0xFF, (f shr 16) and 0xFF, m) shl 16) or
                (RevealRules.blendChannel((u shr 8) and 0xFF, (f shr 8) and 0xFF, m) shl 8) or
                RevealRules.blendChannel(u and 0xFF, f and 0xFF, m)
        }

        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        bitmap.setPixels(output, 0, width, 0, 0, width, height)
        return bitmap
    }

    /** Decodes one package's files and renders — null when decode fails. */
    fun render(pkg: PaintingPackage, progress: Double): Bitmap? {
        val final = BitmapFactory.decodeFile(pkg.finalFile.path) ?: return null
        val under = BitmapFactory.decodeFile(pkg.underdrawingFile.path) ?: return null
        val map = BitmapFactory.decodeFile(pkg.revealMapFile.path) ?: return null
        return render(underdrawing = under, final = final, revealMap = map, progress = progress)
    }

    private fun scaledTo(bitmap: Bitmap, width: Int, height: Int): Bitmap =
        if (bitmap.width == width && bitmap.height == height) {
            bitmap
        } else {
            Bitmap.createScaledBitmap(bitmap, width, height, true)
        }
}

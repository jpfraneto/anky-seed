package inc.anky.android.ui.lazure

import android.graphics.Bitmap
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithCache
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import kotlin.math.ceil

/**
 * Deterministic RNG so the grain never shimmers between frames.
 * Exact port of the iOS `LazureSeededRandom` (a 64-bit LCG with
 * Knuth's MMIX constants, taking 24 bits above bit 33).
 */
class LazureSeededRandom(seed: Long) {
    private var state: ULong = seed.toULong()

    /** Next value in `[0, 1]`. */
    fun next(): Float {
        state = state * 6364136223846793005uL + 1442695040888963407uL
        return ((state shr 33) and 0xFFFFFFuL).toFloat() / 0xFFFFFF.toFloat()
    }
}

/**
 * Real watercolor paper has tooth — tiny valleys where pigment pools.
 * A whisper of ink speckle (max ~3% alpha) multiplied over every wash
 * kills the "digital gradient" smoothness that would betray the illusion.
 *
 * Port of the iOS `PaperGrain` view: the same 3dp cell walk with the
 * same seeded LCG (seed 888), cells kept when the draw exceeds 0.72,
 * alpha `(v - 0.72) * 0.11`, composited with multiply.
 *
 * Implementation note: where iOS re-runs its `Canvas` walk every frame,
 * here the speckle is rasterized once into a one-pixel-per-cell bitmap
 * (cached until the size changes) and drawn scaled with
 * [FilterQuality.None], so each frame costs a single `drawImage`.
 */
fun Modifier.paperGrain(seed: Long = 888L): Modifier = drawWithCache {
    val cell = GRAIN_CELL_DP.dp.toPx()
    val columns = ceil(size.width / cell).toInt().coerceAtLeast(1)
    val rows = ceil(size.height / cell).toInt().coerceAtLeast(1)
    val bitmap = buildGrainBitmap(columns, rows, seed)
    onDrawWithContent {
        drawContent()
        drawImage(
            image = bitmap,
            srcOffset = IntOffset.Zero,
            srcSize = IntSize(columns, rows),
            dstOffset = IntOffset.Zero,
            dstSize = IntSize(
                (columns * cell).toInt(),
                (rows * cell).toInt(),
            ),
            blendMode = BlendMode.Multiply,
            filterQuality = FilterQuality.None,
        )
    }
}

/** The tooth of the sheet as a standalone overlay layer. */
@Composable
fun PaperGrain(modifier: Modifier = Modifier, seed: Long = 888L) {
    Box(modifier.fillMaxSize().paperGrain(seed))
}

private const val GRAIN_CELL_DP = 3

private fun buildGrainBitmap(columns: Int, rows: Int, seed: Long): ImageBitmap {
    val rng = LazureSeededRandom(seed)
    val ink = LazurePigments.ankyInk
    val inkRgb = ink.copy(alpha = 1f).toArgb() and 0x00FFFFFF
    val pixels = IntArray(columns * rows)
    // Column-major walk, exactly like the iOS stride loops, so the
    // speckle pattern matches the iOS sheet for the same seed.
    for (x in 0 until columns) {
        for (y in 0 until rows) {
            val v = rng.next()
            if (v <= 0.72f) continue
            val alpha = ((v - 0.72f) * 0.11f).coerceIn(0f, 1f)
            pixels[y * columns + x] = ((alpha * 255f).toInt() shl 24) or inkRgb
        }
    }
    val bitmap = Bitmap.createBitmap(columns, rows, Bitmap.Config.ARGB_8888)
    bitmap.setPixels(pixels, 0, columns, 0, 0, columns, rows)
    return bitmap.asImageBitmap()
}

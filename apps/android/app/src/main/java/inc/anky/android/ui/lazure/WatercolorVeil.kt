package inc.anky.android.ui.lazure

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlin.math.PI
import kotlin.math.floor
import kotlin.math.sin

/**
 * The two registers of the veil — port of `WatercolorVeilView.Register`.
 */
enum class WatercolorVeilRegister {
    /** Gate / reflection loading: pale morning pastel. */
    Pale,

    /** Ceremony waiting: candlelit darkness, never black. */
    Aubergine;

    internal val veilColors: List<Color>
        get() = when (this) {
            Pale -> listOf(
                LazurePigments.ankyRose,
                LazurePigments.ankyViolet,
                LazurePigments.ankyGoldLight,
                LazurePigments.ankyApricot,
            )
            Aubergine -> listOf(
                LazurePigments.ankyViolet,
                LazurePigments.ankyMadder,
                LazurePigments.ankyGold,
                LazurePigments.ankyRose,
            )
        }

    internal val textColor: Color
        get() = when (this) {
            Pale -> LazurePigments.ankyInkSoft
            Aubergine -> LazurePigments.ankyPaperDeep.copy(alpha = 0.85f)
        }
}

/**
 * The Waldorf/Steiner loading state: soft watercolor veils breathing and
 * blooming across parchment. No spinner, ever. Built once, reused for the
 * reflection wait, the painting-generation wait, and the [VeiledFeature]
 * mist.
 *
 * Exact port of `WatercolorVeilView`: four blooms per register, each with
 * `breathe = 0.5 + 0.5 sin(2πφ + 1.7s)`, drifting centers derived from
 * fractional multiples of the breath phase, radius `w(0.34 + 0.18b)`,
 * and a radial fade from `alpha 0.16 + 0.10b` to clear.
 *
 * Purely decorative and non-interactive; layer it over paper or a wall.
 */
@Composable
fun WatercolorVeil(
    modifier: Modifier = Modifier,
    message: String? = null,
    register: WatercolorVeilRegister = WatercolorVeilRegister.Pale,
) {
    val phase by rememberBreathPhase()
    Box(modifier.fillMaxSize()) {
        Box(
            Modifier
                .fillMaxSize()
                .drawBehind {
                    val p = phase
                    register.veilColors.forEachIndexed { index, color ->
                        val seed = index.toFloat()
                        val breathe = 0.5f + 0.5f * sin(p * 2f * PI.toFloat() + seed * 1.7f)
                        val x = size.width * (0.22f + 0.56f * fract(seed * 0.37f + p * 0.05f))
                        val y = size.height * (0.25f + 0.5f * fract(seed * 0.61f - p * 0.03f))
                        val radius = size.width * (0.34f + 0.18f * breathe)
                        if (radius <= 0f) return@forEachIndexed
                        val bloom = color.copy(alpha = 0.16f + 0.10f * breathe)
                        drawCircle(
                            brush = Brush.radialGradient(
                                colors = listOf(bloom, color.copy(alpha = 0f)),
                                center = Offset(x, y),
                                radius = radius,
                            ),
                            radius = radius,
                            center = Offset(x, y),
                        )
                    }
                },
        )

        if (message != null) {
            Text(
                text = message,
                fontFamily = FontFamily.Serif,
                fontSize = 15.sp,
                color = register.textColor,
                textAlign = TextAlign.Center,
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .padding(bottom = 64.dp),
            )
        }
    }
}

private fun fract(value: Float): Float = value - floor(value)

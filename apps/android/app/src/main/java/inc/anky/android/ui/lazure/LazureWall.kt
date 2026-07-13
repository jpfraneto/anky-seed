package inc.anky.android.ui.lazure

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp

/**
 * The mood of the wall — which pigments enter from above, the middle,
 * and below. Port of `LazureWall.Mood` in `AnkyLazure.swift`.
 */
@Immutable
sealed interface LazureMood {

    /** Apricot & gold entering from above (default). */
    data object Dawn : LazureMood

    /** Violet-forward, for evening sessions. */
    data object Dusk : LazureMood

    /** Tinted toward a kingdom pigment. */
    data class Kingdom(val pigment: Color) : LazureMood

    /** (top, mid, low) pigments, exactly as iOS maps them. */
    val pigments: Triple<Color, Color, Color>
        get() = when (this) {
            Dawn -> Triple(LazurePigments.ankyApricot, LazurePigments.ankyGoldLight, LazurePigments.ankyViolet)
            Dusk -> Triple(LazurePigments.ankyViolet, LazurePigments.ankyRose, LazurePigments.ankySlate)
            is Kingdom -> Triple(pigment, LazurePigments.ankyGoldLight, LazurePigments.ankyViolet)
        }
}

/**
 * The foundational surface of every screen: paper, four overlapping
 * radial washes whose centers drift on the 8-second breath, and the
 * tooth of the sheet over everything.
 *
 * This ports the iOS radial-wash path of `LazureWall` (the iOS 16/17
 * fallback, which is the same weather as the iOS 18 mesh, softer):
 * warmth always enters from above, sage hides at the left, the low
 * pigment pools at the bottom, rose blushes at the right edge.
 *
 * Purely decorative: place it as the first child of a full-screen `Box`;
 * it takes no touch input and carries no semantics.
 */
@Composable
fun LazureWall(
    mood: LazureMood = LazureMood.Dawn,
    modifier: Modifier = Modifier,
) {
    val phase by rememberBreathPhase()
    val (top, mid, low) = mood.pigments
    Box(
        modifier
            .fillMaxSize()
            .drawBehind {
                // Reading `phase` here (not in composition) keeps the
                // breath a draw-only invalidation.
                val drift = 0.04f * (phase - 0.5f) * 2f // ±0.04 — felt, not seen

                // Pigment sits ON paper.
                drawRect(LazurePigments.ankyPaper)

                // Warmth from above.
                drawRect(
                    Brush.radialGradient(
                        colors = listOf(
                            mid.copy(alpha = 0.65f),
                            top.copy(alpha = 0.35f),
                            top.copy(alpha = 0f),
                        ),
                        center = Offset(size.width * (0.5f + drift), 0f),
                        radius = 480.dp.toPx(),
                    ),
                )
                // Sage hiding at the left.
                drawRect(
                    Brush.radialGradient(
                        colors = listOf(
                            LazurePigments.ankySage.copy(alpha = 0.22f),
                            LazurePigments.ankySage.copy(alpha = 0f),
                        ),
                        center = Offset(0f, size.height * (0.55f - drift)),
                        radius = 380.dp.toPx(),
                    ),
                )
                // The low pigment pooling below.
                drawRect(
                    Brush.radialGradient(
                        colors = listOf(
                            low.copy(alpha = 0.42f),
                            LazurePigments.ankySlate.copy(alpha = 0.18f),
                            LazurePigments.ankySlate.copy(alpha = 0f),
                        ),
                        center = Offset(size.width * (0.5f - drift), size.height * 1.05f),
                        radius = 520.dp.toPx(),
                    ),
                )
                // Rose blushing at the right edge.
                drawRect(
                    Brush.radialGradient(
                        colors = listOf(
                            LazurePigments.ankyRose.copy(alpha = 0.22f),
                            LazurePigments.ankyRose.copy(alpha = 0f),
                        ),
                        center = Offset(size.width, size.height * (0.5f + drift)),
                        radius = 340.dp.toPx(),
                    ),
                )
            }
            .paperGrain(),
    )
}

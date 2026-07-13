package inc.anky.android.ui.lazure

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.ProvideTextStyle
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp

/** Capsule, like the iOS button silhouette. */
private val CapsuleShape = RoundedCornerShape(percent = 50)

/**
 * The primary action is the golden thread Anky pulls from the sky.
 * It glows gently on the 8s breath while idle — an invitation, not a
 * demand. Port of iOS `ThreadButtonStyle`.
 *
 * Fidelity notes:
 *  - The iOS glow is a gold drop shadow whose radius and opacity ride the
 *    breath (`0.25 + 0.15p`, radius `10 + 6p`, y offset 3). Android's
 *    elevation shadows cannot breathe, so the glow is drawn behind the
 *    capsule as a capsule-shaped radial halo with the same alpha/spread
 *    arithmetic.
 *  - Press feedback is the iOS scale-to-0.97 over 150ms; no ripple —
 *    the lazure world has no flashes.
 */
@Composable
fun ThreadButton(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    content: @Composable RowScope.() -> Unit,
) {
    val interactionSource = remember { MutableInteractionSource() }
    val pressed by interactionSource.collectIsPressedAsState()
    val pressScale by animateFloatAsState(
        targetValue = if (pressed) 0.97f else 1f,
        animationSpec = tween(durationMillis = 150),
        label = "threadButtonPress",
    )
    val phase by rememberBreathPhase()

    Row(
        modifier
            .graphicsLayer {
                scaleX = pressScale
                scaleY = pressScale
                alpha = if (enabled) 1f else 0.5f
            }
            .drawBehind {
                val p = phase
                val glow = LazurePigments.ankyGold.copy(alpha = 0.25f + 0.15f * p)
                val spread = (10.dp.toPx() + 6.dp.toPx() * p)
                val radius = size.height / 2f + spread
                val center = Offset(size.width / 2f, size.height / 2f + 3.dp.toPx())
                // Stretch the halo horizontally so it hugs the capsule.
                scale(scaleX = size.width / size.height, scaleY = 1f, pivot = center) {
                    drawCircle(
                        brush = Brush.radialGradient(
                            colors = listOf(glow, glow.copy(alpha = 0f)),
                            center = center,
                            radius = radius,
                        ),
                        radius = radius,
                        center = center,
                    )
                }
            }
            .clip(CapsuleShape)
            .background(
                Brush.verticalGradient(
                    colors = listOf(LazurePigments.ankyGoldLight, LazurePigments.ankyGold),
                ),
            )
            .border(0.5.dp, LazurePigments.ankyInk.copy(alpha = 0.10f), CapsuleShape)
            .clickable(
                interactionSource = interactionSource,
                indication = null,
                enabled = enabled,
                role = Role.Button,
                onClick = onClick,
            )
            .padding(horizontal = 28.dp, vertical = 15.dp),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        CompositionLocalProvider(LocalContentColor provides LazurePigments.ankyInk) {
            ProvideTextStyle(LazureType.ankyAction) { content() }
        }
    }
}

/** Text convenience for the common case. */
@Composable
fun ThreadButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
) {
    ThreadButton(onClick = onClick, modifier = modifier, enabled = enabled) {
        Text(text)
    }
}

/**
 * Secondary actions are quieter washes of slate.
 * Port of iOS `WashButtonStyle`: slate 0.18 -> violet 0.14 vertical wash,
 * hairline edge, same press scale, no glow.
 */
@Composable
fun WashButton(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    content: @Composable RowScope.() -> Unit,
) {
    val interactionSource = remember { MutableInteractionSource() }
    val pressed by interactionSource.collectIsPressedAsState()
    val pressScale by animateFloatAsState(
        targetValue = if (pressed) 0.97f else 1f,
        animationSpec = tween(durationMillis = 150),
        label = "washButtonPress",
    )

    Row(
        modifier
            .graphicsLayer {
                scaleX = pressScale
                scaleY = pressScale
                alpha = if (enabled) 1f else 0.5f
            }
            .clip(CapsuleShape)
            .background(
                Brush.verticalGradient(
                    colors = listOf(
                        LazurePigments.ankySlate.copy(alpha = 0.18f),
                        LazurePigments.ankyViolet.copy(alpha = 0.14f),
                    ),
                ),
            )
            .border(0.5.dp, LazurePigments.ankyInk.copy(alpha = 0.10f), CapsuleShape)
            .clickable(
                interactionSource = interactionSource,
                indication = null,
                enabled = enabled,
                role = Role.Button,
                onClick = onClick,
            )
            .padding(horizontal = 28.dp, vertical = 15.dp),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        CompositionLocalProvider(LocalContentColor provides LazurePigments.ankyInk) {
            ProvideTextStyle(LazureType.ankyAction) { content() }
        }
    }
}

/** Text convenience for the common case. */
@Composable
fun WashButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
) {
    WashButton(onClick = onClick, modifier = modifier, enabled = enabled) {
        Text(text)
    }
}

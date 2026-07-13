package inc.anky.android.ui.lazure

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/** The one card silhouette of the lazure world. */
internal val VeilShape = RoundedCornerShape(28.dp)

/**
 * A card is not a box sitting ON the wall — it is one more translucent
 * veil of pigment laid over it. The wall's colors bleed through.
 * The edge is precise but subtle: a half-dp line of the ink itself,
 * barely there, like the dry rim a wash leaves when it settles.
 *
 * Port of the iOS `VeilCard`. iOS backs the wash with
 * `.ultraThinMaterial`; Android has no live-blur material at this layer,
 * so a translucent paper underlay stands in (the gradient wash on top is
 * identical: `tint` at 0.80 -> 0.55, top-leading to bottom-trailing).
 *
 * Rule 3: the shadow is violet air, not a black hole. (Shadow tint
 * requires API 28+; below that the platform draws its plain soft shadow.)
 */
@Composable
fun VeilCard(
    modifier: Modifier = Modifier,
    tint: Color = LazurePigments.ankyPaper,
    padding: Dp = 20.dp,
    content: @Composable ColumnScope.() -> Unit,
) {
    Column(
        modifier
            .shadow(
                elevation = 10.dp,
                shape = VeilShape,
                clip = false,
                ambientColor = LazurePigments.ankyViolet,
                spotColor = LazurePigments.ankyViolet,
            )
            .clip(VeilShape)
            // Stand-in for iOS ultraThinMaterial: a pooled-paper underlay.
            .background(LazurePigments.ankyPaperDeep.copy(alpha = 0.35f))
            // Even the card fill is a wash, never flat.
            .background(
                Brush.linearGradient(
                    colors = listOf(tint.copy(alpha = 0.80f), tint.copy(alpha = 0.55f)),
                    start = Offset.Zero,
                    end = Offset.Infinite,
                ),
            )
            // Edge defined by a darker tint of itself, not a border.
            .border(0.5.dp, LazurePigments.hairline, VeilShape)
            .padding(padding),
        content = content,
    )
}

/**
 * A hairline of ink between rows — the pencil rule under a line of
 * handwriting, not a wall between rooms. Port of iOS `LazureDivider`.
 */
@Composable
fun LazureDivider(modifier: Modifier = Modifier) {
    Box(
        modifier
            .fillMaxWidth()
            .height(0.5.dp)
            .background(LazurePigments.hairline),
    )
}

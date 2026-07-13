package inc.anky.android.feature.gate

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import inc.anky.android.core.copy.AnkyCopyRegistry
import inc.anky.android.core.gate.AdaptiveTargetOffer
import inc.anky.android.ui.lazure.AnkySunGlyph
import inc.anky.android.ui.lazure.LazureMood
import inc.anky.android.ui.lazure.LazurePigments
import inc.anky.android.ui.lazure.LazureWall
import inc.anky.android.ui.lazure.WatercolorVeil
import inc.anky.android.ui.lazure.WatercolorVeilRegister

/**
 * Phase-2 §1 — port of iOS `AdaptiveTargetOfferView`: after two consecutive
 * missed days, one gentle offer to walk with a smaller target for a while.
 * Pastel register, exactly two choices — never a badge, never a nag, never
 * shown twice per episode (the caller owns `AdaptiveTargetOfferStore`).
 *
 * Deviation: the iOS center is the shy-listening Anky sprite; the sun glyph
 * holds the spot until the sprites are ported.
 */
@Composable
fun AdaptiveTargetOfferCard(
    offer: AdaptiveTargetOffer,
    onLower: () -> Unit,
    onKeep: () -> Unit,
) {
    Box(Modifier.fillMaxSize()) {
        LazureWall(mood = LazureMood.Dawn)
        WatercolorVeil(register = WatercolorVeilRegister.Pale)

        Column(
            modifier = Modifier.fillMaxSize(),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(32.dp),
        ) {
            Spacer(Modifier.weight(1f))

            AnkySunGlyph(size = 96.dp)

            Text(
                text = AnkyCopyRegistry.adaptiveOfferLine(
                    targetMinutes = offer.currentTargetMinutes,
                    suggestedMinutes = offer.suggestedTargetMinutes,
                ),
                fontFamily = FontFamily.Serif,
                fontSize = 21.sp,
                lineHeight = 29.sp,
                color = LazurePigments.ankyInk,
                textAlign = TextAlign.Center,
                modifier = Modifier.padding(horizontal = 44.dp),
            )

            Spacer(Modifier.weight(1f))

            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 40.dp)
                    .padding(bottom = 56.dp),
                verticalArrangement = Arrangement.spacedBy(14.dp),
            ) {
                OfferChoice(
                    text = AnkyCopyRegistry.adaptiveOfferLower(
                        suggestedMinutes = offer.suggestedTargetMinutes,
                    ),
                    filled = true,
                    onClick = onLower,
                )
                OfferChoice(
                    text = AnkyCopyRegistry.adaptiveOfferKeep(
                        targetMinutes = offer.currentTargetMinutes,
                    ),
                    filled = false,
                    onClick = onKeep,
                )
            }
        }
    }
}

@Composable
private fun OfferChoice(
    text: String,
    filled: Boolean,
    onClick: () -> Unit,
) {
    val capsule = RoundedCornerShape(percent = 50)
    val base = Modifier
        .fillMaxWidth()
        .clip(capsule)
    val decorated = if (filled) {
        base.background(LazurePigments.ankyGoldLight.copy(alpha = 0.42f))
    } else {
        base.border(1.dp, LazurePigments.ankyInkSoft.copy(alpha = 0.28f), capsule)
    }
    Box(
        modifier = decorated
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
                role = Role.Button,
                onClick = onClick,
            ),
        contentAlignment = Alignment.Center,
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Spacer(Modifier.height(15.dp))
            Text(
                text = text,
                fontFamily = FontFamily.Serif,
                fontSize = 17.sp,
                fontWeight = if (filled) FontWeight.Medium else FontWeight.Normal,
                color = if (filled) LazurePigments.ankyInk else LazurePigments.ankyInkSoft,
            )
            Spacer(Modifier.height(15.dp))
        }
    }
}

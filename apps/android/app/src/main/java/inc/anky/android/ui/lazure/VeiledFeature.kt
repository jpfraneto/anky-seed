package inc.anky.android.ui.lazure

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * One treatment for everything the free tier stands next to: the feature's
 * real UI rendered beneath a soft parchment mist, the small spiral sun (no
 * padlocks, no red, never pure black), one quiet line, and the whole
 * surface one tap from the paywall. It must read as *not yet* — the thing
 * is really there, breathing under the veil — never as *denied*.
 *
 * Port of iOS `VeiledFeature` (phase-3 §3). Differences kept deliberate:
 *  - [message] must arrive already localized (iOS routes through
 *    `AnkyLocalization.ui`).
 *  - iOS fires `AnkyHaptics.light()` and `AnkyFunnel.report(veilTapped,
 *    origin: surface)` inside the tap; here the caller does both in
 *    [onTap] — [surface] is carried so call sites keep the funnel tag
 *    ("reflection", "ceremony", "journey") next to the veil.
 *
 * @param surface Funnel tag for `veil_tapped {surface}`.
 */
@Composable
fun VeiledFeature(
    surface: String,
    message: String,
    onTap: () -> Unit,
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit,
) {
    @Suppress("UNUSED_EXPRESSION")
    surface // retained for parity with the iOS API; consumed by the caller's funnel report.
    val interactionSource = remember { MutableInteractionSource() }
    Box(
        modifier
            .clip(VeilShape)
            .border(0.5.dp, LazurePigments.hairline, VeilShape),
        contentAlignment = Alignment.Center,
    ) {
        content()

        // Parchment mist: a paper wash so the feature stays visible
        // but restful, with the breathing watercolor over it.
        Box(
            Modifier
                .matchParentSize()
                .background(LazurePigments.ankyPaper.copy(alpha = 0.62f)),
        )
        WatercolorVeil(
            register = WatercolorVeilRegister.Pale,
            modifier = Modifier
                .matchParentSize()
                .alpha(0.8f),
        )

        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(12.dp),
            modifier = Modifier.padding(horizontal = 28.dp, vertical = 20.dp),
        ) {
            AnkySunGlyph(size = 30.dp, color = LazurePigments.ankyGold)
            Text(
                text = message,
                style = TextStyle(
                    fontFamily = FontFamily.Serif,
                    fontStyle = FontStyle.Italic,
                    fontSize = 15.sp,
                    lineHeight = 22.sp,
                    color = LazurePigments.ankyInkSoft,
                    textAlign = TextAlign.Center,
                ),
            )
        }

        // Topmost: one quiet tap for the whole surface. Sits above the
        // content so nothing beneath the veil is interactive (the iOS
        // content is `allowsHitTesting(false)`).
        Box(
            Modifier
                .matchParentSize()
                .clickable(
                    interactionSource = interactionSource,
                    indication = null,
                    role = Role.Button,
                    onClickLabel = message,
                    onClick = onTap,
                ),
        )
    }
}

/**
 * The shape of a reflection that exists but is not yet seen: a serif title
 * stroke and a few quiet body lines. Rendered beneath the reflection veil —
 * real enough to be longed for, abstract enough to promise nothing false.
 *
 * Port of iOS `ReflectionGhost` (title bar 172x20 violet@0.35, four
 * 11dp lines of ink@0.18, the last 190dp wide, on paper@0.5).
 */
@Composable
fun ReflectionGhost(modifier: Modifier = Modifier) {
    Column(
        verticalArrangement = Arrangement.spacedBy(14.dp),
        modifier = modifier
            .fillMaxWidth()
            .clip(VeilShape)
            .background(LazurePigments.ankyPaper.copy(alpha = 0.5f))
            .padding(24.dp),
    ) {
        Box(
            Modifier
                .padding(bottom = 4.dp)
                .size(width = 172.dp, height = 20.dp)
                .clip(RoundedCornerShape(4.dp))
                .background(LazurePigments.ankyViolet.copy(alpha = 0.35f)),
        )
        repeat(4) { index ->
            Box(
                Modifier
                    .height(11.dp)
                    .then(if (index == 3) Modifier.width(190.dp) else Modifier.fillMaxWidth())
                    .clip(RoundedCornerShape(3.dp))
                    .background(LazurePigments.ankyInk.copy(alpha = 0.18f)),
            )
        }
    }
}

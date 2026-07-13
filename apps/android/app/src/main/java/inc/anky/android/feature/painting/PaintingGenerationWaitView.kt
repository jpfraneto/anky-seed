package inc.anky.android.feature.painting

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import inc.anky.android.R
import inc.anky.android.core.copy.AnkyCopyRegistry
import inc.anky.android.ui.lazure.LazurePigments
import inc.anky.android.ui.lazure.WatercolorVeil
import inc.anky.android.ui.lazure.WatercolorVeilRegister

/**
 * The waiting room while anky paints: aubergine watercolor breathing, the
 * registry's "Anky is painting…" line, and up to three excerpts from the
 * chapter the painting is distilled from (picked by LevelTriggerTuning's
 * excerpt spread — the caller passes them in via
 * `coordinator.paintingGenerationExcerpts()`).
 *
 * Port of iOS `PaintingGenerationWaitView` (UnveilCeremonyView.swift).
 * Purely decorative — takes no touch input.
 */
@Composable
fun PaintingGenerationWaitView(
    excerpts: List<String>,
    modifier: Modifier = Modifier,
) {
    Box(modifier.fillMaxSize().clearAndSetSemantics { }) {
        WatercolorVeil(register = WatercolorVeilRegister.Aubergine)

        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(18.dp),
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 28.dp, vertical = 56.dp),
        ) {
            Spacer(Modifier.weight(1f))

            Text(
                text = AnkyCopyRegistry.generationWait,
                style = TextStyle(
                    fontFamily = FontFamily.Serif,
                    fontWeight = FontWeight.Medium,
                    fontSize = 17.sp,
                ),
                color = LazurePigments.ankyGoldLight,
            )

            if (excerpts.isNotEmpty()) {
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                    modifier = Modifier.widthIn(max = 360.dp),
                ) {
                    Text(
                        text = stringResource(R.string.ceremony_from_your_writing).uppercase(),
                        style = TextStyle(
                            fontFamily = FontFamily.Serif,
                            fontWeight = FontWeight.SemiBold,
                            fontSize = 11.sp,
                            letterSpacing = 2.8.sp,
                        ),
                        color = LazurePigments.ankyGold.copy(alpha = 0.78f),
                    )

                    Column(
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        excerpts.take(3).forEachIndexed { index, excerpt ->
                            val leading = index == 0
                            Text(
                                text = "“$excerpt”",
                                style = TextStyle(
                                    fontFamily = FontFamily.Serif,
                                    fontSize = if (leading) 17.sp else 15.sp,
                                    lineHeight = if (leading) 25.sp else 23.sp,
                                    textAlign = TextAlign.Center,
                                ),
                                color = LazurePigments.ankyPaperDeep.copy(alpha = if (leading) 0.92f else 0.72f),
                                modifier = Modifier
                                    .background(
                                        LazurePigments.ankyInk.copy(alpha = if (leading) 0.18f else 0.10f),
                                        RoundedCornerShape(18.dp),
                                    )
                                    .border(
                                        0.6.dp,
                                        LazurePigments.ankyGold.copy(alpha = if (leading) 0.28f else 0.16f),
                                        RoundedCornerShape(18.dp),
                                    )
                                    .padding(
                                        horizontal = 22.dp,
                                        vertical = if (leading) 15.dp else 12.dp,
                                    ),
                            )
                        }
                    }
                }
            }

            Spacer(Modifier.weight(1f))
        }
    }
}

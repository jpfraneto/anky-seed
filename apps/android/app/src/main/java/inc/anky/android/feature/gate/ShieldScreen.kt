package inc.anky.android.feature.gate

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import inc.anky.android.R
import inc.anky.android.core.copy.AnkyCopyRegistry
import inc.anky.android.ui.lazure.ThreadButton

/**
 * The shield face — a direct port of the iOS `ShieldConfigurationExtension`
 * palette and copy: near-black warm background, the door icon, a gold
 * headline that rotates gently by day (exhausted variant when the day's
 * Quick Passes are spent), "{App} is waiting behind the door.", the
 * quick-pass line, and two exits: Write ⊙ (golden thread) and the quiet
 * emergency link.
 */
private object ShieldPalette {
    val background = Color(red = 0.08f, green = 0.055f, blue = 0.045f)
    val title = Color(red = 0.96f, green = 0.86f, blue = 0.68f)
    val subtitle = Color(red = 0.78f, green = 0.67f, blue = 0.58f)
}

@Composable
fun ShieldScreen(
    appLabel: String?,
    quickPassesRemaining: Int,
    onWriteRequested: () -> Unit,
    onEmergencyRequested: () -> Unit,
) {
    val headline = remember(quickPassesRemaining) {
        AnkyCopyRegistry.gateHeadline(passesRemaining = quickPassesRemaining)
    }

    Box(
        Modifier
            .fillMaxSize()
            .background(ShieldPalette.background)
            .statusBarsPadding()
            .navigationBarsPadding(),
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 40.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            Spacer(Modifier.weight(1f))

            Image(
                painter = painterResource(R.drawable.anky_shield_door_icon),
                contentDescription = null,
                modifier = Modifier.size(132.dp),
            )

            Spacer(Modifier.height(30.dp))

            Text(
                text = headline,
                fontFamily = FontFamily.Serif,
                fontWeight = FontWeight.Medium,
                fontSize = 26.sp,
                lineHeight = 34.sp,
                color = ShieldPalette.title,
                textAlign = TextAlign.Center,
            )

            Spacer(Modifier.height(16.dp))

            Text(
                text = AnkyCopyRegistry.gateFooter(appName = appLabel),
                fontFamily = FontFamily.Serif,
                fontSize = 15.sp,
                lineHeight = 22.sp,
                color = ShieldPalette.subtitle,
                textAlign = TextAlign.Center,
            )

            if (quickPassesRemaining > 0) {
                Spacer(Modifier.height(10.dp))
                Text(
                    text = AnkyCopyRegistry.gatePassLine(passesRemaining = quickPassesRemaining),
                    fontSize = 13.sp,
                    color = ShieldPalette.subtitle.copy(alpha = 0.82f),
                    textAlign = TextAlign.Center,
                )
            }

            Spacer(Modifier.weight(1f))

            ThreadButton(
                text = stringResource(R.string.gate_shield_write_button),
                onClick = onWriteRequested,
                modifier = Modifier.fillMaxWidth(),
            )

            Spacer(Modifier.height(18.dp))

            Text(
                text = AnkyCopyRegistry.emergencyLink,
                fontSize = 14.sp,
                fontWeight = FontWeight.Medium,
                color = ShieldPalette.subtitle.copy(alpha = 0.82f),
                textAlign = TextAlign.Center,
                modifier = Modifier
                    .clickable(
                        interactionSource = remember { MutableInteractionSource() },
                        indication = null,
                        onClick = onEmergencyRequested,
                    )
                    .padding(horizontal = 16.dp, vertical = 8.dp),
            )

            Spacer(Modifier.height(40.dp))
        }
    }
}

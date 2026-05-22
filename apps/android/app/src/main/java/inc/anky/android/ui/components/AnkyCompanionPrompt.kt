package inc.anky.android.ui.components

import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import inc.anky.android.R
import inc.anky.android.ui.theme.AnkyColors
import inc.anky.android.ui.theme.AnkyType

@Composable
fun AnkyCompanionPrompt(
    title: String,
    message: String,
    actionLabel: String,
    isLoading: Boolean,
    enabled: Boolean,
    onAction: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val motion by rememberInfiniteTransition(label = "anky-companion-motion").animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(durationMillis = 1800),
            repeatMode = RepeatMode.Reverse,
        ),
        label = "anky-companion-motion-value",
    )

    Row(
        modifier = modifier
            .fillMaxWidth()
            .heightIn(min = 86.dp)
            .clip(RoundedCornerShape(8.dp))
            .background(Color.Black.copy(alpha = 0.24f))
            .border(1.dp, AnkyColors.Gold.copy(alpha = 0.18f), RoundedCornerShape(8.dp))
            .padding(12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Box(
            modifier = Modifier.size(58.dp),
            contentAlignment = Alignment.Center,
        ) {
            Box(
                Modifier
                    .matchParentSize()
                    .clip(CircleShape)
                    .background(AnkyColors.Gold.copy(alpha = 0.07f + motion * 0.05f)),
            )
            Image(
                painter = painterResource(R.drawable.anky040),
                contentDescription = null,
                modifier = Modifier
                    .size(48.dp)
                    .graphicsLayer {
                        translationY = (-2f + motion * 4f)
                        rotationZ = -1.6f + motion * 3.2f
                    }
                    .alpha(0.92f),
            )
        }
        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Text(
                title.lowercase(),
                style = AnkyType.Body.copy(fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = AnkyColors.Paper),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                message,
                style = AnkyType.Caption.copy(fontSize = 12.sp, color = AnkyColors.Paper.copy(alpha = 0.62f)),
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
        }
        Button(
            onClick = onAction,
            enabled = enabled,
            shape = RoundedCornerShape(8.dp),
            colors = ButtonDefaults.buttonColors(
                containerColor = AnkyColors.Gold,
                contentColor = AnkyColors.Ink,
                disabledContainerColor = AnkyColors.Gold.copy(alpha = 0.46f),
                disabledContentColor = AnkyColors.Ink.copy(alpha = 0.62f),
            ),
            modifier = Modifier.heightIn(min = 40.dp),
        ) {
            if (isLoading) {
                CircularProgressIndicator(
                    color = AnkyColors.Ink,
                    strokeWidth = 2.dp,
                    modifier = Modifier.size(14.dp),
                )
            } else {
                Icon(
                    imageVector = Icons.Filled.AutoAwesome,
                    contentDescription = null,
                    modifier = Modifier.size(14.dp),
                )
            }
            Text(
                actionLabel,
                style = AnkyType.Caption.copy(fontSize = 12.sp, fontWeight = FontWeight.Bold, color = AnkyColors.Ink),
                maxLines = 1,
            )
        }
    }
}

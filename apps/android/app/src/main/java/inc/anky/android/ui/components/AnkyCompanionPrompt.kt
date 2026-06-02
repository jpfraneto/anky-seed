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
import androidx.compose.material3.TextButton
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

data class AnkyChatAction(
    val title: String,
    val isPrimary: Boolean = false,
    val subtitle: String? = null,
    val badge: String? = null,
    val action: () -> Unit,
)

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

@Composable
fun AnkyConversationPrompt(
    message: String,
    actions: List<AnkyChatAction> = emptyList(),
    steps: List<String> = emptyList(),
    modifier: Modifier = Modifier,
    isThinking: Boolean = false,
    onClose: (() -> Unit)? = null,
) {
    Box(modifier = modifier.fillMaxWidth()) {
        DialoguePanel(
            message = message,
            actions = actions.take(4),
            steps = steps.take(4),
            isThinking = isThinking,
            modifier = Modifier.padding(top = 14.dp),
        )
        if (onClose != null) {
            TextButton(
                onClick = onClose,
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .size(32.dp)
                    .clip(CircleShape)
                    .background(Color.Black.copy(alpha = 0.34f))
                    .border(1.dp, AnkyColors.Gold.copy(alpha = 0.26f), CircleShape),
                contentPadding = androidx.compose.foundation.layout.PaddingValues(0.dp),
            ) {
                Text("x", style = AnkyType.Caption.copy(fontSize = 13.sp, color = AnkyColors.GoldSoft))
            }
        }
    }
}

@Composable
private fun DialoguePanel(
    message: String,
    actions: List<AnkyChatAction>,
    steps: List<String>,
    isThinking: Boolean,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(8.dp))
            .background(Color(0xF20C0907))
            .border(1.dp, AnkyColors.Gold.copy(alpha = 0.22f), RoundedCornerShape(8.dp))
            .padding(horizontal = 14.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(
                "anky",
                style = AnkyType.Caption.copy(
                    fontSize = 10.sp,
                    fontWeight = FontWeight.Bold,
                    color = AnkyColors.Gold.copy(alpha = 0.82f),
                ),
            )
            if (isThinking) {
                CircularProgressIndicator(
                    color = AnkyColors.GoldSoft,
                    strokeWidth = 2.dp,
                    modifier = Modifier.size(16.dp),
                )
            }
        }
        Text(
            message.lowercase(),
            style = AnkyType.Mono.copy(fontSize = 15.sp, lineHeight = 20.sp, color = AnkyColors.Paper.copy(alpha = 0.92f)),
        )
        if (steps.isNotEmpty()) {
            Column(verticalArrangement = Arrangement.spacedBy(5.dp)) {
                steps.forEachIndexed { index, step ->
                    Text(
                        "${index + 1}. ${step.lowercase()}",
                        style = AnkyType.Caption.copy(
                            fontSize = 12.sp,
                            fontWeight = FontWeight.SemiBold,
                            color = AnkyColors.GoldSoft.copy(alpha = 0.86f),
                        ),
                    )
                }
            }
        }
        if (actions.isNotEmpty()) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                actions.forEach { chatAction ->
                    TextButton(
                        onClick = chatAction.action,
                        modifier = Modifier
                            .weight(1f)
                            .heightIn(min = if (chatAction.subtitle != null || chatAction.badge != null) 58.dp else 32.dp)
                            .clip(RoundedCornerShape(4.dp))
                            .background(if (chatAction.isPrimary) AnkyColors.GoldSoft else Color.Black.copy(alpha = 0.22f))
                            .border(
                                1.dp,
                                if (chatAction.isPrimary) Color.White.copy(alpha = 0.46f) else AnkyColors.Gold.copy(alpha = 0.34f),
                                RoundedCornerShape(4.dp),
                            ),
                        contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 12.dp),
                    ) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            chatAction.badge?.let { badge ->
                                Text(
                                    badge.lowercase(),
                                    style = AnkyType.Caption.copy(
                                        fontSize = 8.sp,
                                        fontWeight = FontWeight.Bold,
                                        color = if (chatAction.isPrimary) AnkyColors.Ink.copy(alpha = 0.88f) else AnkyColors.GoldSoft,
                                    ),
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis,
                                )
                            }
                            Text(
                                chatAction.title.lowercase(),
                                style = AnkyType.Caption.copy(
                                    fontSize = 12.sp,
                                    fontWeight = FontWeight.Bold,
                                    color = if (chatAction.isPrimary) AnkyColors.Ink.copy(alpha = 0.88f) else AnkyColors.GoldSoft,
                                ),
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                            )
                            chatAction.subtitle?.let { subtitle ->
                                Text(
                                    subtitle.lowercase(),
                                    style = AnkyType.Caption.copy(
                                        fontSize = 10.sp,
                                        fontWeight = FontWeight.SemiBold,
                                        color = if (chatAction.isPrimary) AnkyColors.Ink.copy(alpha = 0.78f) else AnkyColors.GoldSoft,
                                    ),
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis,
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

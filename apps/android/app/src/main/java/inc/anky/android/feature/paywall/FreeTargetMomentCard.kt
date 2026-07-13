package inc.anky.android.feature.paywall

import android.content.SharedPreferences
import android.view.HapticFeedbackConstants
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import inc.anky.android.core.copy.AnkyCopyRegistry
import inc.anky.android.core.subscription.EntitlementStore
import inc.anky.android.ui.lazure.LazurePigments
import inc.anky.android.ui.lazure.LazureType
import inc.anky.android.ui.lazure.ThreadButton

/**
 * The free writer's target moment (decision 2026-07-06, option C):
 * acknowledgment first, the subscriber fact second, the trial as an open
 * door. Dismissible in one tap; when the host still shows the emergency
 * breath, [onEmergency] keeps a free way forward quietly visible.
 *
 * Port of iOS `freeTargetMomentBlock` in `AppRoot.swift`; all copy comes
 * from [AnkyCopyRegistry] (the single source of that voice, like iOS).
 *
 * The trial CTA opens [PaywallSheet] with origin `free_target_moment`
 * right here — the card owns its sheet, the host only supplies the
 * dependencies. Purchase or restore inside the sheet closes it; the
 * surface beneath unveils on its own because entitlement changed.
 */
const val FREE_TARGET_MOMENT_ORIGIN = "free_target_moment"

@Composable
fun FreeTargetMomentCard(
    store: EntitlementStore,
    onDismiss: () -> Unit,
    onShowTerms: () -> Unit,
    onShowPrivacy: () -> Unit,
    modifier: Modifier = Modifier,
    onFunnelEvent: (event: String, origin: String) -> Unit = { _, _ -> },
    subscriptionPreferences: SharedPreferences? = null,
    /** Non-null keeps the emergency-breath link visible (no passes left). */
    onEmergency: (() -> Unit)? = null,
) {
    val view = LocalView.current
    var showsPaywall by remember { mutableStateOf(false) }

    Column(
        verticalArrangement = Arrangement.spacedBy(14.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = modifier.fillMaxWidth().padding(top = 10.dp),
    ) {
        Text(
            text = AnkyCopyRegistry.freeTargetMomentTitle,
            style = LazureType.ankyProse.copy(fontSize = 22.sp, fontWeight = FontWeight.SemiBold),
            color = LazurePigments.ankyInk,
            textAlign = TextAlign.Center,
            modifier = Modifier.fillMaxWidth(),
        )

        Text(
            text = AnkyCopyRegistry.freeTargetMomentLine,
            style = LazureType.ankyProse.copy(fontSize = 15.sp, lineHeight = 21.sp),
            color = LazurePigments.ankyInkSoft,
            textAlign = TextAlign.Center,
            modifier = Modifier.fillMaxWidth(),
        )

        Text(
            text = AnkyCopyRegistry.freeTargetMomentSubscriberLine,
            style = LazureType.ankyProse.copy(fontSize = 15.sp, lineHeight = 21.sp, fontWeight = FontWeight.Medium),
            color = LazurePigments.ankyViolet.copy(alpha = 0.92f),
            textAlign = TextAlign.Center,
            modifier = Modifier.fillMaxWidth(),
        )

        ThreadButton(
            text = AnkyCopyRegistry.freeTargetMomentCTA,
            onClick = {
                view.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
                showsPaywall = true
            },
            modifier = Modifier.fillMaxWidth(),
        )

        if (onEmergency != null) {
            Text(
                text = AnkyCopyRegistry.emergencyLink,
                style = LazureType.ankyCaption.copy(fontSize = 13.sp),
                color = LazurePigments.ankyInkSoft.copy(alpha = 0.75f),
                modifier = Modifier.clickable(
                    interactionSource = remember { MutableInteractionSource() },
                    indication = null,
                    role = Role.Button,
                    onClick = onEmergency,
                ),
            )
        }

        Text(
            text = AnkyCopyRegistry.freeTargetMomentDismiss,
            style = LazureType.ankyCaption.copy(fontSize = 13.sp, fontWeight = FontWeight.Medium),
            color = LazurePigments.ankyInkSoft,
            modifier = Modifier.clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
                role = Role.Button,
                onClick = onDismiss,
            ),
        )
    }

    if (showsPaywall) {
        PaywallSheet(
            store = store,
            origin = FREE_TARGET_MOMENT_ORIGIN,
            onDismiss = { showsPaywall = false },
            onShowTerms = onShowTerms,
            onShowPrivacy = onShowPrivacy,
            onFunnelEvent = onFunnelEvent,
            subscriptionPreferences = subscriptionPreferences,
        )
    }
}

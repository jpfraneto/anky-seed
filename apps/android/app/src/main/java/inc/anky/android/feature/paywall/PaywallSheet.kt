package inc.anky.android.feature.paywall

import android.content.SharedPreferences
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.BottomSheetDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import inc.anky.android.core.subscription.EntitlementStore
import inc.anky.android.ui.lazure.LazureMood
import inc.anky.android.ui.lazure.LazurePigments
import inc.anky.android.ui.lazure.LazureWall

/**
 * The paywall as a presentable sheet (phase-3 §4) — launched from every
 * veil and boundary surface. Same dawn room as the onboarding ask; the
 * sheet dismisses itself on purchase or restore, and the surface beneath
 * unveils on its own because entitlement changed. Nothing is ever locked
 * behind this sheet that wasn't gently visible through its veil.
 *
 * Port of iOS `PaywallSheet` in `Anky/Purchases/PaywallView.swift`.
 * `paywall_shown {origin}` fires through [onFunnelEvent] on the hosted
 * screen's first composition (once, like iOS `onAppear`) — the caller
 * never reports it separately.
 *
 * @param origin funnel tag for `paywall_shown {origin}` — e.g.
 *   "reflection", "ceremony", "journey", "widget", "quick_action",
 *   "free_target_moment".
 * @param onDismiss remove the sheet from composition. Called on swipe/
 *   scrim dismissal and by the paywall's own completion (purchase,
 *   restore, or Done while entitled).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PaywallSheet(
    store: EntitlementStore,
    origin: String,
    onDismiss: () -> Unit,
    onShowTerms: () -> Unit,
    onShowPrivacy: () -> Unit,
    onFunnelEvent: (event: String, origin: String) -> Unit = { _, _ -> },
    subscriptionPreferences: SharedPreferences? = null,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = LazurePigments.ankyPaper,
        contentColor = LazurePigments.ankyInk,
        dragHandle = { BottomSheetDefaults.DragHandle(color = LazurePigments.ankySlate.copy(alpha = 0.5f)) },
    ) {
        Box(modifier = Modifier.fillMaxWidth()) {
            // Behind everything: the same dawn weather as onboarding.
            LazureWall(mood = LazureMood.Dawn, modifier = Modifier.matchParentSize())

            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .verticalScroll(rememberScrollState()),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Spacer(modifier = Modifier.height(44.dp))

                PaywallScreen(
                    store = store,
                    context = PaywallContext.Veil(origin),
                    onCompleted = onDismiss,
                    onShowTerms = onShowTerms,
                    onShowPrivacy = onShowPrivacy,
                    onFunnelEvent = onFunnelEvent,
                    subscriptionPreferences = subscriptionPreferences,
                    modifier = Modifier
                        .padding(horizontal = 30.dp)
                        .widthIn(max = 620.dp),
                )

                Spacer(modifier = Modifier.height(30.dp))
            }
        }
    }
}

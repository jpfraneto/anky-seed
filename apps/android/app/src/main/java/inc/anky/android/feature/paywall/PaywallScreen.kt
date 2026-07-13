package inc.anky.android.feature.paywall

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.content.SharedPreferences
import android.content.res.Resources
import android.view.HapticFeedbackConstants
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import inc.anky.android.R
import inc.anky.android.core.subscription.EntitlementStore
import inc.anky.android.core.subscription.PaywallPressureLedger
import inc.anky.android.ui.lazure.LazurePigments
import inc.anky.android.ui.lazure.LazureType
import inc.anky.android.ui.lazure.ThreadButton
import kotlinx.coroutines.launch

/**
 * The ask. One screen, two prices, no tricks — the trial timeline says
 * exactly what will happen and when, in Anky's voice.
 *
 * Port of iOS `Anky/Purchases/PaywallView.swift`. Painted post-dawn: the
 * host places it over a `LazureWall(Dawn)` so it lives in the same warm
 * room as the journey map. [PaywallContext] changes copy only, never
 * styling — the onboarding and lapsed variants are the same room with
 * different words.
 *
 * Canon guardrails, deliberately structural:
 *  - Switching plans updates only the selector, the payment line, and the
 *    CTA label. Never a sheet, never a discount, never a countdown.
 *  - Purchase failure or cancellation changes nothing on screen beyond
 *    one quiet line. The screen itself is the ask; asking twice in the
 *    same breath is off-canon.
 *
 * Self-contained: purchases need a foreground [Activity] (Play Billing);
 * it is unwrapped from [LocalContext], so the host Activity must be a
 * plain ContextWrapper chain (any ComponentActivity is).
 */
object PaywallDefaults {
    /**
     * QA / Play-review escape hatch: when true, a quiet "later" link
     * advances without purchase. MUST be false before shipping a build.
     * (iOS `PaywallView.paywallIsSkippable`.)
     */
    const val PAYWALL_IS_SKIPPABLE = false
}

@Composable
fun PaywallScreen(
    store: EntitlementStore,
    context: PaywallContext,
    onCompleted: () -> Unit,
    onShowTerms: () -> Unit,
    onShowPrivacy: () -> Unit,
    modifier: Modifier = Modifier,
    /**
     * Best-effort funnel reporting (`paywall_shown` / `trial_started` /
     * `subscribed`, each with [PaywallContext.funnelOrigin]) — wire to the
     * AnkyFunnel adapter. See [PaywallFunnel] for the event names.
     */
    onFunnelEvent: (event: String, origin: String) -> Unit = { _, _ -> },
    /**
     * The subscription prefs file (`anky-subscription`) so the screen can
     * record [PaywallPressureLedger.recordPaywallShown] on appear, exactly
     * like iOS. Null skips the ledger (previews/tests).
     */
    subscriptionPreferences: SharedPreferences? = null,
) {
    val state by store.state.collectAsState()
    val scope = rememberCoroutineScope()
    val view = LocalView.current
    val activity = LocalContext.current.findActivity()

    val selection = remember { PaywallPlanSelection() }
    var isTrialEligible by remember { mutableStateOf(true) }

    // iOS `.task(id: store.packages.count)`: load offerings, then ask the
    // store about trial eligibility once packages exist.
    LaunchedEffect(state.packages.size) {
        store.loadPackages()
        isTrialEligible = store.yearlyTrialEligibility()
    }

    // iOS `.onAppear`: the funnel's paywall_shown {origin} plus the
    // once-per-rolling-week pressure ledger — only when there is an ask.
    LaunchedEffect(Unit) {
        if (!store.state.value.isEntitled) {
            onFunnelEvent(PaywallFunnel.PAYWALL_SHOWN, context.funnelOrigin)
            subscriptionPreferences?.let { PaywallPressureLedger.recordPaywallShown(it) }
        }
    }

    val resources = LocalContext.current.resources

    fun purchaseSelected() {
        if (state.isPurchasing) {
            return
        }
        if (state.isEntitled) {
            onCompleted()
            return
        }
        view.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
        val startedTrialEligible = isTrialEligible
        val plan = selection.plan
        scope.launch {
            store.loadPackages()
            val loaded = store.state.value
            val pkg = if (plan == PaywallPlan.YEARLY) loaded.yearlyPackage else loaded.monthlyPackage
            if (pkg == null) {
                // Offerings unreachable: loadPackages surfaced the line and
                // the retry link. Loaded but missing this plan: say so.
                if (loaded.packages.isNotEmpty()) {
                    store.noteSelectedPackageUnavailable()
                }
                return@launch
            }
            val purchased = store.purchase(pkg, activity)
            if (!purchased) {
                // Cancelled or failed: the screen stays as it is (plus at
                // most one quiet line). No guilt copy, no modal.
                return@launch
            }
            val startedTrial = plan == PaywallPlan.YEARLY && startedTrialEligible
            onFunnelEvent(
                if (startedTrial) PaywallFunnel.TRIAL_STARTED else PaywallFunnel.SUBSCRIBED,
                context.funnelOrigin,
            )
            view.performHapticFeedback(HapticFeedbackConstants.CONFIRM)
            onCompleted()
        }
    }

    fun restore() {
        if (state.isRestoring) {
            return
        }
        view.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
        scope.launch {
            store.restore()
            if (store.state.value.isEntitled) {
                onCompleted()
            }
        }
    }

    Column(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(18.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(
            text = PaywallCopy.title(state, context, isTrialEligible).resolve(resources),
            style = LazureType.ankyTitle,
            color = LazurePigments.ankyInk,
            textAlign = TextAlign.Center,
            modifier = Modifier.fillMaxWidth(),
        )

        Text(
            text = PaywallCopy.voiceLine(state, context).resolve(resources),
            style = LazureType.ankyProse.copy(fontSize = 16.sp, lineHeight = 24.sp, fontStyle = FontStyle.Italic),
            color = LazurePigments.ankyInkSoft,
            textAlign = TextAlign.Center,
            modifier = Modifier.fillMaxWidth(),
        )

        if (!state.isEntitled && isTrialEligible) {
            TrialTimeline(modifier = Modifier.fillMaxWidth().padding(vertical = 2.dp))
        }

        if (!state.isEntitled) {
            PlanSelector(
                selection = selection,
                yearlyTitle = PaywallCopy.yearlyPlanTitle(state, isTrialEligible).resolve(resources),
                yearlyTrailing = PaywallCopy.yearlyWeeklyLine(state).resolve(resources),
                monthlyTitle = PaywallCopy.monthlyPlanTitle(state).resolve(resources),
                onChanged = { view.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK) },
            )
        }

        // Full body legibility, deliberately — never fine print.
        Text(
            text = PaywallCopy.paymentLine(state, selection.plan, isTrialEligible).resolve(resources),
            style = LazureType.ankyProse.copy(fontSize = 16.sp),
            color = LazurePigments.ankyInkSoft,
            textAlign = TextAlign.Center,
            modifier = Modifier.fillMaxWidth(),
        )

        if (!state.isEntitled) {
            state.purchaseErrorLine?.let { QuietLine(it, LazurePigments.ankyMadder.copy(alpha = 0.9f)) }

            // Offline / store-unreachable is a visible state with a way
            // back, never a silently dead buy button.
            if (state.offeringsErrorLine != null && state.packages.isEmpty()) {
                QuietLine(state.offeringsErrorLine!!, LazurePigments.ankyMadder.copy(alpha = 0.9f))
                if (state.isLoadingPackages) {
                    CircularProgressIndicator(
                        color = LazurePigments.ankyInkSoft,
                        strokeWidth = 2.dp,
                        modifier = Modifier.size(18.dp),
                    )
                } else {
                    Text(
                        text = resources.getString(R.string.paywall_try_again),
                        style = LazureType.ankyProse.copy(
                            fontSize = 14.sp,
                            fontWeight = FontWeight.Medium,
                            textDecoration = TextDecoration.Underline,
                        ),
                        color = LazurePigments.ankyGold,
                        modifier = Modifier.clickable(
                            interactionSource = remember { MutableInteractionSource() },
                            indication = null,
                            role = Role.Button,
                        ) {
                            view.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
                            scope.launch {
                                store.loadPackages()
                                isTrialEligible = store.yearlyTrialEligibility()
                            }
                        },
                    )
                }
            }

            state.restoreStatusLine?.let { QuietLine(it, LazurePigments.ankyInkSoft) }
        }

        // CTA — the filled golden thread; a purchase in flight shows a
        // quiet indicator, never a second ask.
        ThreadButton(
            onClick = ::purchaseSelected,
            enabled = !state.isPurchasing,
            modifier = Modifier.fillMaxWidth().padding(top = 6.dp),
        ) {
            if (state.isPurchasing) {
                CircularProgressIndicator(
                    color = LazurePigments.ankyInk,
                    strokeWidth = 2.dp,
                    modifier = Modifier.size(20.dp),
                )
            } else {
                Text(
                    text = PaywallCopy.ctaTitle(state, selection.plan, isTrialEligible).resolve(resources),
                    maxLines = 1,
                )
            }
        }

        PaywallFooter(
            isRestoring = state.isRestoring,
            onRestore = ::restore,
            onShowTerms = onShowTerms,
            onShowPrivacy = onShowPrivacy,
            onSkip = onCompleted,
        )
    }
}

/** One quiet italic line — how failure and status speak on this screen. */
@Composable
private fun QuietLine(text: String, color: androidx.compose.ui.graphics.Color) {
    Text(
        text = text,
        style = LazureType.ankyProse.copy(fontSize = 14.sp, lineHeight = 19.sp, fontStyle = FontStyle.Italic),
        color = color,
        textAlign = TextAlign.Center,
        modifier = Modifier.fillMaxWidth(),
    )
}

/**
 * Three nodes on a hairline gold thread — the same visual grammar as the
 * 8-day map, telling the trial exactly as it will happen. Today's node is
 * filled; the days still to come are outlines.
 */
@Composable
private fun TrialTimeline(modifier: Modifier = Modifier) {
    Column(modifier = modifier) {
        PaywallCopy.trialTimeline.forEachIndexed { index, node ->
            TimelineNode(node = node, isLast = index == PaywallCopy.trialTimeline.lastIndex)
        }
    }
}

@Composable
private fun TimelineNode(node: PaywallTimelineNode, isLast: Boolean) {
    val resources = LocalContext.current.resources
    Row(
        horizontalArrangement = Arrangement.spacedBy(14.dp),
        modifier = Modifier.fillMaxWidth().height(intrinsicSize = androidx.compose.foundation.layout.IntrinsicSize.Min),
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            modifier = Modifier.fillMaxHeight(),
        ) {
            val dot = if (node.isFilled) 12.dp else 11.dp
            Box(
                modifier = Modifier
                    .padding(top = 3.dp)
                    .size(dot)
                    .clip(CircleShape)
                    .background(if (node.isFilled) LazurePigments.ankyGold else androidx.compose.ui.graphics.Color.Transparent)
                    .border(1.dp, LazurePigments.ankyGold, CircleShape),
            )
            if (!isLast) {
                // Hairline, same weight as the 8-day map's LazureDivider.
                Box(
                    modifier = Modifier
                        .width(0.5.dp)
                        .weight(1f)
                        .background(LazurePigments.ankyGold.copy(alpha = 0.5f)),
                )
            }
        }

        Column(verticalArrangement = Arrangement.spacedBy(3.dp), modifier = Modifier.weight(1f)) {
            Text(
                text = resources.getString(node.labelRes).uppercase(),
                style = LazureType.ankyProse.copy(
                    fontSize = 12.sp,
                    fontWeight = FontWeight.SemiBold,
                    letterSpacing = 2.5.sp,
                ),
                color = LazurePigments.ankyMadder.copy(alpha = 0.85f),
            )
            Text(
                text = resources.getString(node.lineRes),
                style = LazureType.ankyProse.copy(fontSize = 15.sp, lineHeight = 21.sp),
                color = LazurePigments.ankyInk,
                modifier = Modifier.padding(bottom = if (isLast) 0.dp else 16.dp),
            )
        }
    }
}

/**
 * Warm cream cards a half-step lighter than the wall. Selection is a gold
 * hairline with a very faint interior wash; unselected is a gray-violet
 * hairline. Tapping updates only the selector, the payment line, and the
 * CTA label.
 */
@Composable
private fun PlanSelector(
    selection: PaywallPlanSelection,
    yearlyTitle: String,
    yearlyTrailing: String,
    monthlyTitle: String,
    onChanged: () -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.fillMaxWidth()) {
        PlanOption(
            title = yearlyTitle,
            trailing = yearlyTrailing,
            isSelected = selection.plan == PaywallPlan.YEARLY,
            onTap = { if (selection.select(PaywallPlan.YEARLY)) onChanged() },
        )
        PlanOption(
            title = monthlyTitle,
            trailing = null,
            isSelected = selection.plan == PaywallPlan.MONTHLY,
            onTap = { if (selection.select(PaywallPlan.MONTHLY)) onChanged() },
        )
    }
}

@Composable
private fun PlanOption(
    title: String,
    trailing: String?,
    isSelected: Boolean,
    onTap: () -> Unit,
) {
    val shape = RoundedCornerShape(20.dp)
    val interior = if (isSelected) {
        LazurePigments.ankyGold.copy(alpha = 0.07f)
    } else {
        androidx.compose.ui.graphics.Color.Transparent
    }
    Row(
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .height(60.dp)
            .clip(shape)
            .background(LazurePigments.ankyPaper.copy(alpha = 0.72f))
            .background(interior)
            .border(
                width = if (isSelected) 1.dp else 0.5.dp,
                color = if (isSelected) {
                    LazurePigments.ankyGold.copy(alpha = 0.85f)
                } else {
                    LazurePigments.ankySlate.copy(alpha = 0.35f)
                },
                shape = shape,
            )
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
                role = Role.RadioButton,
                onClick = onTap,
            )
            .padding(horizontal = 18.dp),
    ) {
        Text(
            text = title,
            style = LazureType.ankyProse.copy(fontSize = 16.sp),
            color = if (isSelected) LazurePigments.ankyInk else LazurePigments.ankyInk.copy(alpha = 0.72f),
            maxLines = 1,
            modifier = Modifier.weight(1f),
        )
        if (trailing != null) {
            Text(
                text = trailing,
                style = LazureType.ankyProse.copy(fontSize = 14.sp, fontWeight = FontWeight.Medium),
                color = LazurePigments.ankyGold,
            )
        }
    }
}

@Composable
private fun PaywallFooter(
    isRestoring: Boolean,
    onRestore: () -> Unit,
    onShowTerms: () -> Unit,
    onShowPrivacy: () -> Unit,
    onSkip: () -> Unit,
) {
    val resources = LocalContext.current.resources
    Column(
        verticalArrangement = Arrangement.spacedBy(12.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = Modifier.fillMaxWidth().padding(top = 2.dp),
    ) {
        Row(
            horizontalArrangement = Arrangement.spacedBy(18.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            FooterLink(
                title = resources.getString(if (isRestoring) R.string.paywall_restoring else R.string.paywall_restore),
                onClick = onRestore,
            )
            FooterDot()
            FooterLink(title = resources.getString(R.string.paywall_terms), onClick = onShowTerms)
            FooterDot()
            FooterLink(title = resources.getString(R.string.paywall_privacy), onClick = onShowPrivacy)
        }

        // iOS also shows a "Have a code?" offer-code link here;
        // Play Billing has no in-app redemption sheet, so Android omits it
        // (codes redeem through the Play Store app). See WIRING-paywall.md.

        @Suppress("KotlinConstantConditions")
        if (PaywallDefaults.PAYWALL_IS_SKIPPABLE) {
            Text(
                text = resources.getString(R.string.paywall_later),
                style = LazureType.ankyCaption.copy(textDecoration = TextDecoration.Underline),
                color = LazurePigments.ankyInkSoft.copy(alpha = 0.8f),
                modifier = Modifier.clickable(
                    interactionSource = remember { MutableInteractionSource() },
                    indication = null,
                    role = Role.Button,
                    onClick = onSkip,
                ),
            )
        }
    }
}

@Composable
private fun FooterDot() {
    Text(
        text = "·",
        style = LazureType.ankyProse.copy(fontSize = 13.sp),
        color = LazurePigments.ankySlate.copy(alpha = 0.6f),
    )
}

@Composable
private fun FooterLink(title: String, onClick: () -> Unit) {
    Text(
        text = title,
        style = LazureType.ankyProse.copy(fontSize = 13.sp),
        color = LazurePigments.ankySlate,
        modifier = Modifier.clickable(
            interactionSource = remember { MutableInteractionSource() },
            indication = null,
            role = Role.Button,
            onClick = onClick,
        ),
    )
}

/** Walks the ContextWrapper chain to the hosting Activity (Play Billing needs one). */
internal fun Context.findActivity(): Activity? {
    var current: Context = this
    while (current is ContextWrapper) {
        if (current is Activity) {
            return current
        }
        current = current.baseContext
    }
    return null
}

/** Resolves a [PaywallLine], formatting nested lines depth-first. */
fun PaywallLine.resolve(resources: Resources): String {
    if (args.isEmpty()) {
        return resources.getString(res)
    }
    val resolved = args.map { arg ->
        when (arg) {
            is PaywallArg.Text -> arg.value
            is PaywallArg.Nested -> arg.line.resolve(resources)
        }
    }.toTypedArray()
    return resources.getString(res, *resolved)
}

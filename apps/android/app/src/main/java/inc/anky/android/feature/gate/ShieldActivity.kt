package inc.anky.android.feature.gate

import android.content.Context
import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.OnBackPressedCallback
import androidx.activity.compose.setContent
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import inc.anky.android.core.gate.WriteBeforeScrollEventName
import inc.anky.android.core.gate.WriteBeforeScrollShieldReconciler
import inc.anky.android.core.gate.runtime.GateDeepLinks
import inc.anky.android.core.gate.runtime.GateRuntime
import java.time.Instant

/**
 * The door itself — Android's ShieldConfiguration + ShieldAction extensions
 * in one full-screen activity, launched by [inc.anky.android.core.gate.runtime.GateWatcherService]
 * over a blocked app. `singleTask` in its own task, excluded from recents,
 * `noHistory`; the back gesture goes *home*, never into the blocked app.
 */
class ShieldActivity : ComponentActivity() {

    private lateinit var runtime: GateRuntime
    private var blockedPackage by mutableStateOf<String?>(null)
    private var blockedLabel by mutableStateOf<String?>(null)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        runtime = GateRuntime(this)
        readIntent(intent)
        logShieldShown()

        onBackPressedDispatcher.addCallback(
            this,
            object : OnBackPressedCallback(true) {
                override fun handleOnBackPressed() {
                    // Never back into the blocked app: go to the home screen
                    // (the blocked app is directly underneath this task —
                    // merely backgrounding the shield would reveal it and
                    // the watcher would relaunch us in a loop).
                    startActivity(
                        Intent(Intent.ACTION_MAIN)
                            .addCategory(Intent.CATEGORY_HOME)
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                    )
                    moveTaskToBack(true)
                }
            },
        )

        setContent {
            ShieldScreen(
                appLabel = blockedLabel,
                quickPassesRemaining = runtime.quickPassStore.remainingPasses(),
                onWriteRequested = ::handleWrite,
                onEmergencyRequested = ::handleEmergency,
            )
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val previousPackage = blockedPackage
        readIntent(intent)
        if (blockedPackage != previousPackage) {
            logShieldShown()
        }
    }

    override fun onResume() {
        super.onResume()
        // The unlock may have landed while the door was standing (quick pass
        // sealed in the writing surface, emergency breath completed): obey
        // the reconciler and step aside.
        val decision = WriteBeforeScrollShieldReconciler.decision(
            gateOff = runtime.gateSwitchStore.isGateOff,
            state = runtime.stateStore.load(),
            at = Instant.now(),
        )
        if (decision == WriteBeforeScrollShieldReconciler.Decision.ClearShield) {
            finish()
        }
    }

    private fun readIntent(intent: Intent?) {
        blockedPackage = intent?.getStringExtra(ExtraBlockedPackage)
        blockedLabel = intent?.getStringExtra(ExtraBlockedLabel)
    }

    /** iOS logs `shield_rendered` per render; the activity logs one `shield_shown` per interception. */
    private fun logShieldShown() {
        val remaining = runtime.quickPassStore.remainingPasses()
        runtime.eventLog.append(
            WriteBeforeScrollEventName.ShieldShown,
            metadata = mapOf(
                "attemptedAppName" to (blockedLabel ?: blockedPackage ?: "unknown"),
                "package" to (blockedPackage ?: "unknown"),
                "quickPassesRemaining" to "$remaining",
            ),
        )
        if (remaining == 0) {
            runtime.eventLog.append(WriteBeforeScrollEventName.QuickPassExhaustedShown)
        }
    }

    /** Primary button — "Write ⊙": carry the intent across to the app, like the iOS shield-action bridge. */
    private fun handleWrite() {
        val now = Instant.now()
        runtime.eventLog.append(
            WriteBeforeScrollEventName.ShieldActionTapped,
            at = now,
            metadata = mapOf(
                "action" to "write",
                "package" to (blockedPackage ?: "unknown"),
            ),
        )
        // The pending marker survives even if the VIEW intent is lost —
        // MainActivity's routing can consume it (iOS pendingIntervention).
        runtime.stateStore.update { state ->
            state.copy(pendingInterventionRequestedAt = now)
        }
        startActivity(GateDeepLinks.mainActivityIntent(this, GateDeepLinks.WriteUri))
        finish()
    }

    /** Secondary — the emergency door: straight into the 30-second breath. */
    private fun handleEmergency() {
        val now = Instant.now()
        runtime.eventLog.append(
            WriteBeforeScrollEventName.ShieldActionTapped,
            at = now,
            metadata = mapOf(
                "action" to "emergency",
                "package" to (blockedPackage ?: "unknown"),
            ),
        )
        runtime.eventLog.append(
            WriteBeforeScrollEventName.EmergencyUnlockTapped,
            at = now,
            metadata = mapOf("package" to (blockedPackage ?: "unknown")),
        )
        startActivity(GateDeepLinks.mainActivityIntent(this, GateDeepLinks.EmergencyUri))
        finish()
    }

    companion object {
        private const val ExtraBlockedPackage = "inc.anky.android.gate.extra.BLOCKED_PACKAGE"
        private const val ExtraBlockedLabel = "inc.anky.android.gate.extra.BLOCKED_LABEL"

        fun intent(context: Context, blockedPackage: String, label: String?): Intent =
            Intent(context, ShieldActivity::class.java)
                .putExtra(ExtraBlockedPackage, blockedPackage)
                .putExtra(ExtraBlockedLabel, label)
                .addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_EXCLUDE_FROM_RECENTS,
                )
    }
}

package inc.anky.android.core.gate.runtime

import android.content.Context
import android.content.Intent
import android.net.Uri

/**
 * The shield's two exits, carried as *explicit* VIEW intents to
 * MainActivity (class-addressed, no manifest intent-filter for `anky://` —
 * the integration workstream owns MainActivity's routing; see
 * WIRING-gate-runtime.md).
 */
object GateDeepLinks {
    /** "Write ⊙" — the door opens through writing. */
    const val WriteUri = "anky://write"

    /** The 30-second emergency breath. */
    const val EmergencyUri = "anky://emergency"

    private const val MainActivityClassName = "inc.anky.android.MainActivity"

    fun mainActivityIntent(context: Context, uri: String): Intent =
        Intent(Intent.ACTION_VIEW, Uri.parse(uri))
            .setClassName(context.packageName, MainActivityClassName)
            .addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP,
            )
}

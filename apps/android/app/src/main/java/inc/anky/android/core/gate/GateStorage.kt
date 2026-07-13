package inc.anky.android.core.gate

import android.content.Context
import android.content.SharedPreferences

/**
 * The single preferences file behind every Write Before Scroll store. iOS
 * splits state between App Group defaults (shield extensions) and standard
 * defaults (main app only); Android is one process, so one file carries the
 * exact same per-store keys with no App-Group indirection.
 */
object GateStorage {
    const val PreferencesName = "anky-write-before-scroll"

    fun preferences(context: Context): SharedPreferences =
        context.applicationContext.getSharedPreferences(PreferencesName, Context.MODE_PRIVATE)
}

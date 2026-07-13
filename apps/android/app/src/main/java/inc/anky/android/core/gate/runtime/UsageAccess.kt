package inc.anky.android.core.gate.runtime

import android.app.AppOpsManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Process

/**
 * Usage-access is Android's Screen Time authorization: a special-access
 * toggle (Settings → Apps → Special access → Usage access), checked live
 * through AppOps — never persisted, matching the WIRING-gate.md note that
 * authorization state has no store on Android.
 */
object UsageAccess {

    fun hasUsageAccess(context: Context): Boolean {
        val appOps = context.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = if (Build.VERSION.SDK_INT >= 29) {
            appOps.unsafeCheckOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(),
                context.packageName,
            )
        } else {
            @Suppress("DEPRECATION")
            appOps.checkOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(),
                context.packageName,
            )
        }
        return when (mode) {
            AppOpsManager.MODE_ALLOWED -> true
            AppOpsManager.MODE_DEFAULT ->
                context.checkPermission(
                    android.Manifest.permission.PACKAGE_USAGE_STATS,
                    Process.myPid(),
                    Process.myUid(),
                ) == PackageManager.PERMISSION_GRANTED
            else -> false
        }
    }
}

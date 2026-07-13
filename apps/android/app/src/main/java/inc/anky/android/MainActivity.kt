package inc.anky.android

import android.content.Intent
import android.content.pm.ShortcutInfo
import android.content.pm.ShortcutManager
import android.graphics.drawable.Icon
import android.net.Uri
import android.os.Build
import android.os.Bundle
import androidx.activity.compose.setContent
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.fragment.app.FragmentActivity
import inc.anky.android.app.AnkyApp

class MainActivity : FragmentActivity() {
    private var deepLinkUri by mutableStateOf<String?>(null)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        deepLinkUri = intent?.data?.toString()
        publishPaintingShortcut()
        val container = (application as AnkyApplication).container
        setContent {
            AnkyApp(
                container = container,
                deepLinkUri = deepLinkUri,
                onDeepLinkHandled = { deepLinkUri = null },
            )
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        deepLinkUri = intent.data?.toString()
    }

    private fun publishPaintingShortcut() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N_MR1) return
        val manager = getSystemService(ShortcutManager::class.java) ?: return
        val shortcut = ShortcutInfo.Builder(this, "open_painting")
            .setShortLabel("Open painting")
            .setLongLabel("Open Anky painting")
            .setIcon(Icon.createWithResource(this, R.mipmap.ic_launcher))
            .setIntent(
                Intent(Intent.ACTION_VIEW, Uri.parse("anky://painting"))
                    .setPackage(packageName)
                    .setClass(this, MainActivity::class.java),
            )
            .build()
        manager.dynamicShortcuts = listOf(shortcut)
    }
}

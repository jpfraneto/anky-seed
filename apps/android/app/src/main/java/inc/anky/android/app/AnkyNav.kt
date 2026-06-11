package inc.anky.android.app

import android.net.Uri
import androidx.annotation.StringRes
import inc.anky.android.R

sealed class AnkyRoute(
    val route: String,
    val label: String,
    @StringRes val labelRes: Int,
) {
    data object Write : AnkyRoute("write", "Write", R.string.tab_write)
    data object Map : AnkyRoute("map", "Map", R.string.tab_map)
    data object MapAllAnkys : AnkyRoute("map/all-ankys", "Map", R.string.tab_map)
    data object You : AnkyRoute("you", "You", R.string.tab_you)
    data object YouCredits : AnkyRoute("you/credits", "You", R.string.tab_you)
    data object Reveal : AnkyRoute("reveal/{hash}?reflect={reflect}", "Reveal", R.string.tab_write) {
        fun route(hash: String, reflect: Boolean = false): String = "reveal/$hash?reflect=$reflect"
    }
    data object TagSessions : AnkyRoute("tags/{tag}", "Tags", R.string.tab_map) {
        fun route(tag: String): String = "tags/${Uri.encode(tag)}"
    }
}

package inc.anky.android.app

import android.net.Uri

sealed class AnkyRoute(val route: String, val label: String) {
    data object Write : AnkyRoute("write", "Write")
    data object Map : AnkyRoute("map", "Map")
    data object You : AnkyRoute("you", "You")
    data object YouCredits : AnkyRoute("you/credits", "You")
    data object Reveal : AnkyRoute("reveal/{hash}?reflect={reflect}", "Reveal") {
        fun route(hash: String, reflect: Boolean = false): String = "reveal/$hash?reflect=$reflect"
    }
    data object TagSessions : AnkyRoute("tags/{tag}", "Tags") {
        fun route(tag: String): String = "tags/${Uri.encode(tag)}"
    }
}

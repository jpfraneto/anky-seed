package inc.anky.android.app

sealed class AnkyRoute(val route: String, val label: String) {
    data object Write : AnkyRoute("write", "Write")
    data object Map : AnkyRoute("map", "Map")
    data object You : AnkyRoute("you", "You")
    data object Reveal : AnkyRoute("reveal/{hash}", "Reveal") {
        fun route(hash: String): String = "reveal/$hash"
    }
}

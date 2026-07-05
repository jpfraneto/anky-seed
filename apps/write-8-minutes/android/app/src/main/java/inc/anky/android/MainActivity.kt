package inc.anky.android

import android.os.Bundle
import androidx.activity.compose.setContent
import androidx.fragment.app.FragmentActivity
import inc.anky.android.app.AnkyApp

class MainActivity : FragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val container = (application as AnkyApplication).container
        setContent {
            AnkyApp(container = container)
        }
    }
}

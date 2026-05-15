package inc.anky.android

import android.app.Application
import inc.anky.android.app.AppContainer

class AnkyApplication : Application() {
    lateinit var container: AppContainer
        private set

    override fun onCreate() {
        super.onCreate()
        container = AppContainer(this)
    }
}

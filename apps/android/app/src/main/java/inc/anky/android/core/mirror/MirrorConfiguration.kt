package inc.anky.android.core.mirror

import inc.anky.android.BuildConfig

data class MirrorConfiguration(
    val baseUrl: String = BuildConfig.DEFAULT_MIRROR_BASE_URL,
)

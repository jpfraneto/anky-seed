package inc.anky.android.feature.map

import androidx.lifecycle.ViewModel
import inc.anky.android.core.storage.AppOpenStore
import inc.anky.android.core.storage.LocalAnkyArchive
import inc.anky.android.core.storage.ReflectionStore
import inc.anky.android.core.storage.SessionDay
import inc.anky.android.core.storage.SessionIndexStore
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

data class MapState(
    val days: List<SessionDay> = emptyList(),
)

class MapViewModel(
    private val archive: LocalAnkyArchive,
    private val reflectionStore: ReflectionStore,
    private val indexStore: SessionIndexStore,
    private val appOpenStore: AppOpenStore,
) : ViewModel() {
    private val _state = MutableStateFlow(MapState())
    val state: StateFlow<MapState> = _state

    fun refresh() {
        val sessions = indexStore.rebuild(archive, reflectionStore)
        val firstOpen = sessions
            .minByOrNull { it.createdAt }
            ?.let { appOpenStore.recordEarlierFirstOpenDate(it.createdAt) }
            ?: appOpenStore.loadOrCreate()
        _state.value = MapState(days = SessionIndexStore.groupByContinuousDays(sessions, firstOpen))
    }
}

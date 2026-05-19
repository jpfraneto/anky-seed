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
    val errorMessage: String? = null,
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
        runCatching {
            val sessions = indexStore.rebuild(archive, reflectionStore)
            val firstOpen = sessions
                .minByOrNull { it.createdAt }
                ?.let { appOpenStore.recordEarlierFirstOpenDate(it.createdAt) }
                ?: appOpenStore.loadOrCreate()
            SessionIndexStore.groupByContinuousDays(sessions, firstOpen)
        }.onSuccess { days ->
            _state.value = MapState(days = days, errorMessage = null)
        }.onFailure {
            _state.value = MapState(
                days = emptyList(),
                errorMessage = "Could not load the map.",
            )
        }
    }
}

package inc.anky.android.feature.map

import androidx.lifecycle.ViewModel
import inc.anky.android.core.storage.AppOpenStore
import inc.anky.android.core.storage.LocalAnkyArchive
import inc.anky.android.core.storage.ReflectionStore
import inc.anky.android.core.storage.SessionDay
import inc.anky.android.core.storage.SessionIndexStore
import java.time.Instant
import java.time.ZoneOffset
import java.time.temporal.ChronoUnit
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

data class MapState(
    val days: List<SessionDay> = emptyList(),
    val completeAnkyCount: Int = 0,
    val totalWritingMinutes: Int = 0,
    val currentStreak: Int = 0,
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
            val storedFirstOpen = appOpenStore.loadOrCreate()
            val sessions = runCatching {
                indexStore.rebuild(archive, reflectionStore)
            }.getOrElse {
                indexStore.load()
            }
            val firstOpen = sessions
                .minByOrNull { it.createdAt }
                ?.let { appOpenStore.recordEarlierFirstOpenDate(it.createdAt) }
                ?: storedFirstOpen
            val days = SessionIndexStore.groupByContinuousDays(sessions, firstOpen)
            val completeSessions = sessions.filter { it.isComplete }
            val totalDurationMs = sessions.sumOf { it.durationMs }
            MapState(
                days = days,
                completeAnkyCount = completeSessions.size,
                totalWritingMinutes = if (sessions.isEmpty()) 0 else maxOf(1, ((totalDurationMs + 59_999L) / 60_000L).toInt()),
                currentStreak = currentStreak(completeSessions.map { it.createdAt }),
                errorMessage = null,
            )
        }.onSuccess { mapState ->
            _state.value = mapState
        }.onFailure {
            _state.value = MapState(
                days = emptyList(),
                errorMessage = "Could not load the map.",
            )
        }
    }

    private fun currentStreak(dates: List<Instant>, now: Instant = Instant.now()): Int {
        val activeDays = dates.map { it.atZone(ZoneOffset.UTC).toLocalDate() }.toSet()
        if (activeDays.isEmpty()) return 0
        var day = now.atZone(ZoneOffset.UTC).toLocalDate()
        if (!activeDays.contains(day)) return 0
        var streak = 0
        while (activeDays.contains(day)) {
            streak += 1
            day = day.minus(1, ChronoUnit.DAYS)
        }
        return streak
    }
}

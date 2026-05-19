package inc.anky.android.core.storage

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.temporal.ChronoUnit

class SessionIndexStore private constructor(
    private val file: File,
) {
    constructor(context: Context) : this(File(File(context.filesDir, "Anky"), "session-index.json"))

    init {
        file.parentFile?.mkdirs()
    }

    fun load(): List<SessionSummary> {
        if (!file.exists()) return emptyList()
        return runCatching {
            val array = JSONArray(file.readText(Charsets.UTF_8))
            (0 until array.length()).map { array.getJSONObject(it).toSessionSummary() }
        }.getOrDefault(emptyList())
    }

    fun save(sessions: List<SessionSummary>) {
        val sorted = sessions.sortedByDescending { it.createdAt }
        val array = JSONArray()
        sorted.forEach { array.put(it.toJson()) }
        file.writeText(array.toString(2), Charsets.UTF_8)
    }

    fun upsert(summary: SessionSummary) {
        save(load().filter { it.hash != summary.hash } + summary)
    }

    fun rebuild(archive: LocalAnkyArchive, reflectionStore: ReflectionStore): List<SessionSummary> {
        val sessions = archive.list().map { artifact ->
            SessionSummary.make(artifact, reflectionStore.load(artifact.hash))
        }
        save(sessions)
        return sessions
    }

    fun updateReflection(hash: String, title: String) {
        save(load().map { summary ->
            if (summary.hash == hash) {
                summary.copy(hasReflection = true, reflectionTitle = title)
            } else {
                summary
            }
        })
    }

    fun delete(hash: String) {
        save(load().filter { it.hash != hash })
    }

    fun clear() {
        if (file.exists()) file.delete()
    }

    companion object {
        fun forFile(file: File): SessionIndexStore = SessionIndexStore(file)

        fun groupByDay(sessions: List<SessionSummary>, zoneId: ZoneId = ZoneOffset.UTC): List<SessionDay> {
            val grouped = sessions.groupBy { it.createdAt.atZone(zoneId).toLocalDate() }
            val startDate = grouped.keys.minOrNull() ?: LocalDate.now(zoneId)
            return grouped
                .map { (day, daySessions) ->
                    val sorted = daySessions.sortedByDescending { it.createdAt }
                    SessionDay(
                        dayEpochMs = day.atStartOfDay(zoneId).toInstant().toEpochMilli(),
                        sessions = sorted,
                        completeCount = sorted.count { it.isComplete },
                        fragmentCount = sorted.count { !it.isComplete },
                        reflectionCount = sorted.count { it.hasReflection },
                        dayIndex = dayIndex(startDate, day),
                        dayInRegion = dayInRegion(startDate, day),
                    )
                }
                .sortedByDescending { it.dayEpochMs }
        }

        fun groupByContinuousDays(
            sessions: List<SessionSummary>,
            firstOpen: Instant,
            now: Instant = Instant.now(),
            zoneId: ZoneId = ZoneOffset.UTC,
        ): List<SessionDay> {
            val grouped = sessions.groupBy { it.createdAt.atZone(zoneId).toLocalDate() }
            val firstOpenDate = firstOpen.atZone(zoneId).toLocalDate()
            val earliestSessionDate = grouped.keys.minOrNull()
            val latestSessionDate = grouped.keys.maxOrNull()
            val today = now.atZone(zoneId).toLocalDate()
            val requestedStartDate = listOfNotNull(firstOpenDate, earliestSessionDate).minOrNull() ?: firstOpenDate
            val endDate = listOfNotNull(today, latestSessionDate).maxOrNull() ?: today
            val startDate = if (ChronoUnit.DAYS.between(requestedStartDate, endDate) > MaxContinuousTrailDays) {
                endDate.minusDays(MaxContinuousTrailDays)
            } else {
                requestedStartDate
            }
            val dayCount = ChronoUnit.DAYS.between(startDate, endDate).coerceAtLeast(0)

            return (0..dayCount).map { offset ->
                val day = startDate.plusDays(offset)
                val sorted = grouped[day].orEmpty().sortedByDescending { it.createdAt }
                SessionDay(
                    dayEpochMs = day.atStartOfDay(zoneId).toInstant().toEpochMilli(),
                    sessions = sorted,
                    completeCount = sorted.count { it.isComplete },
                    fragmentCount = sorted.count { !it.isComplete },
                    reflectionCount = sorted.count { it.hasReflection },
                    dayIndex = dayIndex(startDate, day),
                    dayInRegion = dayInRegion(startDate, day),
                )
            }
        }

        private fun dayIndex(startDate: LocalDate, day: LocalDate): Int =
            ChronoUnit.DAYS.between(startDate, day).coerceAtLeast(0).toInt() + 1

        private fun dayInRegion(startDate: LocalDate, day: LocalDate): Int {
            return (((dayIndex(startDate, day) - 1) % 8) + 1)
        }

        private const val MaxContinuousTrailDays = 3650L
    }
}

private fun SessionSummary.toJson(): JSONObject =
    JSONObject()
        .put("hash", hash)
        .put("createdAt", createdAt.toString())
        .put("localFilePath", localFilePath)
        .put("durationMs", durationMs)
        .put("isComplete", isComplete)
        .put("preview", preview)
        .put("wordCount", wordCount)
        .put("hasReflection", hasReflection)
        .put("reflectionTitle", reflectionTitle)

private fun JSONObject.toSessionSummary(): SessionSummary =
    SessionSummary(
        hash = getString("hash"),
        createdAt = Instant.parse(getString("createdAt")),
        localFilePath = getString("localFilePath"),
        durationMs = getLong("durationMs"),
        isComplete = getBoolean("isComplete"),
        preview = getString("preview"),
        wordCount = optInt("wordCount", SessionSummary.wordCount(getString("preview"))),
        hasReflection = getBoolean("hasReflection"),
        reflectionTitle = if (isNull("reflectionTitle")) null else getString("reflectionTitle"),
    )

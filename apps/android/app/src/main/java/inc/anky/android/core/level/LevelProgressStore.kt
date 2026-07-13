package inc.anky.android.core.level

import android.content.Context
import java.io.File
import org.json.JSONArray
import org.json.JSONObject

/**
 * Phase of one level's painting, keyed by the level the painting celebrates
 * reaching. Mirrors the server's `level_state.phase` and iOS's raw values.
 */
enum class LevelPaintingPhase(val rawValue: String) {
    Accumulating("accumulating"),
    GenerationPending("generationPending"),
    Generated("generated"),
    CeremonyPending("ceremonyPending"),
    CeremonyShown("ceremonyShown"),
    ;

    companion object {
        fun fromRawValue(raw: String?): LevelPaintingPhase? =
            entries.firstOrNull { it.rawValue == raw }
    }
}

/**
 * A sealed session the server's ledger has not acknowledged yet.
 * Carries hash and seconds only — never writing.
 */
data class LevelUnreportedSession(
    val hash: String,
    val seconds: Long,
    val sealedAtMs: Long,
)

/**
 * Persisted counter state. JSON field names match iOS `LevelProgressSnapshot`
 * (Swift Codable defaults) exactly so a future shared backup stays readable.
 */
data class LevelProgressSnapshot(
    val totalSeconds: Long = 0,
    val pendingStrokeSeconds: Long = 0,
    val unreported: List<LevelUnreportedSession> = emptyList(),
    val phaseByLevel: Map<String, LevelPaintingPhase> = emptyMap(),
    val didBackfill: Boolean = false,
    /**
     * Phase-3 funnel: whether boundary_reached has been reported for this
     * writer. One event per life, persisted so relaunches never repeat it.
     */
    val didReportBoundary: Boolean = false,
    /**
     * The moment the last ceremony was shown — the chapter boundary the
     * next distillation reads from. Null means "since the beginning".
     */
    val lastLevelUpAtMs: Long? = null,
    /**
     * Highest level whose unveiling has been witnessed (null reads as 1:
     * level 1 needs no ceremony — it is the beginning).
     */
    val lastCeremonyShownLevel: Int? = null,
)

/** Minimal session-summary input for the one-time backfill (hash + timing only). */
data class LevelSessionStat(
    val hash: String,
    val createdAtMs: Long,
    val durationMs: Long,
)

/**
 * The client-side counter of record for lifetime seconds written.
 *
 * Every sealed session credits its exact seconds here, synchronously, before
 * any UI transition — the number is offline-correct and never waits on the
 * network. The server ledger (`POST /level/sessions`) is reconciled from the
 * `unreported` queue whenever connectivity allows.
 */
class LevelProgressStore(
    private val file: File,
    private val clock: () -> Long = System::currentTimeMillis,
) {
    constructor(context: Context, clock: () -> Long = System::currentTimeMillis) :
        this(File(File(context.filesDir, "Anky"), "level-progress.json"), clock)

    init {
        file.parentFile?.mkdirs()
    }

    fun load(): LevelProgressSnapshot {
        if (!file.exists()) return LevelProgressSnapshot()
        return runCatching { JSONObject(file.readText(Charsets.UTF_8)).toSnapshot() }
            .getOrDefault(LevelProgressSnapshot())
    }

    fun save(snapshot: LevelProgressSnapshot) {
        runCatching {
            val temp = File(file.parentFile, "${file.name}.tmp")
            temp.writeText(snapshot.toJson().toString(), Charsets.UTF_8)
            if (!temp.renameTo(file)) {
                file.writeText(snapshot.toJson().toString(), Charsets.UTF_8)
                temp.delete()
            }
        }
    }

    val progress: AnkyLevel.Progress
        get() = AnkyLevel.progress(load().totalSeconds)

    // MARK: Phase-3 boundary

    /**
     * What the UI shows. Entitled writers see the true curve; a free writer
     * past the boundary sees level 2 serenely complete at 100%. The counter
     * underneath keeps every second — nothing is ever lost, and the true
     * level reappears the moment entitlement does.
     */
    fun presentedProgress(entitled: Boolean): AnkyLevel.Progress {
        val real = progress
        if (entitled || real.level <= FreeBoundaryLevel) {
            return real
        }
        val required = AnkyLevel.requirementSeconds(FreeBoundaryLevel)
        return AnkyLevel.Progress(
            level = FreeBoundaryLevel,
            secondsIntoLevel = required,
            secondsRequired = required,
            percent = 1.0,
            totalSeconds = real.totalSeconds,
        )
    }

    /** True while a free writer stands at the held-100% moment. */
    fun isAtBoundary(entitled: Boolean): Boolean =
        !entitled && progress.level > FreeBoundaryLevel

    /**
     * Claims the one boundary_reached funnel report. Returns true exactly
     * once, when the writer first stands at the boundary.
     */
    fun claimBoundaryReport(entitled: Boolean): Boolean {
        if (!isAtBoundary(entitled)) return false
        val snapshot = load()
        if (snapshot.didReportBoundary) return false
        save(snapshot.copy(didReportBoundary = true))
        return true
    }

    /**
     * Credits a sealed session. When the session replaced a continued
     * artifact, only the newly written delta is credited (the replaced
     * artifact's seconds were already counted under its own hash).
     */
    fun creditSealedSession(
        hash: String,
        durationMs: Long,
        replacedDurationMs: Long? = null,
        sealedAtMs: Long = clock(),
    ): AnkyLevel.Progress {
        val snapshot = load()
        val sessionSeconds = durationMs / 1000
        val replacedSeconds = (replacedDurationMs ?: 0L) / 1000
        val creditSeconds = maxOf(0L, sessionSeconds - replacedSeconds)
        if (creditSeconds <= 0 || snapshot.unreported.any { it.hash == hash }) {
            return AnkyLevel.progress(snapshot.totalSeconds)
        }
        val updated = snapshot.copy(
            totalSeconds = snapshot.totalSeconds + creditSeconds,
            pendingStrokeSeconds = snapshot.pendingStrokeSeconds + creditSeconds,
            unreported = snapshot.unreported + LevelUnreportedSession(
                hash = hash,
                seconds = creditSeconds,
                sealedAtMs = sealedAtMs,
            ),
        )
        save(updated)
        return AnkyLevel.progress(updated.totalSeconds)
    }

    /**
     * One-time adoption of history that predates the level system: sums the
     * session index and queues every artifact for the server ledger.
     */
    fun backfillIfNeeded(summaries: List<LevelSessionStat>) {
        var snapshot = load()
        if (snapshot.didBackfill) return
        snapshot = snapshot.copy(didBackfill = true)
        for (summary in summaries) {
            val seconds = summary.durationMs / 1000
            if (seconds <= 0 || snapshot.unreported.any { it.hash == summary.hash }) {
                continue
            }
            snapshot = snapshot.copy(
                totalSeconds = snapshot.totalSeconds + seconds,
                unreported = snapshot.unreported + LevelUnreportedSession(
                    hash = summary.hash,
                    seconds = seconds,
                    sealedAtMs = summary.createdAtMs,
                ),
            )
        }
        save(snapshot)
    }

    /** The strokes owed to the next visit of the painting page. */
    fun consumePendingStrokeSeconds(): Long {
        val snapshot = load()
        val pending = snapshot.pendingStrokeSeconds
        if (pending <= 0) return 0
        save(snapshot.copy(pendingStrokeSeconds = 0))
        return pending
    }

    fun peekPendingStrokeSeconds(): Long = load().pendingStrokeSeconds

    fun phase(level: Int): LevelPaintingPhase =
        load().phaseByLevel[level.toString()] ?: LevelPaintingPhase.Accumulating

    val lastCeremonyShownLevel: Int
        get() = load().lastCeremonyShownLevel ?: 1

    val lastLevelUpAtMs: Long?
        get() = load().lastLevelUpAtMs

    /**
     * The lowest level whose unveiling is owed: the writer has reached it,
     * but its ceremony has not been witnessed. Replay-safe across app kill —
     * this is pure persisted state, recomputed on every ask.
     */
    val owedCeremonyLevel: Int?
        get() {
            val snapshot = load()
            val reached = AnkyLevel.level(snapshot.totalSeconds)
            val shown = snapshot.lastCeremonyShownLevel ?: 1
            if (reached <= shown) return null
            return shown + 1
        }

    /**
     * Closes one unveiling. Persisted synchronously before any UI moves on —
     * it must be impossible to permanently miss (or repeat) your own ceremony.
     */
    fun markCeremonyShown(level: Int, atMs: Long = clock()) {
        val snapshot = load()
        val shown = snapshot.lastCeremonyShownLevel ?: 1
        if (level <= shown) return
        save(
            snapshot.copy(
                lastCeremonyShownLevel = level,
                lastLevelUpAtMs = atMs,
                phaseByLevel = snapshot.phaseByLevel + (level.toString() to LevelPaintingPhase.CeremonyShown),
            ),
        )
    }

    fun setPhase(phase: LevelPaintingPhase, level: Int) {
        val snapshot = load()
        save(snapshot.copy(phaseByLevel = snapshot.phaseByLevel + (level.toString() to phase)))
    }

    fun unreportedSessions(limit: Int = 500): List<LevelUnreportedSession> =
        load().unreported.take(limit)

    fun markReported(hashes: List<String>) {
        if (hashes.isEmpty()) return
        val snapshot = load()
        val reported = hashes.toSet()
        save(snapshot.copy(unreported = snapshot.unreported.filterNot { it.hash in reported }))
    }

    /**
     * Reinstall recovery: the server ledger may know sessions this install
     * never saw. The counter is monotonic, so adopt the higher total.
     */
    fun adoptServerTotalIfHigher(serverTotalSeconds: Long) {
        val snapshot = load()
        if (serverTotalSeconds <= snapshot.totalSeconds) return
        save(snapshot.copy(totalSeconds = serverTotalSeconds))
    }

    companion object {
        /**
         * The free tier deepens through the one free ceremony (level 1→2) and
         * then holds. Presentation never advances past this level unentitled.
         */
        const val FreeBoundaryLevel = 2
    }
}

private fun LevelProgressSnapshot.toJson(): JSONObject {
    val json = JSONObject()
        .put("totalSeconds", totalSeconds)
        .put("pendingStrokeSeconds", pendingStrokeSeconds)
        .put(
            "unreported",
            JSONArray().also { array ->
                unreported.forEach { session ->
                    array.put(
                        JSONObject()
                            .put("hash", session.hash)
                            .put("seconds", session.seconds)
                            .put("sealedAtMs", session.sealedAtMs),
                    )
                }
            },
        )
        .put(
            "phaseByLevel",
            JSONObject().also { levels ->
                phaseByLevel.forEach { (level, phase) -> levels.put(level, phase.rawValue) }
            },
        )
        .put("didBackfill", didBackfill)
        .put("didReportBoundary", didReportBoundary)
    lastLevelUpAtMs?.let { json.put("lastLevelUpAtMs", it) }
    lastCeremonyShownLevel?.let { json.put("lastCeremonyShownLevel", it) }
    return json
}

private fun JSONObject.toSnapshot(): LevelProgressSnapshot {
    val unreportedArray = optJSONArray("unreported") ?: JSONArray()
    val unreported = (0 until unreportedArray.length()).mapNotNull { index ->
        val entry = unreportedArray.optJSONObject(index) ?: return@mapNotNull null
        LevelUnreportedSession(
            hash = entry.getString("hash"),
            seconds = entry.getLong("seconds"),
            sealedAtMs = entry.getLong("sealedAtMs"),
        )
    }
    val phaseObject = optJSONObject("phaseByLevel") ?: JSONObject()
    val phaseByLevel = buildMap {
        phaseObject.keys().forEach { key ->
            LevelPaintingPhase.fromRawValue(phaseObject.optString(key))?.let { put(key, it) }
        }
    }
    return LevelProgressSnapshot(
        totalSeconds = optLong("totalSeconds", 0),
        pendingStrokeSeconds = optLong("pendingStrokeSeconds", 0),
        unreported = unreported,
        phaseByLevel = phaseByLevel,
        didBackfill = optBoolean("didBackfill", false),
        didReportBoundary = optBoolean("didReportBoundary", false),
        lastLevelUpAtMs = if (has("lastLevelUpAtMs") && !isNull("lastLevelUpAtMs")) getLong("lastLevelUpAtMs") else null,
        lastCeremonyShownLevel = if (has("lastCeremonyShownLevel") && !isNull("lastCeremonyShownLevel")) {
            getInt("lastCeremonyShownLevel")
        } else {
            null
        },
    )
}

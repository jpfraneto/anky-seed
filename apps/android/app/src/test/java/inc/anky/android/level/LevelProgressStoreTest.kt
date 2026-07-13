package inc.anky.android.level

import inc.anky.android.core.level.LevelPaintingPhase
import inc.anky.android.core.level.LevelProgressStore
import inc.anky.android.core.level.LevelSessionStat
import java.io.File
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class LevelProgressStoreTest {
    private fun temporaryStore(): LevelProgressStore {
        val file = File(
            File(System.getProperty("java.io.tmpdir"), "anky-tests-${UUID.randomUUID()}"),
            "level-progress.json",
        )
        return LevelProgressStore(file)
    }

    private fun hash(seed: Int): String =
        "0".repeat(64 - seed.toString().length) + seed.toString()

    @Test
    fun creditAccumulatesAndQueuesReport() {
        val store = temporaryStore()
        val progress = store.creditSealedSession(hash = hash(1), durationMs = 480_000)
        assertEquals(2, progress.level)
        assertEquals(480L, progress.totalSeconds)
        assertEquals(480L, store.peekPendingStrokeSeconds())
        assertEquals(1, store.unreportedSessions().size)
        assertEquals(480L, store.unreportedSessions().first().seconds)
    }

    @Test
    fun creditIsIdempotentPerHash() {
        val store = temporaryStore()
        store.creditSealedSession(hash = hash(2), durationMs = 60_000)
        store.creditSealedSession(hash = hash(2), durationMs = 60_000)
        assertEquals(60L, store.progress.totalSeconds)
        assertEquals(1, store.unreportedSessions().size)
    }

    @Test
    fun continuedSessionCreditsOnlyTheDelta() {
        val store = temporaryStore()
        store.creditSealedSession(hash = hash(3), durationMs = 120_000)
        store.creditSealedSession(hash = hash(4), durationMs = 300_000, replacedDurationMs = 120_000)
        assertEquals((120 + 180).toLong(), store.progress.totalSeconds)
        assertEquals(listOf(120L, 180L), store.unreportedSessions().map { it.seconds })
    }

    @Test
    fun subSecondSessionsDoNotCredit() {
        val store = temporaryStore()
        store.creditSealedSession(hash = hash(5), durationMs = 900)
        assertEquals(0L, store.progress.totalSeconds)
        assertTrue(store.unreportedSessions().isEmpty())
    }

    // MARK: Phase-3 boundary

    @Test
    fun presentedProgressHoldsAtBoundaryForFreeWriters() {
        val store = temporaryStore()
        // 480s closes level 1; another 778s closes level 2 → real level 3.
        store.creditSealedSession(hash = hash(31), durationMs = 480_000)
        store.creditSealedSession(hash = hash(32), durationMs = 800_000)
        assertEquals(3, store.progress.level)

        val held = store.presentedProgress(entitled = false)
        assertEquals(2, held.level)
        assertEquals(1.0, held.percent, 0.0)
        assertEquals(held.secondsRequired, held.secondsIntoLevel)
        // Nothing lost: the true total is carried through the veil.
        assertEquals(store.progress.totalSeconds, held.totalSeconds)

        assertEquals(3, store.presentedProgress(entitled = true).level)
        assertTrue(store.isAtBoundary(entitled = false))
        assertFalse(store.isAtBoundary(entitled = true))
    }

    @Test
    fun presentedProgressIsRealBeforeTheBoundary() {
        val store = temporaryStore()
        store.creditSealedSession(hash = hash(33), durationMs = 480_000)
        assertEquals(2, store.progress.level)
        val presented = store.presentedProgress(entitled = false)
        assertEquals(store.progress, presented)
        assertFalse(store.isAtBoundary(entitled = false))
    }

    @Test
    fun boundaryReportClaimsExactlyOnce() {
        val store = temporaryStore()
        store.creditSealedSession(hash = hash(34), durationMs = 480_000)
        assertFalse("not at boundary yet", store.claimBoundaryReport(entitled = false))
        store.creditSealedSession(hash = hash(35), durationMs = 800_000)
        assertFalse("entitled writers have no boundary", store.claimBoundaryReport(entitled = true))
        assertTrue(store.claimBoundaryReport(entitled = false))
        assertFalse("one report per life", store.claimBoundaryReport(entitled = false))
    }

    @Test
    fun pendingStrokeSecondsConsumeOnce() {
        val store = temporaryStore()
        store.creditSealedSession(hash = hash(6), durationMs = 90_000)
        assertEquals(90L, store.consumePendingStrokeSeconds())
        assertEquals(0L, store.consumePendingStrokeSeconds())
    }

    @Test
    fun backfillRunsOnce() {
        val store = temporaryStore()
        val summaries = listOf(
            LevelSessionStat(hash = hash(7), createdAtMs = System.currentTimeMillis(), durationMs = 240_000),
            LevelSessionStat(hash = hash(8), createdAtMs = System.currentTimeMillis(), durationMs = 240_000),
        )
        store.backfillIfNeeded(summaries)
        store.backfillIfNeeded(summaries)
        assertEquals(480L, store.progress.totalSeconds)
        assertEquals(2, store.unreportedSessions().size)
        // Backfill never owes strokes — the paintings begin from the present.
        assertEquals(0L, store.peekPendingStrokeSeconds())
    }

    @Test
    fun markReportedDrainsQueue() {
        val store = temporaryStore()
        store.creditSealedSession(hash = hash(9), durationMs = 60_000)
        store.creditSealedSession(hash = hash(10), durationMs = 60_000)
        store.markReported(listOf(hash(9)))
        assertEquals(listOf(hash(10)), store.unreportedSessions().map { it.hash })
        assertEquals(120L, store.progress.totalSeconds)
    }

    @Test
    fun adoptServerTotalOnlyIfHigher() {
        val store = temporaryStore()
        store.creditSealedSession(hash = hash(11), durationMs = 100_000)
        store.adoptServerTotalIfHigher(50)
        assertEquals(100L, store.progress.totalSeconds)
        store.adoptServerTotalIfHigher(700)
        assertEquals(700L, store.progress.totalSeconds)
    }

    @Test
    fun phasePersistsPerLevel() {
        val store = temporaryStore()
        assertEquals(LevelPaintingPhase.Accumulating, store.phase(2))
        store.setPhase(LevelPaintingPhase.Generated, 2)
        assertEquals(LevelPaintingPhase.Generated, store.phase(2))
        assertEquals(LevelPaintingPhase.Accumulating, store.phase(3))
    }

    // MARK: Kill-safe ceremony ledger

    @Test
    fun owedCeremonyDerivesFromPersistedState() {
        val store = temporaryStore()
        assertEquals(null, store.owedCeremonyLevel)
        store.creditSealedSession(hash = hash(41), durationMs = 480_000)
        assertEquals(2, store.owedCeremonyLevel)
        store.markCeremonyShown(2)
        assertEquals(null, store.owedCeremonyLevel)
        assertEquals(2, store.lastCeremonyShownLevel)
        assertEquals(LevelPaintingPhase.CeremonyShown, store.phase(2))
        // A second mark for a lower level never regresses the ledger.
        store.markCeremonyShown(1)
        assertEquals(2, store.lastCeremonyShownLevel)
    }

    @Test
    fun markCeremonyShownRecordsChapterBoundary() {
        val store = temporaryStore()
        store.creditSealedSession(hash = hash(42), durationMs = 480_000)
        assertEquals(null, store.lastLevelUpAtMs)
        store.markCeremonyShown(2, atMs = 1_234_567)
        assertEquals(1_234_567L, store.lastLevelUpAtMs)
    }
}

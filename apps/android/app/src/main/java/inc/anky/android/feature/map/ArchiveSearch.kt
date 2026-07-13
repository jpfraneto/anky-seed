package inc.anky.android.feature.map

import inc.anky.android.core.storage.SavedAnky
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

/**
 * The archive chamber's search plumbing, kept pure so it can be unit
 * tested. Mirrors the iOS ArchiveChamberView: reconstructed text is
 * lowercased ONCE per load into a cache keyed by hash — never on every
 * keystroke of the search field — and queries match against that cache.
 */
object ArchiveSearchIndex {

    /** One lowercased haystack per writing, keyed by content hash. */
    fun build(entries: List<SavedAnky>): Map<String, String> =
        entries.associate { it.hash to it.reconstructedText.lowercase() }

    /**
     * The visible writings for a query: blank queries pass everything,
     * anything else must appear in the cached lowercase text. An entry
     * missing from the cache (still building) is hidden rather than
     * searched on the main thread.
     */
    fun filter(
        entries: List<SavedAnky>,
        cache: Map<String, String>,
        query: String,
    ): List<SavedAnky> {
        val needle = query.trim().lowercase()
        if (needle.isEmpty()) return entries
        return entries.filter { cache[it.hash]?.contains(needle) == true }
    }
}

/** One archive day bucket: a local calendar day and its writings, newest first. */
data class ArchiveDaySection(
    val day: LocalDate,
    val isToday: Boolean,
    val isYesterday: Boolean,
    val entries: List<SavedAnky>,
)

/**
 * Buckets writings by LOCAL day (the archive reads like a diary, not a
 * protocol ledger), preserving the incoming newest-first order — "Today",
 * "Yesterday", then dated headers, exactly as the iOS chamber sections.
 */
fun archiveDaySections(
    entries: List<SavedAnky>,
    zone: ZoneId = ZoneId.systemDefault(),
    now: Instant = Instant.now(),
): List<ArchiveDaySection> {
    val today = now.atZone(zone).toLocalDate()
    val yesterday = today.minusDays(1)
    val order = mutableListOf<LocalDate>()
    val buckets = mutableMapOf<LocalDate, MutableList<SavedAnky>>()
    for (entry in entries) {
        val day = entry.createdAt.atZone(zone).toLocalDate()
        if (buckets[day] == null) {
            order += day
            buckets[day] = mutableListOf()
        }
        buckets.getValue(day) += entry
    }
    return order.map { day ->
        ArchiveDaySection(
            day = day,
            isToday = day == today,
            isYesterday = day == yesterday,
            entries = buckets.getValue(day),
        )
    }
}

package inc.anky.android.core.level.journey

import org.json.JSONObject

/**
 * The 96-day sojourn: 8 kingdom paintings stacked into one continuous
 * vertical world, primordia at the bottom, poiesis at the top. Each kingdom
 * holds 12 days — 8 stepping-stone "tile" days baked into its painting and
 * 4 "threshold" days in the misty seam toward the next kingdom. The
 * tile/threshold distinction is INTERNAL ONLY: no screen ever names a
 * kingdom, a threshold, or a crossing. The map just gets lighter.
 */
object JourneySojourn {
    const val KingdomCount = 8
    const val TilesPerKingdom = 8
    const val ThresholdsPerKingdom = 4
    const val DaysPerKingdom = TilesPerKingdom + ThresholdsPerKingdom
    const val TotalDays = KingdomCount * DaysPerKingdom // 96
}

enum class JourneyDayKind(val rawValue: String) {
    Tile("tile"),
    Threshold("threshold"),
    ;

    companion object {
        fun fromRawValue(raw: String?): JourneyDayKind? =
            entries.firstOrNull { it.rawValue == raw }
    }
}

/**
 * One day of the sojourn, pinned to a normalized position inside one of the
 * eight paintings. Threshold days may sit in the bottom mist-band of the
 * NEXT kingdom's image (the seam belongs to the crossing); after poiesis
 * they rise into the light at the top of image 8 — hence [imageIndex] is
 * stored separately from [kingdomIndex].
 */
data class JourneyDay(
    val index: Int, // 0...95, walked bottom-to-top
    val kind: JourneyDayKind,
    val kingdomIndex: Int, // 0...7, which kingdom's 12-day span owns the day
    val imageIndex: Int, // 0...7, which painting the position is authored in
    val x: Double, // normalized within that painting
    val y: Double,
)

/**
 * Loader for the authored positions (`journeykingdoms/journey_positions.json`
 * in the APK assets; the same file the iOS bundle ships). [parse] throws on
 * a missing or malformed file so it can never ship silently wrong; callers
 * that must fail soft use [parseOrEmpty].
 */
object JourneyPositions {
    const val AssetPath = "journeykingdoms/journey_positions.json"

    fun parse(json: String): List<JourneyDay> {
        val file = JSONObject(json)
        val daysArray = file.optJSONArray("days")
            ?: throw IllegalArgumentException("journey_positions.json missing days")
        val days = (0 until daysArray.length())
            .map { index ->
                val day = daysArray.getJSONObject(index)
                JourneyDay(
                    index = day.getInt("index"),
                    kind = JourneyDayKind.fromRawValue(day.getString("kind"))
                        ?: throw IllegalArgumentException("journey_positions.json has invalid kind"),
                    kingdomIndex = day.getInt("kingdom"),
                    imageIndex = day.getInt("image"),
                    x = day.getDouble("x"),
                    y = day.getDouble("y"),
                )
            }
            .sortedBy { it.index }
        val valid = days.size == JourneySojourn.TotalDays &&
            days.withIndex().all { (offset, day) ->
                day.index == offset &&
                    day.imageIndex in 0 until JourneySojourn.KingdomCount &&
                    day.kingdomIndex in 0 until JourneySojourn.KingdomCount
            }
        require(valid) { "journey_positions.json must hold days 0...95 with valid indices" }
        return days
    }

    fun parseOrEmpty(json: String?): List<JourneyDay> =
        runCatching { parse(json ?: return emptyList()) }.getOrDefault(emptyList())
}

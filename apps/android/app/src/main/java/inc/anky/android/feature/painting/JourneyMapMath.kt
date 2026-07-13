package inc.anky.android.feature.painting

import inc.anky.android.core.level.journey.JourneyDay
import inc.anky.android.core.level.journey.JourneySnapshot
import inc.anky.android.core.level.journey.JourneySojourn

/**
 * The geometry of the stacked journey world. Every kingdom painting renders
 * square at the card's width; adjacent paintings overlap by 4% of their
 * height so the misty seams melt into each other. Image 0 (primordia) sits
 * at the BOTTOM of the scroll content, image 7 (poiesis) at the top.
 *
 * Port of iOS `JourneyMapGeometry` (JourneyTilePositions.swift). Pure math
 * in whatever unit `imageSide` arrives in (px or dp) so it is JVM-testable.
 */
data class JourneyMapGeometry(val imageSide: Float) {

    val overlap: Float get() = imageSide * SeamOverlapFraction

    val totalHeight: Float
        get() = imageSide * JourneySojourn.KingdomCount -
            overlap * (JourneySojourn.KingdomCount - 1)

    /** Distance from the top of the scroll content to the top of a painting. */
    fun imageTop(imageIndex: Int): Float =
        (JourneySojourn.KingdomCount - 1 - imageIndex) * (imageSide - overlap)

    /** A day's position in scroll-content coordinates: (x, y). */
    fun point(day: JourneyDay): Pair<Float, Float> =
        Pair(
            imageSide * day.x.toFloat(),
            imageTop(day.imageIndex) + imageSide * day.y.toFloat(),
        )

    /** Which paintings contain a content-space y. In the seam overlap two do. */
    fun imageIndices(containing: Float): List<Int> =
        (0 until JourneySojourn.KingdomCount).filter { index ->
            val top = imageTop(index)
            containing >= top && containing <= top + imageSide
        }

    /**
     * The scroll offset (top of the viewport) that centers a content y in a
     * viewport of the given height, clamped to the scrollable range.
     */
    fun scrollOffsetCentering(contentY: Float, viewportHeight: Float): Float {
        val maxOffset = maxOf(0f, totalHeight - viewportHeight)
        return (contentY - viewportHeight / 2f).coerceIn(0f, maxOffset)
    }

    companion object {
        const val SeamOverlapFraction: Float = 0.04f
    }
}

/** One day-marker's presentation state on the journey map. */
enum class JourneyDayState { Completed, Missed, Current, Future }

/**
 * Pure derivation of a day marker's state from the derived journey
 * snapshot: the most recently lit stone is *current* (iOS
 * `latestWrittenIndex` — the max written index, so a missed day never
 * steals the walk), other written days are completed, days the walk passed
 * without writing are missed (a faint wash, never punitive), and
 * everything ahead is future.
 */
fun journeyDayState(index: Int, snapshot: JourneySnapshot): JourneyDayState = when {
    index in snapshot.writtenDayIndices &&
        index == snapshot.writtenDayIndices.max() -> JourneyDayState.Current
    index in snapshot.writtenDayIndices -> JourneyDayState.Completed
    index in snapshot.missedDayIndices -> JourneyDayState.Missed
    else -> JourneyDayState.Future
}

/**
 * Power-of-two `BitmapFactory.Options.inSampleSize` so a decoded kingdom
 * PNG lands at (or just above) the target width. Pure so it's testable.
 */
object JourneyImageSampling {
    fun inSampleSize(sourceWidth: Int, targetWidth: Int): Int {
        if (sourceWidth <= 0 || targetWidth <= 0) return 1
        var sample = 1
        while (sourceWidth / (sample * 2) >= targetWidth) {
            sample *= 2
        }
        return sample
    }
}

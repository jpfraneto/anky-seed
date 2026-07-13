package inc.anky.android.painting

import inc.anky.android.core.level.journey.JourneyDay
import inc.anky.android.core.level.journey.JourneyDayKind
import inc.anky.android.core.level.journey.JourneySnapshot
import inc.anky.android.core.level.journey.JourneySojourn
import inc.anky.android.feature.painting.JourneyDayState
import inc.anky.android.feature.painting.JourneyImageSampling
import inc.anky.android.feature.painting.JourneyMapGeometry
import inc.anky.android.feature.painting.journeyDayState
import org.junit.Assert.assertEquals
import org.junit.Test

/** iOS `JourneyMapGeometry` (JourneyTilePositions.swift), value for value. */
class JourneyMapMathTest {

    private val geometry = JourneyMapGeometry(imageSide = 1000f)

    private fun day(index: Int, image: Int, x: Double, y: Double) = JourneyDay(
        index = index,
        kind = JourneyDayKind.Tile,
        kingdomIndex = image,
        imageIndex = image,
        x = x,
        y = y,
    )

    @Test
    fun seamOverlapIsFourPercentOfTheImage() {
        assertEquals(0.04f, JourneyMapGeometry.SeamOverlapFraction, 0f)
        assertEquals(40f, geometry.overlap, 0f)
    }

    @Test
    fun totalHeightSubtractsSevenSeams() {
        // 8 paintings minus 7 overlapping seams: 8000 - 7*40.
        assertEquals(7720f, geometry.totalHeight, 0f)
    }

    @Test
    fun poiesisSitsAtTheTopPrimordiaAtTheBottom() {
        assertEquals(0f, geometry.imageTop(7), 0f)
        assertEquals(7 * 960f, geometry.imageTop(0), 0f)
        // Consecutive images step by side − overlap.
        for (index in 0..6) {
            assertEquals(960f, geometry.imageTop(index) - geometry.imageTop(index + 1), 1e-3f)
        }
    }

    @Test
    fun dayPointsResolveInsideTheirAuthoredImage() {
        val bottomDay = day(index = 0, image = 0, x = 0.52, y = 0.82)
        val (x0, y0) = geometry.point(bottomDay)
        assertEquals(520f, x0, 1e-3f)
        assertEquals(geometry.imageTop(0) + 820f, y0, 1e-3f)

        val topDay = day(index = 95, image = 7, x = 0.5, y = 0.1)
        val (x7, y7) = geometry.point(topDay)
        assertEquals(500f, x7, 1e-3f)
        assertEquals(100f, y7, 1e-3f)
    }

    @Test
    fun seamBandBelongsToBothPaintings() {
        // Just inside image 7's bottom band = also inside image 6's top.
        val seamY = geometry.imageTop(6) + geometry.overlap / 2f
        assertEquals(listOf(6, 7), geometry.imageIndices(seamY))
        // Mid-painting belongs to exactly one.
        assertEquals(listOf(7), geometry.imageIndices(500f))
        assertEquals(listOf(0), geometry.imageIndices(geometry.imageTop(0) + 500f))
    }

    @Test
    fun autoScrollCentersTheCurrentDayAndClampsAtTheEdges() {
        val viewport = 1000f
        // Centered in range.
        assertEquals(3500f, geometry.scrollOffsetCentering(4000f, viewport), 0f)
        // Clamped at the top of the world.
        assertEquals(0f, geometry.scrollOffsetCentering(100f, viewport), 0f)
        // Clamped at the bottom (max offset = totalHeight − viewport).
        assertEquals(6720f, geometry.scrollOffsetCentering(7700f, viewport), 0f)
    }

    @Test
    fun sojournConstantsHoldNinetySixDays() {
        assertEquals(96, JourneySojourn.TotalDays)
        assertEquals(8, JourneySojourn.KingdomCount)
    }

    // MARK: Day marker states

    @Test
    fun dayStatesDeriveFromTheSnapshot() {
        val snapshot = JourneySnapshot(
            completedDays = 3,
            currentJourneyDay = 5,
            writtenDayIndices = setOf(0, 1, 3),
            missedDayIndices = setOf(2, 4),
        )
        // The current stone is the most recently *written* one (iOS
        // latestWrittenIndex) — a missed day never steals the walk.
        assertEquals(JourneyDayState.Completed, journeyDayState(0, snapshot))
        assertEquals(JourneyDayState.Completed, journeyDayState(1, snapshot))
        assertEquals(JourneyDayState.Missed, journeyDayState(2, snapshot))
        assertEquals(JourneyDayState.Current, journeyDayState(3, snapshot))
        assertEquals(JourneyDayState.Missed, journeyDayState(4, snapshot))
        assertEquals(JourneyDayState.Future, journeyDayState(5, snapshot))
    }

    @Test
    fun currentStoneIsTheMostRecentlyLitOne() {
        val snapshot = JourneySnapshot(
            completedDays = 2,
            currentJourneyDay = 2,
            writtenDayIndices = setOf(0, 1),
            missedDayIndices = emptySet(),
        )
        assertEquals(JourneyDayState.Completed, journeyDayState(0, snapshot))
        assertEquals(JourneyDayState.Current, journeyDayState(1, snapshot))
    }

    @Test
    fun beforeAnyWritingEveryStoneIsFuture() {
        val snapshot = JourneySnapshot()
        assertEquals(JourneyDayState.Future, journeyDayState(0, snapshot))
        assertEquals(JourneyDayState.Future, journeyDayState(95, snapshot))
    }

    // MARK: Downsampling

    @Test
    fun sampleSizeIsThePowerOfTwoThatKeepsTheTargetWidth() {
        // 1254px kingdom on a ~1080px-wide card: full resolution.
        assertEquals(1, JourneyImageSampling.inSampleSize(1254, 1080))
        // Small card (e.g. 400px): halve once (627 ≥ 400, 313 < 400).
        assertEquals(2, JourneyImageSampling.inSampleSize(1254, 400))
        // Tiny target: quarter (313 ≥ 300 at sample 4? 1254/8=156 < 300 → 4).
        assertEquals(4, JourneyImageSampling.inSampleSize(1254, 300))
        // Degenerate inputs never divide by zero.
        assertEquals(1, JourneyImageSampling.inSampleSize(0, 400))
        assertEquals(1, JourneyImageSampling.inSampleSize(1254, 0))
    }
}

package inc.anky.android.storage

import inc.anky.android.core.storage.AnkyverseCalendar
import inc.anky.android.core.storage.AnkyversePosition
import inc.anky.android.core.storage.AvatarStore
import inc.anky.android.core.storage.SessionIndexStore
import java.io.File
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class AnkyverseCalendarTest {
    @get:Rule val temp = TemporaryFolder()

    private val firstOpen = LocalDate.of(2026, 2, 1)
    private val calendar = AnkyverseCalendar(firstOpen)

    @Test
    fun positionsFollowNinetySixDayCycleOfEightDayRegionsLikeIos() {
        assertEquals(AnkyversePosition(dayIndex = 1, cycleDay = 1, region = 1, dayInRegion = 1), calendar.position(firstOpen))
        assertEquals(AnkyversePosition(dayIndex = 8, cycleDay = 8, region = 1, dayInRegion = 8), calendar.position(firstOpen.plusDays(7)))
        assertEquals(AnkyversePosition(dayIndex = 9, cycleDay = 9, region = 2, dayInRegion = 1), calendar.position(firstOpen.plusDays(8)))
        assertEquals(AnkyversePosition(dayIndex = 96, cycleDay = 96, region = 12, dayInRegion = 8), calendar.position(firstOpen.plusDays(95)))
        assertEquals(AnkyversePosition(dayIndex = 97, cycleDay = 1, region = 1, dayInRegion = 1), calendar.position(firstOpen.plusDays(96)))
    }

    @Test
    fun daysBeforeFirstOpenClampToDayOneLikeIos() {
        assertEquals(
            AnkyversePosition(dayIndex = 1, cycleDay = 1, region = 1, dayInRegion = 1),
            calendar.position(firstOpen.minusDays(3)),
        )
    }

    @Test
    fun sessionDaysCarryAnkyverseRegionAndCycleDay() {
        val firstDay = Instant.parse("2026-02-01T12:00:00Z")

        val days = SessionIndexStore.groupByContinuousDays(
            sessions = emptyList(),
            firstOpen = firstDay,
            now = firstDay.plusSeconds(9L * 24 * 60 * 60),
            zoneId = ZoneOffset.UTC,
        )

        assertEquals(10, days.size)
        assertEquals(1, days.first().region)
        assertEquals(1, days.first().cycleDay)
        assertEquals(1, days.first().dayInRegion)
        assertEquals(2, days.last().region)
        assertEquals(10, days.last().cycleDay)
        assertEquals(2, days.last().dayInRegion)
        assertEquals(10, days.last().dayIndex)
    }

    @Test
    fun avatarStoreSavesLoadsAndDeletesSelfieJpegBytes() {
        val store = AvatarStore.forDirectory(temp.newFolder("files"))
        assertFalse(store.hasAvatar)
        assertNull(store.loadData())

        val bytes = byteArrayOf(0xFF.toByte(), 0xD8.toByte(), 0xFF.toByte(), 1, 2, 3)
        store.save(bytes)

        assertTrue(store.hasAvatar)
        assertTrue(bytes.contentEquals(checkNotNull(store.loadData())))

        store.delete()
        assertFalse(store.hasAvatar)
        assertNull(store.loadData())
    }

    @Test
    fun avatarStoreWritesSingleAvatarJpgFile() {
        val directory = temp.newFolder("files")
        val store = AvatarStore.forDirectory(directory)

        store.save(byteArrayOf(1))
        store.save(byteArrayOf(2))

        assertEquals(listOf("avatar.jpg"), directory.listFiles()!!.map(File::getName))
        assertTrue(byteArrayOf(2).contentEquals(checkNotNull(store.loadData())))
    }
}

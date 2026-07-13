package inc.anky.android.onboarding

import inc.anky.android.feature.onboarding.OnboardingFlowProgress
import inc.anky.android.feature.onboarding.OnboardingFlowState
import inc.anky.android.feature.onboarding.OnboardingJourneyStory
import inc.anky.android.feature.onboarding.OnboardingSwipe
import inc.anky.android.feature.onboarding.PhoneHoursBracket
import inc.anky.android.gate.FakeSharedPreferences
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The pure logic behind the 13-screen onboarding, mirrored against iOS
 * `OnboardingView.swift` (screen constants, `advance`/`retreatFromSwipe`,
 * `wakingYears`, `OnboardingFlowProgress`, `PhoneHoursBracket`,
 * `OnboardingJourneyDay.story(for:)`).
 */
class OnboardingFlowStateTest {

    // MARK: - Screen ordering

    @Test
    fun screensAdvanceOneToElevenThenHandOffToGateSetup() {
        val flow = OnboardingFlowState(isEntitledForGating = { false })

        val visited = mutableListOf(OnboardingFlowState.FirstScreen)
        while (true) {
            val next = flow.nextScreen(visited.last()) ?: break
            visited += next
        }

        assertEquals((1..11).toList(), visited)
        assertNull(flow.nextScreen(OnboardingFlowState.NotificationsScreen))
    }

    @Test
    fun entitledWriterSkipsThePaywallInBothDirections() {
        val flow = OnboardingFlowState(isEntitledForGating = { true })

        assertEquals(11, flow.nextScreen(9))
        assertEquals(9, flow.previousScreen(11))
    }

    @Test
    fun unentitledWriterSeesThePaywallInBothDirections() {
        val flow = OnboardingFlowState(isEntitledForGating = { false })

        assertEquals(10, flow.nextScreen(9))
        assertEquals(10, flow.previousScreen(11))
    }

    @Test
    fun thereIsNoScreenBeforeTheFirst() {
        val flow = OnboardingFlowState()

        assertNull(flow.previousScreen(1))
        assertEquals(1, flow.previousScreen(2))
    }

    @Test
    fun dawnBreaksAtMeetAnkyAndStays() {
        val flow = OnboardingFlowState()

        (1..5).forEach { assertFalse("screen $it is pre-dawn", flow.isDawn(it)) }
        (6..11).forEach { assertTrue("screen $it is dawn", flow.isDawn(it)) }
    }

    @Test
    fun screenConstantsMatchTheIosFlow() {
        assertEquals(6, OnboardingFlowState.DawnStartScreen)
        assertEquals(8, OnboardingFlowState.TargetScreen)
        assertEquals(10, OnboardingFlowState.PaywallScreen)
        assertEquals(11, OnboardingFlowState.ScreenCount)
        assertEquals(12, OnboardingFlowState.GateSetupScreen)
        assertEquals(13, OnboardingFlowState.DayOneThresholdScreen)
    }

    // MARK: - Swipe rules

    @Test
    fun targetScreenOwnsTheDragEntirely() {
        val flow = OnboardingFlowState()

        assertFalse(flow.allowsSwipe(OnboardingFlowState.TargetScreen))
        assertFalse(flow.allowsForwardSwipe(OnboardingFlowState.TargetScreen))
        assertFalse(flow.allowsBackwardSwipe(OnboardingFlowState.TargetScreen))
    }

    @Test
    fun paywallCannotBeSwipedPastButAllowsRetreat() {
        val flow = OnboardingFlowState(isEntitledForGating = { false })

        assertFalse(flow.allowsForwardSwipe(OnboardingFlowState.PaywallScreen))
        assertTrue(flow.allowsBackwardSwipe(OnboardingFlowState.PaywallScreen))
    }

    @Test
    fun lastPagerScreenNeverSwipesForwardAndFirstNeverBack() {
        val flow = OnboardingFlowState()

        assertFalse(flow.allowsForwardSwipe(OnboardingFlowState.NotificationsScreen))
        assertFalse(flow.allowsBackwardSwipe(OnboardingFlowState.FirstScreen))
        assertTrue(flow.allowsForwardSwipe(3))
        assertTrue(flow.allowsBackwardSwipe(3))
    }

    @Test
    fun swipeJudgmentMatchesIosThresholds() {
        // Must travel more than 70 units horizontally.
        assertNull(OnboardingFlowState.swipeDirection(-70f, 0f))
        assertEquals(OnboardingSwipe.Advance, OnboardingFlowState.swipeDirection(-71f, 0f))
        assertEquals(OnboardingSwipe.Retreat, OnboardingFlowState.swipeDirection(90f, 10f))
        // And be decisively horizontal: |x| > |y| * 1.35.
        assertNull(OnboardingFlowState.swipeDirection(-80f, -70f))
        assertEquals(OnboardingSwipe.Advance, OnboardingFlowState.swipeDirection(-95f, -70f))
    }

    // MARK: - The visceral math

    @Test
    fun wakingYearsIsRoundedHoursTimesFortyOverSixteen() {
        assertEquals(4, OnboardingFlowState.wakingYears(PhoneHoursBracket.OneToTwo)) // 1.5h → 3.75
        assertEquals(9, OnboardingFlowState.wakingYears(PhoneHoursBracket.ThreeToFour)) // 3.5h → 8.75
        assertEquals(14, OnboardingFlowState.wakingYears(PhoneHoursBracket.FiveToSix)) // 5.5h → 13.75
        assertEquals(20, OnboardingFlowState.wakingYears(PhoneHoursBracket.SevenPlus)) // 8h → 20
    }

    @Test
    fun wakingYearsFallsBackToThreeAndAHalfHoursAndNeverGoesBelowOne() {
        assertEquals(9, OnboardingFlowState.wakingYears(null))
        assertEquals(1, OnboardingFlowState.wakingYearsFor(0.1))
    }

    @Test
    fun phoneHoursBracketsPersistTheIosRawValues() {
        assertEquals("anky.dailyPhoneHours", PhoneHoursBracket.PreferenceKey)
        assertEquals(
            listOf("1-2", "3-4", "5-6", "7+"),
            PhoneHoursBracket.entries.map { it.rawValue },
        )
        assertEquals(PhoneHoursBracket.FiveToSix, PhoneHoursBracket.fromRawValue("5-6"))
        assertNull(PhoneHoursBracket.fromRawValue("9000"))
    }

    // MARK: - Flow progress persistence

    @Test
    fun progressMarksEveryScreenUnderTheIosKey() {
        val preferences = FakeSharedPreferences()
        val progress = OnboardingFlowProgress(preferences)

        progress.mark(5)
        assertEquals(5, preferences.getInt("anky.onboardingLastScreen", -1))
        assertEquals(5, progress.lastScreen)

        progress.mark(OnboardingFlowState.DayOneThresholdScreen)
        assertEquals(13, progress.lastScreen)

        progress.markFinished()
        assertEquals(0, progress.lastScreen)
    }

    @Test
    fun progressKeyMatchesIos() {
        assertEquals("anky.onboardingLastScreen", OnboardingFlowProgress.Key)
        assertEquals(0, OnboardingFlowProgress.Finished)
    }

    // MARK: - The 8-day journey story

    @Test
    fun journeyStoryHasEightDaysWithIosMilestones() {
        val story = OnboardingJourneyStory.story(null)

        assertEquals(8, story.size)
        assertEquals((1..8).toList(), story.map { it.day })
        assertEquals(
            setOf(1, 3, 7, 8),
            story.filter { it.isMilestone }.map { it.day }.toSet(),
        )
    }

    @Test
    fun givingANameTurnsDaysOneFourAndSixIntoTheThirdPersonStory() {
        val named = OnboardingJourneyStory.story("Pablo")

        assertEquals(
            setOf(1, 4, 6),
            named.filter { it.usesNamedVariant }.map { it.day }.toSet(),
        )
    }

    @Test
    fun blankNamesFallBackToTheSecondPersonStory() {
        assertTrue(OnboardingJourneyStory.story(null).none { it.usesNamedVariant })
        assertTrue(OnboardingJourneyStory.story("   ").none { it.usesNamedVariant })
    }
}

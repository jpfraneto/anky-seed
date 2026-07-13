package inc.anky.android.feature.onboarding

import android.content.SharedPreferences
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.roundToInt

/**
 * Pure logic behind the 13-screen onboarding — a direct port of the state
 * embedded in iOS `OnboardingView.swift` (`AnkyOnboardingView` + the
 * `OnboardingFlowProgress` enum + `PhoneHoursBracket`), extracted into a
 * JVM-testable class the way iOS keeps `OnboardingFlowProgress` separate.
 *
 * Screen map (identical to iOS):
 *   1  The problem            (pre-dawn)
 *   2  The solution           (pre-dawn)
 *   3  The mechanism          (pre-dawn)
 *   4  Phone-hours bracket    (pre-dawn)
 *   5  The visceral math      (pre-dawn)
 *   6  Meet Anky              (dawn)
 *   7  The name + selfie      (dawn)
 *   8  The daily target       (dawn)
 *   9  The 8-day journey      (dawn)
 *   10 The paywall            (dawn; slot)
 *   11 Notifications          (dawn)
 *   12 Gate setup             (slot; lives past the pager)
 *   13 Day 1 threshold        (overlay over the live writing surface)
 *   0  finished
 */
class OnboardingFlowState(
    private val isEntitledForGating: () -> Boolean = { false },
) {

    /** Screens with warm dawn light behind Anky (6+); before that, pre-dawn aubergine. */
    fun isDawn(screen: Int): Boolean = screen >= DawnStartScreen

    /**
     * The next in-view screen after [current], skipping the paywall for a
     * returning subscriber (iOS `advance()`), or null when the eleven
     * in-view screens are done and gate setup (12) follows.
     */
    fun nextScreen(current: Int): Int? {
        var next = current + 1
        if (next == PaywallScreen && isEntitledForGating()) {
            next += 1
        }
        return next.takeIf { it <= ScreenCount }
    }

    /**
     * The previous screen before [current], skipping the paywall backwards
     * for a returning subscriber (iOS `retreatFromSwipe()`), or null at the
     * first screen.
     */
    fun previousScreen(current: Int): Int? {
        var previous = current - 1
        if (previous == PaywallScreen && isEntitledForGating()) {
            previous -= 1
        }
        return previous.takeIf { it >= FirstScreen }
    }

    /** The target screen owns the drag (its slider); no swiping at all there. */
    fun allowsSwipe(current: Int): Boolean = current != TargetScreen

    /** Forward swipes never skip the paywall and never leave the pager (iOS `advanceFromSwipe`). */
    fun allowsForwardSwipe(current: Int): Boolean =
        allowsSwipe(current) && current != PaywallScreen && current < ScreenCount

    fun allowsBackwardSwipe(current: Int): Boolean =
        allowsSwipe(current) && previousScreen(current) != null

    companion object {
        const val FirstScreen = 1
        const val DawnStartScreen = 6
        const val MeetAnkyScreen = 6
        const val NameScreen = 7
        const val TargetScreen = 8
        const val JourneyScreen = 9
        const val PaywallScreen = 10
        const val NotificationsScreen = 11

        /** The screens the pager itself holds (12 and 13 live past it). */
        const val ScreenCount = 11

        const val GateSetupScreen = 12
        const val DayOneThresholdScreen = 13

        /**
         * iOS: `round(hours × 40 / 16)`, floor 1 — a lifetime of adult
         * years spent inside the feed, measured against a 16-hour waking day.
         */
        fun wakingYears(bracket: PhoneHoursBracket?): Int =
            wakingYearsFor(bracket?.midpointHours ?: PhoneHoursBracket.DefaultMidpointHours)

        fun wakingYearsFor(hoursPerDay: Double): Int =
            max(1, (hoursPerDay * 40.0 / 16.0).roundToInt())

        /**
         * iOS swipe judgment (`onboardingSwipeGesture`): the travel must be
         * decisively horizontal — more than 70 units and at least 1.35x the
         * vertical travel. Units are density-independent (iOS points ≈ dp).
         */
        fun swipeDirection(translationX: Float, translationY: Float): OnboardingSwipe? {
            if (abs(translationX) <= 70f) return null
            if (abs(translationX) <= abs(translationY) * 1.35f) return null
            return if (translationX < 0) OnboardingSwipe.Advance else OnboardingSwipe.Retreat
        }
    }
}

enum class OnboardingSwipe { Advance, Retreat }

/**
 * Analytics-free local record of where the flow was left, for physical QA.
 * 1–11 = the in-view screens (10 = paywall), 12 = gate setup, 13 = the
 * Day 1 threshold, 0 = finished. Never leaves the device.
 * Port of the iOS `OnboardingFlowProgress` enum (same key, same values).
 */
class OnboardingFlowProgress(
    private val preferences: SharedPreferences,
) {
    fun mark(screen: Int) {
        preferences.edit().putInt(Key, screen).apply()
    }

    fun markFinished() {
        preferences.edit().putInt(Key, Finished).apply()
    }

    val lastScreen: Int
        get() = preferences.getInt(Key, Finished)

    companion object {
        const val Key = "anky.onboardingLastScreen"
        const val Finished = 0
    }
}

/**
 * Screen 4's honest brackets. Raw values and midpoints match iOS
 * `PhoneHoursBracket` exactly; the chosen raw value persists under
 * `anky.dailyPhoneHours` like iOS `UserDefaults.standard`.
 */
enum class PhoneHoursBracket(val rawValue: String, val midpointHours: Double) {
    OneToTwo("1-2", 1.5),
    ThreeToFour("3-4", 3.5),
    FiveToSix("5-6", 5.5),
    SevenPlus("7+", 8.0),
    ;

    companion object {
        const val PreferenceKey = "anky.dailyPhoneHours"

        /** iOS falls back to 3.5h when no bracket was chosen. */
        const val DefaultMidpointHours = 3.5

        fun fromRawValue(raw: String?): PhoneHoursBracket? =
            entries.firstOrNull { it.rawValue == raw }
    }
}

/**
 * One beat per day of the 8-Day Gate — the story shape of iOS
 * `OnboardingJourneyDay.story(for:)`. The narrative text itself lives in
 * `strings_onboarding.xml`; this type carries the structure (which days are
 * milestones, which lines change when the writer gave a name) so the shape
 * is unit-testable off-device.
 */
data class OnboardingJourneyDay(
    val day: Int,
    val isMilestone: Boolean,
    /** True when the third-person, name-bearing variant of the line applies. */
    val usesNamedVariant: Boolean,
)

object OnboardingJourneyStory {
    const val DayCount = 8

    /** iOS marks days 1, 3, 7 and 8 as milestones in both variants. */
    val MilestoneDays = setOf(1, 3, 7, 8)

    /** Only these lines differ between the named story and the second-person fallback. */
    val NamedVariantDays = setOf(1, 4, 6)

    fun story(name: String?): List<OnboardingJourneyDay> {
        val hasName = !name.isNullOrBlank()
        return (1..DayCount).map { day ->
            OnboardingJourneyDay(
                day = day,
                isMilestone = day in MilestoneDays,
                usesNamedVariant = hasName && day in NamedVariantDays,
            )
        }
    }
}

package inc.anky.android.core.copy

import java.time.Instant
import java.time.ZoneId
import java.util.Locale

/**
 * The copy registry (spec Appendix B): every gate, unlock, ceremony, and
 * top-bar line in one place, so new events can speak through the same
 * voice. Strings are verbatim from the iOS registry; localization to
 * string resources is a later workstream.
 */
object AnkyCopyRegistry {
    // Gate / interception

    /**
     * Rotating gentle headlines; stable within a day so the gate never
     * flickers between moods.
     */
    val gateHeadlines = listOf(
        "write with me first.",
        "one true sentence opens the door.",
        "i'm here. write with me a moment.",
    )

    const val gateHeadlineExhausted =
        "i've opened the door three times today. write with me first."

    fun gateHeadline(
        passesRemaining: Int,
        date: Instant = Instant.now(),
        zoneId: ZoneId = ZoneId.systemDefault(),
    ): String {
        if (passesRemaining <= 0) {
            return gateHeadlineExhausted
        }
        val day = date.atZone(zoneId).toLocalDate().dayOfYear
        return gateHeadlines[day % gateHeadlines.size]
    }

    fun gateFooter(appName: String?): String =
        "${appName ?: "your app"} is waiting behind the door."

    fun gatePassLine(passesRemaining: Int): String =
        "quick pass — one sentence · $passesRemaining left today"

    // Quick Pass

    /** Gate-originated sessions only; organic sessions show nothing. */
    fun quickPassUnlockLine(appName: String?): String =
        "you can now go back to ${(appName ?: "your app").lowercase()} for 15 minutes."

    // The talking top bar

    const val backspaceMessage = "backspace is disabled. keep going."
    const val enterMessage = "formatting doesn't matter. just write."

    // Ceremony

    fun ceremonyTitle(level: Int): String = "WELCOME TO LEVEL $level"

    fun ceremonyLine(paintingTitle: String, seconds: Int): String =
        "“$paintingTitle” — painted from ${formatted(seconds)} seconds of your writing."

    const val ceremonyBegin = "Begin"
    const val generationWait = "Anky is painting…"

    // Journey

    fun journeyDayLabel(day: Int, total: Int): String = "day $day of $total"

    // Adaptive target (phase-2 §1)

    fun adaptiveOfferLine(targetMinutes: Int, suggestedMinutes: Int): String =
        "$targetMinutes minutes has been heavy lately. want to walk with $suggestedMinutes for a while?"

    fun adaptiveOfferLower(suggestedMinutes: Int): String = "walk with $suggestedMinutes"

    fun adaptiveOfferKeep(targetMinutes: Int): String = "keep $targetMinutes"

    // Emergency unlock (phase-2 §2)

    const val emergencyLink = "emergency? open without writing"
    const val emergencyNotificationTitle = "the emergency door"
    const val emergencyNotificationBody = "tap to take one slow breath. everything opens after."

    // Gate off-switch (2026-07-06)
    // One honest exit, one honest confirmation — no dark patterns in
    // either direction.

    const val gateOffLink = "turn the gate off"
    const val gateOffConfirmTitle = "take the door down?"
    const val gateOffConfirmBody =
        "your apps open freely again. the gate waits here whenever you want it back."
    const val gateOffConfirm = "turn it off"
    const val gateOffCancel = "keep the gate"
    const val gateOffStandingCaption = "the gate is off. your apps are open."

    // Free-tier target moment (decision 2026-07-06, option C)
    // Companion, not ransom: no countdowns, no guilt. Shown once per day
    // at seal when a free writer crosses their target.

    const val freeTargetMomentTitle = "your target, reached."
    const val freeTargetMomentLine =
        "you wrote what you set out to write today. that is the whole practice."
    const val freeTargetMomentSubscriberLine =
        "for subscribers, this is the moment the day opens — the phone unlocks until midnight, because the writing already happened."
    const val freeTargetMomentCTA = "start 3 free days"
    const val freeTargetMomentDismiss = "not now"

    // Reflection loading (phase-2 §7)

    const val reflectionWait = "anky is reading…"

    // Home Screen quick action (phase-2 §3)

    const val quickActionUnfinished = "your painting is still unfinished"
    const val quickActionNewPainting = "a new painting is waiting"

    fun quickActionProgressLine(percent: Int, level: Int): String = "$percent% — level $level"

    fun quickActionNewLevelLine(level: Int): String = "level $level — 0%"

    // Trial surface (phase-2 §5)

    const val trialSurfaceHeadline = "anky has already begun your painting."

    fun trialSurfaceTrialLine(days: Int, price: String): String =
        "$days day${if (days == 1) "" else "s"} free — then $price/year"

    fun trialSurfacePriceLine(price: String): String = "$price/year"

    // Privacy disclosure (spec §3.1)

    const val paintingDisclosure =
        "Your level paintings are created from a distilled reflection of your writing — never the writing itself. Nothing is stored after the painting is made, same as your reflections."

    // The veils (phase-3 §3) — *not yet*, never *denied*

    const val veilReflection = "anky read this. subscribe to see what he saw."
    const val veilCeremony = "your next painting is ready to begin."
    const val veilJourney = "the journey opens with anky."

    // Boundary-truthful ambient surfaces (phase-3 §5)

    const val boundaryWidgetLine = "a new painting waits"
    const val boundaryQuickAction = "a new painting is waiting — with anky+"

    // Paywall sheet (phase-3 §4)

    const val paywallSheetTitle = "the deepening"
    const val paywallSheetVoiceLine =
        "the mirror, the paintings, the journey, the daily door — they open together."

    /** Mirror of Swift's `Int.formatted()` grouping (e.g. 1,234). */
    private fun formatted(value: Int): String =
        String.format(Locale.US, "%,d", value)
}

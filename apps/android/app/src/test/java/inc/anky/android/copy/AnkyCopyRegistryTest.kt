package inc.anky.android.copy

import inc.anky.android.core.copy.AnkyCopyRegistry
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneOffset
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The registry is the single voice of the gate — these tests pin the copy
 * verbatim to the iOS AnkyCopyRegistry.swift and the headline rotation law
 * (stable within a day, exhausted framing wins).
 */
class AnkyCopyRegistryTest {
    private val zone = ZoneOffset.UTC

    private fun at(year: Int, month: Int, day: Int, hour: Int = 0): Instant =
        LocalDateTime.of(year, month, day, hour, 0).atZone(zone).toInstant()

    @Test
    fun gateHeadlineIsStableWithinADayAndRotatesAcrossDays() {
        val morning = at(2026, 7, 6, hour = 8)
        val evening = at(2026, 7, 6, hour = 22)
        assertEquals(
            AnkyCopyRegistry.gateHeadline(passesRemaining = 3, date = morning, zoneId = zone),
            AnkyCopyRegistry.gateHeadline(passesRemaining = 3, date = evening, zoneId = zone),
        )

        val threeDays = (0..2).map { offset ->
            AnkyCopyRegistry.gateHeadline(
                passesRemaining = 3,
                date = at(2026, 7, 6 + offset, hour = 12),
                zoneId = zone,
            )
        }
        assertEquals(AnkyCopyRegistry.gateHeadlines.toSet(), threeDays.toSet())
    }

    @Test
    fun gateHeadlineExhaustionFramingWins() {
        assertEquals(
            "i've opened the door three times today. write with me first.",
            AnkyCopyRegistry.gateHeadline(passesRemaining = 0, date = at(2026, 7, 6), zoneId = zone),
        )
    }

    @Test
    fun gateFooterAndPassLine() {
        assertEquals(
            "Instagram is waiting behind the door.",
            AnkyCopyRegistry.gateFooter("Instagram"),
        )
        assertEquals(
            "your app is waiting behind the door.",
            AnkyCopyRegistry.gateFooter(null),
        )
        assertEquals(
            "quick pass — one sentence · 2 left today",
            AnkyCopyRegistry.gatePassLine(passesRemaining = 2),
        )
    }

    @Test
    fun quickPassUnlockLineLowercasesTheAppName() {
        assertEquals(
            "you can now go back to instagram for 15 minutes.",
            AnkyCopyRegistry.quickPassUnlockLine("Instagram"),
        )
        assertEquals(
            "you can now go back to your app for 15 minutes.",
            AnkyCopyRegistry.quickPassUnlockLine(null),
        )
    }

    @Test
    fun talkingTopBarLines() {
        assertEquals("backspace is disabled. keep going.", AnkyCopyRegistry.backspaceMessage)
        assertEquals("formatting doesn't matter. just write.", AnkyCopyRegistry.enterMessage)
    }

    @Test
    fun ceremonyLines() {
        assertEquals("WELCOME TO LEVEL 3", AnkyCopyRegistry.ceremonyTitle(3))
        assertEquals(
            "“The Quiet Door” — painted from 1,234 seconds of your writing.",
            AnkyCopyRegistry.ceremonyLine(paintingTitle = "The Quiet Door", seconds = 1234),
        )
        assertEquals("Begin", AnkyCopyRegistry.ceremonyBegin)
        assertEquals("Anky is painting…", AnkyCopyRegistry.generationWait)
        assertEquals("day 2 of 8", AnkyCopyRegistry.journeyDayLabel(day = 2, total = 8))
    }

    @Test
    fun adaptiveTargetOfferLines() {
        assertEquals(
            "8 minutes has been heavy lately. want to walk with 4 for a while?",
            AnkyCopyRegistry.adaptiveOfferLine(targetMinutes = 8, suggestedMinutes = 4),
        )
        assertEquals("walk with 4", AnkyCopyRegistry.adaptiveOfferLower(4))
        assertEquals("keep 8", AnkyCopyRegistry.adaptiveOfferKeep(8))
    }

    @Test
    fun emergencyLines() {
        assertEquals("emergency? open without writing", AnkyCopyRegistry.emergencyLink)
        assertEquals("the emergency door", AnkyCopyRegistry.emergencyNotificationTitle)
        assertEquals(
            "tap to take one slow breath. everything opens after.",
            AnkyCopyRegistry.emergencyNotificationBody,
        )
    }

    @Test
    fun gateOffSwitchSet() {
        assertEquals("turn the gate off", AnkyCopyRegistry.gateOffLink)
        assertEquals("take the door down?", AnkyCopyRegistry.gateOffConfirmTitle)
        assertEquals(
            "your apps open freely again. the gate waits here whenever you want it back.",
            AnkyCopyRegistry.gateOffConfirmBody,
        )
        assertEquals("turn it off", AnkyCopyRegistry.gateOffConfirm)
        assertEquals("keep the gate", AnkyCopyRegistry.gateOffCancel)
        assertEquals("the gate is off. your apps are open.", AnkyCopyRegistry.gateOffStandingCaption)
    }

    @Test
    fun freeTargetMomentSet() {
        assertEquals("your target, reached.", AnkyCopyRegistry.freeTargetMomentTitle)
        assertEquals(
            "you wrote what you set out to write today. that is the whole practice.",
            AnkyCopyRegistry.freeTargetMomentLine,
        )
        assertEquals(
            "for subscribers, this is the moment the day opens — the phone unlocks until midnight, because the writing already happened.",
            AnkyCopyRegistry.freeTargetMomentSubscriberLine,
        )
        assertEquals("start 3 free days", AnkyCopyRegistry.freeTargetMomentCTA)
        assertEquals("not now", AnkyCopyRegistry.freeTargetMomentDismiss)
    }

    @Test
    fun veilAndBoundaryAndPaywallLines() {
        assertEquals("anky is reading…", AnkyCopyRegistry.reflectionWait)
        assertEquals("anky read this. subscribe to see what he saw.", AnkyCopyRegistry.veilReflection)
        assertEquals("your next painting is ready to begin.", AnkyCopyRegistry.veilCeremony)
        assertEquals("the journey opens with anky.", AnkyCopyRegistry.veilJourney)
        assertEquals("a new painting waits", AnkyCopyRegistry.boundaryWidgetLine)
        assertEquals("a new painting is waiting — with anky+", AnkyCopyRegistry.boundaryQuickAction)
        assertEquals("the deepening", AnkyCopyRegistry.paywallSheetTitle)
        assertEquals(
            "the mirror, the paintings, the journey, the daily door — they open together.",
            AnkyCopyRegistry.paywallSheetVoiceLine,
        )
    }

    @Test
    fun quickActionAndTrialLines() {
        assertEquals("your painting is still unfinished", AnkyCopyRegistry.quickActionUnfinished)
        assertEquals("a new painting is waiting", AnkyCopyRegistry.quickActionNewPainting)
        assertEquals("42% — level 3", AnkyCopyRegistry.quickActionProgressLine(percent = 42, level = 3))
        assertEquals("level 4 — 0%", AnkyCopyRegistry.quickActionNewLevelLine(level = 4))
        assertEquals("anky has already begun your painting.", AnkyCopyRegistry.trialSurfaceHeadline)
        assertEquals("3 days free — then $39.99/year", AnkyCopyRegistry.trialSurfaceTrialLine(3, "$39.99"))
        assertEquals("1 day free — then $39.99/year", AnkyCopyRegistry.trialSurfaceTrialLine(1, "$39.99"))
        assertEquals("$39.99/year", AnkyCopyRegistry.trialSurfacePriceLine("$39.99"))
    }

    @Test
    fun paintingPrivacyDisclosureIsVerbatim() {
        assertTrue(AnkyCopyRegistry.paintingDisclosure.startsWith("Your level paintings are created"))
        assertTrue(AnkyCopyRegistry.paintingDisclosure.contains("never the writing itself"))
        assertTrue(AnkyCopyRegistry.paintingDisclosure.endsWith("same as your reflections."))
    }
}

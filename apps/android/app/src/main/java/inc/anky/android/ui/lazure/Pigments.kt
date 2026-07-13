package inc.anky.android.ui.lazure

import androidx.compose.runtime.Immutable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.colorspace.ColorSpaces

/**
 * Lazure — a design system painted the way Steiner painted.
 *
 * Lazure (Lasur) is wet-on-wet layering: color is never applied flat,
 * it is *breathed* onto the surface in translucent veils. Nothing has
 * a hard edge. Nothing is pure white or pure black. Every surface is
 * alive with slow movement of tone.
 *
 * Four rules enforced by this package (port of iOS `AnkyLazure.swift`):
 *  1. NO FLAT FILLS.   Every background is a wash (gradient), even buttons.
 *  2. NO PURE VALUES.  White -> tinted paper. Black -> deep violet ink.
 *  3. NO HARD SHADOWS. Shadows are colored (violet), soft, and low.
 *  4. EVERYTHING BREATHES. Ambient motion cycles at 8 seconds — the
 *     same 8s of silence that seals a writing session.
 *
 * Hairline edges are 0.5dp of [LazurePigments.ankyInk] at ~0.08 alpha.
 */
private fun p3(red: Float, green: Float, blue: Float): Color =
    Color(red = red, green = green, blue = blue, alpha = 1f, colorSpace = ColorSpaces.DisplayP3)

/**
 * Watercolor pigments, not "brand colors."
 *
 * All defined in Display P3 (matching the iOS `Color(.displayP3, ...)`
 * definitions exactly), all desaturated the way real pigment sinks into
 * wet paper.
 */
object LazurePigments {

    /** The paper itself — warm ivory. Never use pure white anywhere in the app. */
    val ankyPaper = p3(0.965f, 0.937f, 0.894f)

    /** Where washes pool. */
    val ankyPaperDeep = p3(0.929f, 0.882f, 0.835f)

    /** The ink — deep violet-slate. Never use pure black anywhere in the app. */
    val ankyInk = p3(0.239f, 0.216f, 0.310f)

    /** Secondary text. */
    val ankyInkSoft = p3(0.396f, 0.369f, 0.475f)

    /** The writing ink — warm umber, sepia on parchment. */
    val ankyUmber = p3(0.310f, 0.243f, 0.180f)

    /** Anky's own skin — the blue-slate of the character. */
    val ankySlate = p3(0.353f, 0.427f, 0.514f)

    /** The curls and vest — muted violet. Also the color of every shadow. */
    val ankyViolet = p3(0.478f, 0.392f, 0.541f)

    /** The warmth entering from above — apricot and the spiral sun. */
    val ankyApricot = p3(0.918f, 0.741f, 0.573f)

    /** Jewelry, accents. */
    val ankyGold = p3(0.878f, 0.694f, 0.427f)

    /** The thread of light. */
    val ankyGoldLight = p3(0.965f, 0.847f, 0.631f)

    /** The green that hides in the background washes. */
    val ankySage = p3(0.678f, 0.714f, 0.604f)

    /** The rose that blushes at the edges. */
    val ankyRose = p3(0.851f, 0.671f, 0.647f)

    /** The one warning pigment — madder, never firetruck red. */
    val ankyMadder = p3(0.702f, 0.325f, 0.302f)

    /** Hairline edge: 0.5dp of this over any veil (iOS `ankyInk.opacity(0.08)`). */
    val hairline: Color get() = ankyInk.copy(alpha = 0.08f)
}

/**
 * Role tokens — the semantic remap the iOS app keeps in `AnkyTheme.swift`
 * ("legacy token names, now resolved to the lazure pigments"). Screens
 * should reach for roles, not raw pigments, wherever a role exists.
 *
 * Provided through [LocalLazureRoles] by [LazureTheme].
 */
@Immutable
data class LazureRoles(
    val background: Color = LazurePigments.ankyPaper,
    val panel: Color = LazurePigments.ankyPaperDeep.copy(alpha = 0.62f),
    val panelStrong: Color = LazurePigments.ankyPaperDeep,
    val border: Color = LazurePigments.ankyInk.copy(alpha = 0.10f),
    val gold: Color = LazurePigments.ankyGold,
    val goldBright: Color = LazurePigments.ankyGoldLight,
    val text: Color = LazurePigments.ankyInk,
    val textMuted: Color = LazurePigments.ankyInkSoft,
    val success: Color = LazurePigments.ankySage,
    val danger: Color = LazurePigments.ankyMadder,
)

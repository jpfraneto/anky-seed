package inc.anky.android.ui.lazure

import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.DeviceFontFamilyName
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.sp

/**
 * Letterforms — port of the iOS `Font.anky*` set (`AnkyLazure.swift` §7).
 *
 * Steiner's world is humanist: serifs for what is *said*, warmth for
 * what is *done*. iOS uses New York (Apple's serif); Android uses the
 * platform serif ([FontFamily.Serif], Noto Serif on stock devices) —
 * the same role, the native hand.
 *
 * Sizes mirror the iOS Dynamic Type styles at their default point sizes:
 * largeTitle 34, title3 20, body 17, subheadline 15, caption 12.
 * Styles carry no color: pair them with [LazureRoles.text] /
 * [LazureRoles.textMuted] so the ink stays the ink.
 */
object LazureType {

    /** Screen titles — serif, light, generous (iOS `.ankyTitle`). */
    val ankyTitle = TextStyle(
        fontFamily = FontFamily.Serif,
        fontWeight = FontWeight.Normal,
        fontSize = 34.sp,
        lineHeight = 41.sp,
    )

    /** Section headings (iOS `.ankyHeading`). */
    val ankyHeading = TextStyle(
        fontFamily = FontFamily.Serif,
        fontWeight = FontWeight.Medium,
        fontSize = 20.sp,
        lineHeight = 25.sp,
    )

    /** The user's own writing & Anky's reflections (iOS `.ankyProse`). */
    val ankyProse = TextStyle(
        fontFamily = FontFamily.Serif,
        fontWeight = FontWeight.Normal,
        fontSize = 17.sp,
        lineHeight = 24.sp,
    )

    /** UI chrome, labels, counts — sans, never shouting (iOS `.ankyLabel`). */
    val ankyLabel = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.Medium,
        fontSize = 15.sp,
        lineHeight = 20.sp,
    )

    /** Tiny captions under things (iOS `.ankyCaption`). */
    val ankyCaption = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.Normal,
        fontSize = 12.sp,
        lineHeight = 16.sp,
    )

    /** Buttons (iOS `.ankyAction`). */
    val ankyAction = TextStyle(
        fontFamily = FontFamily.Serif,
        fontWeight = FontWeight.SemiBold,
        fontSize = 17.sp,
        lineHeight = 22.sp,
    )
}

/**
 * The five hands Anky can write in — port of `AnkyWritingFontChoice`
 * (raw values match the iOS `Codable` enum, which is what the writing
 * preferences store persists). This package deliberately owns its own
 * copy of the enum: the storage layer can map to it via [fromStoredValue]
 * without either module importing the other.
 *
 * Android font mapping (iOS face -> Android face), documented per choice:
 *  - Quill (New York serif)        -> [FontFamily.Serif] (Noto Serif).
 *  - Georgia (rounder book serif)  -> [FontFamily.Serif]. Georgia does not
 *    ship on Android; the platform has a single system serif, so Quill and
 *    Georgia share a face here.
 *  - Round (SF Rounded)            -> device family `"sans-serif-rounded"`
 *    when present, silently falling back to the default sans (Roboto) —
 *    the lookup is optional-local, never a crash.
 *  - Plain (system sans)           -> [FontFamily.SansSerif].
 *  - Typewriter (American Typewriter, a slab serif) -> device family
 *    `"serif-monospace"` (Cutive Mono on stock Android — genuinely
 *    typewriter-flavored), optional-local with default fallback.
 */
enum class AnkyWritingFont(val storedValue: String, val displayName: String) {
    Quill("quill", "Quill"),
    Georgia("georgia", "Georgia"),
    Round("round", "Round"),
    Plain("plain", "Plain"),
    Typewriter("typewriter", "Typewriter");

    companion object {
        /** The default hand, matching iOS `AnkyWritingFontChoice.default`. */
        val Default = Quill

        /** Maps a persisted raw value; unknown/absent values fall back to [Default]. */
        fun fromStoredValue(raw: String?): AnkyWritingFont =
            entries.firstOrNull { it.storedValue == raw } ?: Default
    }
}

/**
 * The writing text size, in steps rather than a free slider so every
 * choice is one a book designer would have made. Port of
 * `AnkyWritingTextSize` (raw values and point sizes match iOS exactly).
 */
enum class AnkyWritingTextSize(
    val storedValue: String,
    val size: TextUnit,
    val displayName: String,
) {
    Small("small", 18.sp, "Small"),
    Medium("medium", 21.sp, "Medium"),
    Large("large", 24.sp, "Large"),
    Grand("grand", 28.sp, "Grand");

    companion object {
        val Default = Medium

        fun fromStoredValue(raw: String?): AnkyWritingTextSize =
            entries.firstOrNull { it.storedValue == raw } ?: Default
    }
}

/** Resolves the [FontFamily] for a writing hand (see [AnkyWritingFont] for the mapping). */
fun fontFamilyFor(choice: AnkyWritingFont): FontFamily = when (choice) {
    AnkyWritingFont.Quill -> FontFamily.Serif
    AnkyWritingFont.Georgia -> FontFamily.Serif
    AnkyWritingFont.Round -> FontFamily(Font(DeviceFontFamilyName("sans-serif-rounded")))
    AnkyWritingFont.Plain -> FontFamily.SansSerif
    AnkyWritingFont.Typewriter -> FontFamily(Font(DeviceFontFamilyName("serif-monospace")))
}

/** Convenience for callers holding only the persisted raw value. */
fun fontFamilyFor(storedValue: String?): FontFamily =
    fontFamilyFor(AnkyWritingFont.fromStoredValue(storedValue))

/**
 * The full writing-surface style: the chosen hand at the chosen step,
 * in umber ink coloration left to the caller (sepia pass pairs it with
 * [LazurePigments.ankyUmber]).
 */
fun writingTextStyle(
    choice: AnkyWritingFont = AnkyWritingFont.Default,
    size: AnkyWritingTextSize = AnkyWritingTextSize.Default,
): TextStyle = TextStyle(
    fontFamily = fontFamilyFor(choice),
    fontWeight = FontWeight.Normal,
    fontSize = size.size,
    lineHeight = size.size * 1.4f,
)

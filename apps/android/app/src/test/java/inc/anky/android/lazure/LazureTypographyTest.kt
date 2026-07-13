package inc.anky.android.lazure

import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import inc.anky.android.ui.lazure.AnkyWritingFont
import inc.anky.android.ui.lazure.AnkyWritingTextSize
import inc.anky.android.ui.lazure.LazureType
import inc.anky.android.ui.lazure.fontFamilyFor
import inc.anky.android.ui.lazure.writingTextStyle
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Test

class LazureTypographyTest {

    @Test
    fun serifSpeaksAndSansLabels() {
        assertEquals(FontFamily.Serif, LazureType.ankyTitle.fontFamily)
        assertEquals(FontFamily.Serif, LazureType.ankyHeading.fontFamily)
        assertEquals(FontFamily.Serif, LazureType.ankyProse.fontFamily)
        assertEquals(FontFamily.Serif, LazureType.ankyAction.fontFamily)
        assertEquals(FontFamily.SansSerif, LazureType.ankyLabel.fontFamily)
        assertEquals(FontFamily.SansSerif, LazureType.ankyCaption.fontFamily)
        assertEquals(FontWeight.SemiBold, LazureType.ankyAction.fontWeight)
        assertEquals(FontWeight.Medium, LazureType.ankyLabel.fontWeight)
    }

    @Test
    fun storedValuesMatchTheIosRawValues() {
        assertEquals("quill", AnkyWritingFont.Quill.storedValue)
        assertEquals("georgia", AnkyWritingFont.Georgia.storedValue)
        assertEquals("round", AnkyWritingFont.Round.storedValue)
        assertEquals("plain", AnkyWritingFont.Plain.storedValue)
        assertEquals("typewriter", AnkyWritingFont.Typewriter.storedValue)
        assertEquals(5, AnkyWritingFont.entries.size)
    }

    @Test
    fun unknownStoredValueFallsBackToQuill() {
        assertEquals(AnkyWritingFont.Quill, AnkyWritingFont.fromStoredValue(null))
        assertEquals(AnkyWritingFont.Quill, AnkyWritingFont.fromStoredValue("wingdings"))
        assertEquals(AnkyWritingFont.Typewriter, AnkyWritingFont.fromStoredValue("typewriter"))
        assertEquals(AnkyWritingFont.Quill, AnkyWritingFont.Default)
    }

    @Test
    fun handsResolveToTheDocumentedFamilies() {
        assertEquals(FontFamily.Serif, fontFamilyFor(AnkyWritingFont.Quill))
        assertEquals(FontFamily.Serif, fontFamilyFor(AnkyWritingFont.Georgia))
        assertEquals(FontFamily.SansSerif, fontFamilyFor(AnkyWritingFont.Plain))
        // Round and Typewriter resolve through optional device families
        // with silent fallbacks; here we only assert they construct.
        assertNotNull(fontFamilyFor(AnkyWritingFont.Round))
        assertNotNull(fontFamilyFor(AnkyWritingFont.Typewriter))
        assertEquals(FontFamily.Serif, fontFamilyFor("quill"))
        assertEquals(FontFamily.SansSerif, fontFamilyFor("plain"))
        assertEquals(FontFamily.Serif, fontFamilyFor(null))
    }

    @Test
    fun writingSizesMatchTheIosPointSteps() {
        assertEquals(18.sp, AnkyWritingTextSize.Small.size)
        assertEquals(21.sp, AnkyWritingTextSize.Medium.size)
        assertEquals(24.sp, AnkyWritingTextSize.Large.size)
        assertEquals(28.sp, AnkyWritingTextSize.Grand.size)
        assertEquals(AnkyWritingTextSize.Medium, AnkyWritingTextSize.Default)
        assertEquals(AnkyWritingTextSize.Grand, AnkyWritingTextSize.fromStoredValue("grand"))
        assertEquals(AnkyWritingTextSize.Medium, AnkyWritingTextSize.fromStoredValue("huge"))
    }

    @Test
    fun writingStyleCombinesHandAndStep() {
        val style = writingTextStyle(AnkyWritingFont.Plain, AnkyWritingTextSize.Large)
        assertEquals(FontFamily.SansSerif, style.fontFamily)
        assertEquals(24.sp, style.fontSize)
    }
}

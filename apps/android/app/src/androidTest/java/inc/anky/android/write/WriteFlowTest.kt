package inc.anky.android.write

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performTextInput
import inc.anky.android.MainActivity
import org.junit.Rule
import org.junit.Test

class WriteFlowTest {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()

    @Test
    fun appOpensToWriteAndAcceptsSingleGlyph() {
        compose.onNodeWithTag("write-screen").assertIsDisplayed()
        compose.onNodeWithTag("write-input").performTextInput("h")
        compose.onNodeWithTag("ritual-glyph").assertIsDisplayed()
    }

    @Test
    fun multiCharacterPasteDoesNotReplaceRitualGlyph() {
        compose.onNodeWithTag("write-input").performTextInput("h")
        compose.onNodeWithTag("write-input").performTextInput("paste")
        compose.onNodeWithTag("ritual-glyph").assertIsDisplayed()
    }
}

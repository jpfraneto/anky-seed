package inc.anky.android.reveal

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import inc.anky.android.MainActivity
import org.junit.Rule
import org.junit.Test

class YouFlowTest {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()

    @Test
    fun youShowsPublicKeySurface() {
        compose.onNodeWithText("You").performClick()
        compose.onNodeWithTag("you-screen").assertIsDisplayed()
        compose.onNodeWithTag("public-key").assertIsDisplayed()
    }
}

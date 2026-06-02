package inc.anky.android.reveal

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import inc.anky.android.MainActivity
import org.junit.Rule
import org.junit.Test

class YouFlowTest {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()

    @Test
    fun youTabOpensIdentitySurface() {
        compose.onNodeWithContentDescription("Open Map").performClick()
        compose.waitUntil {
            compose.onAllNodesWithText("You").fetchSemanticsNodes().isNotEmpty()
        }
        compose.onNodeWithText("You").performClick()
        compose.onNodeWithTag("you-screen").assertIsDisplayed()
        compose.onNodeWithText("identity").assertIsDisplayed()
    }
}

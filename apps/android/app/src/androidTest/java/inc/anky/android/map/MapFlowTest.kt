package inc.anky.android.map

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import inc.anky.android.MainActivity
import org.junit.Rule
import org.junit.Test

class MapFlowTest {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()

    @Test
    fun writeChromeOpensMapSurface() {
        compose.onNodeWithContentDescription("Open Map").performClick()
        compose.waitUntil {
            compose.onAllNodesWithText("Map").fetchSemanticsNodes().isNotEmpty()
        }
        compose.onNodeWithText("Map").assertIsDisplayed()
    }
}

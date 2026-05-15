package inc.anky.android.map

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import inc.anky.android.MainActivity
import org.junit.Rule
import org.junit.Test

class MapFlowTest {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()

    @Test
    fun mapTabOpensLocalArchiveSurface() {
        compose.onNodeWithText("Map").performClick()
        compose.onNodeWithText("No local ankys yet.").assertIsDisplayed()
    }
}

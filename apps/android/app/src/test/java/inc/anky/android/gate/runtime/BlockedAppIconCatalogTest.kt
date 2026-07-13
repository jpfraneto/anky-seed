package inc.anky.android.gate.runtime

import inc.anky.android.feature.gate.BlockedAppIconCatalog
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class BlockedAppIconCatalogTest {

    @Test
    fun `maps the sixteen curated packages exactly`() {
        val expected = mapOf(
            "com.instagram.android" to "blocked_instagram",
            "com.twitter.android" to "blocked_x",
            "com.zhiliaoapp.musically" to "blocked_tiktok",
            "com.google.android.youtube" to "blocked_youtube",
            "com.whatsapp" to "blocked_whatsapp",
            "com.android.chrome" to "blocked_chrome",
            "com.facebook.katana" to "blocked_facebook",
            "com.spotify.music" to "blocked_spotify",
            "com.snapchat.android" to "blocked_snapchat",
            "com.netflix.mediaclient" to "blocked_netflix",
            "com.reddit.frontpage" to "blocked_reddit",
            "com.linkedin.android" to "blocked_linkedin",
            "com.discord" to "blocked_discord",
            "com.openai.chatgpt" to "blocked_chatgpt",
            "com.anthropic.claude" to "blocked_claude",
            "org.telegram.messenger" to "blocked_telegram",
        )
        expected.forEach { (packageName, iconName) ->
            assertEquals(packageName, iconName, BlockedAppIconCatalog.iconName(packageName))
        }
    }

    @Test
    fun `fuzzy-matches unknown package variants, like the iOS catalog`() {
        assertEquals("blocked_tiktok", BlockedAppIconCatalog.iconName("com.ss.android.ugc.trill"))
        assertEquals("blocked_instagram", BlockedAppIconCatalog.iconName("com.instagram.lite"))
        assertEquals("blocked_facebook", BlockedAppIconCatalog.iconName("com.facebook.lite"))
        assertEquals("blocked_telegram", BlockedAppIconCatalog.iconName("org.telegram.messenger.web"))
    }

    @Test
    fun `matches on the label when the package says nothing`() {
        assertEquals(
            "blocked_x",
            BlockedAppIconCatalog.iconName("com.example.mystery", label = "X"),
        )
        assertEquals(
            "blocked_youtube",
            BlockedAppIconCatalog.iconName("com.example.mystery", label = "YouTube"),
        )
    }

    @Test
    fun `unrecognized apps fall back to their real icon`() {
        assertNull(BlockedAppIconCatalog.iconName("com.example.calculator", label = "Calculator"))
        // "x" must match exactly, never fuzzily (iOS guard: identifiers ≤ 2 chars).
        assertNull(BlockedAppIconCatalog.iconName("com.example.xylophone", label = "Xylophone"))
    }

    @Test
    fun `preselection is social apps only — never the browser or messenger`() {
        assertTrue("com.instagram.android" in BlockedAppIconCatalog.preselectedPackages)
        assertTrue("com.twitter.android" in BlockedAppIconCatalog.preselectedPackages)
        assertTrue("com.android.chrome" !in BlockedAppIconCatalog.preselectedPackages)
        assertTrue("com.whatsapp" !in BlockedAppIconCatalog.preselectedPackages)
    }
}

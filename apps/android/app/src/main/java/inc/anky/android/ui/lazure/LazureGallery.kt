package inc.anky.android.ui.lazure

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import inc.anky.android.BuildConfig

/**
 * DEBUG-only visual QA sheet: every lazure component on one scrolling
 * wall, with a mood cycler. Not wired to any navigation; point a debug
 * activity or a preview at it when retheming begins. Renders nothing in
 * release builds.
 */
@Composable
fun LazureGallery() {
    if (!BuildConfig.DEBUG) return

    var moodIndex by remember { mutableIntStateOf(0) }
    val moods = listOf<Pair<String, LazureMood>>(
        "dawn" to LazureMood.Dawn,
        "dusk" to LazureMood.Dusk,
        "kingdom(sage)" to LazureMood.Kingdom(LazurePigments.ankySage),
    )
    val (moodName, mood) = moods[moodIndex % moods.size]

    LazureTheme {
        Box(Modifier.fillMaxSize()) {
            LazureWall(mood = mood)

            Column(
                Modifier
                    .fillMaxSize()
                    .verticalScroll(rememberScrollState())
                    .padding(20.dp),
                verticalArrangement = Arrangement.spacedBy(20.dp),
            ) {
                Text("Lazure", style = LazureType.ankyTitle, color = LazurePigments.ankyInk)
                Text(
                    "Everything on this sheet breathes on the same 8s clock.",
                    style = LazureType.ankyProse,
                    color = LazurePigments.ankyInkSoft,
                )

                WashButton(text = "mood: $moodName", onClick = { moodIndex += 1 })

                GallerySection("Pigments") {
                    PigmentRow(
                        "ankyPaper" to LazurePigments.ankyPaper,
                        "ankyPaperDeep" to LazurePigments.ankyPaperDeep,
                        "ankyInk" to LazurePigments.ankyInk,
                        "ankyInkSoft" to LazurePigments.ankyInkSoft,
                        "ankyUmber" to LazurePigments.ankyUmber,
                    )
                    PigmentRow(
                        "ankySlate" to LazurePigments.ankySlate,
                        "ankyViolet" to LazurePigments.ankyViolet,
                        "ankyApricot" to LazurePigments.ankyApricot,
                        "ankyGold" to LazurePigments.ankyGold,
                    )
                    PigmentRow(
                        "ankyGoldLight" to LazurePigments.ankyGoldLight,
                        "ankySage" to LazurePigments.ankySage,
                        "ankyRose" to LazurePigments.ankyRose,
                        "ankyMadder" to LazurePigments.ankyMadder,
                    )
                }

                GallerySection("Letterforms") {
                    Text("ankyTitle", style = LazureType.ankyTitle, color = LazurePigments.ankyInk)
                    Text("ankyHeading", style = LazureType.ankyHeading, color = LazurePigments.ankyInk)
                    Text(
                        "ankyProse — the user's own writing and Anky's reflections.",
                        style = LazureType.ankyProse,
                        color = LazurePigments.ankyInk,
                    )
                    Text("ankyLabel", style = LazureType.ankyLabel, color = LazurePigments.ankyInkSoft)
                    Text("ankyCaption", style = LazureType.ankyCaption, color = LazurePigments.ankyInkSoft)
                    LazureDivider()
                    AnkyWritingFont.entries.forEach { hand ->
                        Text(
                            "${hand.displayName} — eight quiet minutes",
                            style = writingTextStyle(hand, AnkyWritingTextSize.Small),
                            color = LazurePigments.ankyUmber,
                        )
                    }
                }

                VeilCard {
                    Text("VeilCard", style = LazureType.ankyHeading, color = LazurePigments.ankyInk)
                    Text(
                        "A translucent veil of pigment; the wall bleeds through.",
                        style = LazureType.ankyProse,
                        color = LazurePigments.ankyInkSoft,
                    )
                    LazureDivider(Modifier.padding(vertical = 12.dp))
                    Row(
                        Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        AnkySunGlyph(size = 28.dp)
                        AnkySunGlyph(size = 44.dp, color = LazurePigments.ankyViolet)
                        AnkySunGlyph(size = 60.dp, color = LazurePigments.ankyApricot)
                    }
                }

                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    ThreadButton(text = "Thread", onClick = {})
                    WashButton(text = "Wash", onClick = {})
                }

                GallerySection("Veiled feature") {
                    VeiledFeature(
                        surface = "gallery",
                        message = "Your reflection is waiting on the other side.",
                        onTap = {},
                    ) {
                        ReflectionGhost()
                    }
                }

                GallerySection("Watercolor veil") {
                    Box(
                        Modifier
                            .fillMaxWidth()
                            .height(180.dp)
                            .clip(VeilShape)
                            .background(LazurePigments.ankyPaper),
                    ) {
                        WatercolorVeil(message = "pale register")
                    }
                    Box(
                        Modifier
                            .fillMaxWidth()
                            .height(180.dp)
                            .clip(VeilShape)
                            .background(LazurePigments.ankyInk),
                    ) {
                        WatercolorVeil(
                            message = "aubergine register",
                            register = WatercolorVeilRegister.Aubergine,
                        )
                    }
                }

                GallerySection("Ankyverse days") {
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        (1..8).forEach { day ->
                            Box(
                                Modifier
                                    .size(34.dp)
                                    .clip(CircleShape)
                                    .background(AnkyverseDayPalette.color(day)),
                                contentAlignment = Alignment.Center,
                            ) {
                                Text(
                                    "$day",
                                    style = LazureType.ankyCaption,
                                    color = AnkyverseDayPalette.symbolColor(day),
                                )
                            }
                        }
                    }
                }

                GallerySection("LevelTheme") {
                    val theme = LevelTheme.fromPalette(
                        listOf("#2b1d3a", "#4a3357", "#7a5a63", "#b98a5e", "#e8c879"),
                    )
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        theme.swatches.forEach { swatch ->
                            Box(
                                Modifier
                                    .size(34.dp)
                                    .clip(CircleShape)
                                    .background(swatch),
                            )
                        }
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        RoleSwatch("wash", theme.backgroundWash)
                        RoleSwatch("glow", theme.glowTint)
                        RoleSwatch("warmth", theme.buttonWarmth)
                    }
                }
            }
        }
    }
}

@Composable
private fun GallerySection(title: String, content: @Composable () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(title, style = LazureType.ankyHeading, color = LazurePigments.ankyInk)
        content()
    }
}

@Composable
private fun PigmentRow(vararg entries: Pair<String, Color>) {
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        entries.forEach { (name, color) ->
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Box(
                    Modifier
                        .size(34.dp)
                        .clip(CircleShape)
                        .background(color),
                )
                Text(
                    name.removePrefix("anky"),
                    style = LazureType.ankyCaption,
                    color = LazurePigments.ankyInkSoft,
                )
            }
        }
    }
}

@Composable
private fun RoleSwatch(name: String, color: Color) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Box(
            Modifier
                .size(34.dp)
                .clip(CircleShape)
                .background(color),
        )
        Text(name, style = LazureType.ankyCaption, color = LazurePigments.ankyInkSoft)
    }
}

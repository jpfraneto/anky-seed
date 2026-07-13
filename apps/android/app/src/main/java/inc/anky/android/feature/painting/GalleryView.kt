package inc.anky.android.feature.painting

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import inc.anky.android.R
import inc.anky.android.core.level.LevelProgressStore
import inc.anky.android.core.level.PaintingAssetStore
import inc.anky.android.core.level.PaintingPackage
import inc.anky.android.ui.lazure.LazureMood
import inc.anky.android.ui.lazure.LazurePigments
import inc.anky.android.ui.lazure.LazureType
import inc.anky.android.ui.lazure.LazureWall
import inc.anky.android.ui.lazure.LevelTheme
import java.util.Locale
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** One finished (or in-progress) Anky in the permanent collection. */
data class GalleryEntry(
    val pkg: PaintingPackage,
    val progress: Double,
)

/**
 * The gallery: every finished Anky, permanent. Completed paintings render
 * at 100%; the current level's shows at its true progress; future paintings
 * stay unseen until their glimpse. Port of iOS `GalleryView`.
 */
@Composable
fun GalleryView(
    currentLevel: Int,
    assetStore: PaintingAssetStore,
    progressStore: LevelProgressStore,
    onClose: () -> Unit,
) {
    val entries by produceState<List<GalleryEntry>>(initialValue = emptyList(), currentLevel) {
        value = withContext(Dispatchers.IO) {
            val percent = progressStore.progress.percent
            assetStore.installedLevels().mapNotNull { level ->
                val pkg = assetStore.installedPackage(level) ?: return@mapNotNull null
                when {
                    level < currentLevel -> GalleryEntry(pkg, 1.0)
                    level == currentLevel -> GalleryEntry(pkg, percent)
                    else -> null // future paintings stay unseen until their glimpse
                }
            }
        }
    }
    var selected by remember { mutableStateOf<GalleryEntry?>(null) }

    Box(Modifier.fillMaxSize()) {
        LazureWall(mood = LazureMood.Dusk)

        LazyVerticalGrid(
            columns = GridCells.Fixed(2),
            horizontalArrangement = Arrangement.spacedBy(18.dp),
            verticalArrangement = Arrangement.spacedBy(22.dp),
            contentPadding = androidx.compose.foundation.layout.PaddingValues(
                start = 24.dp,
                end = 24.dp,
                top = 28.dp,
                bottom = 60.dp,
            ),
            modifier = Modifier.fillMaxSize(),
        ) {
            item(span = { androidx.compose.foundation.lazy.grid.GridItemSpan(2) }) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(
                        text = stringResource(R.string.painting_gallery_title).uppercase(),
                        style = TextStyle(
                            fontFamily = FontFamily.Serif,
                            fontWeight = FontWeight.SemiBold,
                            fontSize = 15.sp,
                            letterSpacing = 4.sp,
                        ),
                        color = LazurePigments.ankyGold,
                    )
                    if (entries.isEmpty()) {
                        Text(
                            text = stringResource(R.string.painting_gallery_empty),
                            style = LazureType.ankyProse.copy(textAlign = TextAlign.Center),
                            color = LazurePigments.ankyInkSoft,
                            modifier = Modifier.padding(horizontal = 16.dp, vertical = 60.dp),
                        )
                    }
                }
            }

            items(entries, key = { it.pkg.level }) { entry ->
                val interactionSource = remember { MutableInteractionSource() }
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                    modifier = Modifier.clickable(
                        interactionSource = interactionSource,
                        indication = null,
                        onClick = { selected = entry },
                    ),
                ) {
                    PaintingView(
                        assets = rememberPaintingRevealAssets(
                            entry.pkg,
                            maxSide = PaintingRevealAssets.GalleryMaxSide,
                        ),
                        progress = entry.progress,
                        glowStrength = 0.5f,
                        modifier = Modifier.fillMaxWidth(),
                    )
                    Text(
                        text = stringResource(
                            R.string.painting_gallery_entry,
                            entry.pkg.title.lowercase(Locale.getDefault()),
                            entry.pkg.level,
                        ),
                        style = LazureType.ankyCaption,
                        color = LazurePigments.ankyInkSoft,
                        maxLines = 1,
                    )
                }
            }
        }

        // Close, floating over the top-right corner.
        Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.TopEnd) {
            val interactionSource = remember { MutableInteractionSource() }
            Box(
                Modifier
                    .padding(top = 14.dp, end = 20.dp)
                    .size(38.dp)
                    .background(LazurePigments.ankyPaper.copy(alpha = 0.55f), CircleShape)
                    .clickable(
                        interactionSource = interactionSource,
                        indication = null,
                        onClick = onClose,
                    ),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    imageVector = Icons.Filled.Close,
                    contentDescription = stringResource(R.string.painting_gallery_close_a11y),
                    tint = LazurePigments.ankyInkSoft,
                    modifier = Modifier.size(18.dp),
                )
            }
        }

        selected?.let { entry ->
            GalleryDetailView(entry = entry, onDismiss = { selected = null })
        }
    }
}

/** One painting, full and quiet. Tap anywhere to return. */
@Composable
private fun GalleryDetailView(
    entry: GalleryEntry,
    onDismiss: () -> Unit,
) {
    val theme = remember(entry.pkg.level) { LevelTheme.fromPalette(entry.pkg.palette) }
    val interactionSource = remember { MutableInteractionSource() }
    Box(
        Modifier
            .fillMaxSize()
            .clickable(
                interactionSource = interactionSource,
                indication = null,
                onClick = onDismiss,
            ),
    ) {
        LazureWall(mood = theme.wallMood)

        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(22.dp),
            modifier = Modifier.fillMaxSize(),
        ) {
            Spacer(Modifier.weight(1f))

            PaintingView(
                assets = rememberPaintingRevealAssets(entry.pkg),
                progress = entry.progress,
                glowTint = theme.glowTint,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = PaintingFrameMath.HorizontalInsetDp.dp),
            )

            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Text(
                    text = "“${entry.pkg.title}”",
                    style = TextStyle(
                        fontFamily = FontFamily.Serif,
                        fontWeight = FontWeight.SemiBold,
                        fontSize = 22.sp,
                    ),
                    color = LazurePigments.ankyInk,
                )
                if (entry.progress >= 1.0 && entry.pkg.thresholdSeconds > 0) {
                    Text(
                        text = stringResource(
                            R.string.painting_gallery_painted_from,
                            String.format(Locale.US, "%,d", entry.pkg.thresholdSeconds),
                        ),
                        style = LazureType.ankyCaption,
                        color = LazurePigments.ankyInkSoft,
                    )
                }
            }

            Spacer(Modifier.weight(1f))
        }
    }
}

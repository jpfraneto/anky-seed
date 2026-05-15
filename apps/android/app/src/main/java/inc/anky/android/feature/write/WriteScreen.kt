package inc.anky.android.feature.write

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle

@Composable
fun WriteScreen(
    viewModel: WriteViewModel,
    onReveal: (String) -> Unit,
) {
    val state = viewModel.state.collectAsStateWithLifecycle().value

    LaunchedEffect(state.completedHash) {
        state.completedHash?.let(onReveal)
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color(0xFFFAF8F2))
            .testTag("write-screen"),
    ) {
        HiddenTextInput(
            onGlyph = viewModel::acceptGlyph,
            onRejectedMutation = viewModel::ignoreBackspaceOrReplacement,
            modifier = Modifier.fillMaxSize().testTag("write-input"),
        )
        Column(
            modifier = Modifier
                .align(Alignment.Center)
                .padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(24.dp),
        ) {
            Text(
                text = state.latestGlyph.ifEmpty { " " },
                fontSize = 72.sp,
                color = Color(0xFF171717),
                modifier = Modifier.testTag("ritual-glyph"),
            )
            LinearProgressIndicator(
                progress = { state.progress },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(3.dp),
                color = Color(0xFF171717),
                trackColor = Color(0xFFE2DED4),
            )
            Text(
                text = if (state.isClosing) "stay" else "",
                style = MaterialTheme.typography.bodySmall,
                color = Color(0xFF6F6A60),
            )
        }
    }
}

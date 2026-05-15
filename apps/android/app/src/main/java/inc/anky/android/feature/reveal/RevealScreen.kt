package inc.anky.android.feature.reveal

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle

@Composable
fun RevealScreen(
    viewModel: RevealViewModel,
    onBack: () -> Unit,
) {
    val state = viewModel.state.collectAsStateWithLifecycle().value
    val context = LocalContext.current
    val artifact = state.artifact

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(20.dp)
            .testTag("reveal-screen"),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedButton(onClick = onBack) { Text("Back") }
            artifact?.let {
                OutlinedButton(onClick = { context.copyText("Anky text", it.reconstructedText) }) {
                    Text("Copy text")
                }
                OutlinedButton(onClick = { context.copyText(".anky", it.text) }) {
                    Text("Copy .anky")
                }
            }
        }
        if (artifact == null) {
            Text("This .anky could not be found.")
            return@Column
        }
        Text(
            text = artifact.reconstructedText,
            style = MaterialTheme.typography.bodyLarge,
            modifier = Modifier.testTag("reconstructed-text"),
        )
        Text("Duration: ${artifact.durationMs} ms")
        Text("Hash: ${artifact.hash}")
        Text(if (artifact.isComplete) "Complete Anky" else "Fragment")
        Text(state.privacyReminder)
        state.reflection?.let {
            Text(it.title, style = MaterialTheme.typography.titleMedium)
            Text(it.reflection)
        }
        if (state.canAskAnky) {
            Button(
                onClick = viewModel::askAnky,
                enabled = !state.isAsking,
                modifier = Modifier.testTag("ask-anky"),
            ) {
                Text(if (state.isAsking) "Asking..." else "Ask Anky")
            }
        }
        state.error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
    }
}

private fun Context.copyText(label: String, text: String) {
    val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
    clipboard.setPrimaryClip(ClipData.newPlainText(label, text))
}

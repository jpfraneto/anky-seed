package inc.anky.android.feature.you

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.runtime.Composable
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.core.content.FileProvider
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import inc.anky.android.BuildConfig
import java.io.File

@Composable
fun YouScreen(viewModel: YouViewModel) {
    val state = viewModel.state.collectAsStateWithLifecycle().value
    val context = LocalContext.current
    val mirrorUrl = remember(state.mirrorBaseUrl) { mutableStateOf(state.mirrorBaseUrl) }

    Column(
        modifier = Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp).testTag("you-screen"),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Text("Public key")
        Text(state.publicKey, modifier = Modifier.testTag("public-key"))
        OutlinedButton(onClick = { context.copyText("Anky public key", state.publicKey) }) {
            Text("Copy public key")
        }
        Button(onClick = viewModel::revealRecoveryPhrase, modifier = Modifier.testTag("reveal-recovery")) {
            Text("Reveal recovery phrase")
        }
        state.recoveryPhrase?.let {
            Text(it, modifier = Modifier.testTag("recovery-phrase"))
            OutlinedButton(onClick = {
                viewModel.copyRecoveryPhrase { phrase ->
                    context.copyText("Anky recovery phrase", phrase)
                }
            }) {
                Text("Copy recovery phrase")
            }
        }
        SettingSwitch("App lock", state.appLockEnabled, viewModel::setAppLock)
        SettingSwitch("Daily reminder", state.dailyReminderEnabled, viewModel::setDailyReminder)
        TextField(
            value = mirrorUrl.value,
            onValueChange = { mirrorUrl.value = it },
            label = { Text("Mirror base URL") },
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri),
            modifier = Modifier.fillMaxWidth(),
        )
        OutlinedButton(onClick = { viewModel.setMirrorBaseUrl(mirrorUrl.value) }) {
            Text("Save mirror URL")
        }
        Text("Credits")
        Text(state.creditState.message)
        OutlinedButton(onClick = viewModel::refreshCredits) { Text("Refresh credits") }
        OutlinedButton(onClick = viewModel::exportArchive) { Text("Export archive") }
        state.exportedFile?.let {
            Text("Export ready: ${it.name}")
            OutlinedButton(onClick = { context.shareFile(it) }) { Text("Share export") }
        }
        Text("Free credits")
        Text(state.freeCreditMessage)
        OutlinedButton(onClick = { context.copyText("Anky free credit message", state.freeCreditMessage) }) {
            Text("Copy message")
        }
        Text(inc.anky.android.core.privacy.PrivacyMessages.DollarAnky)
        Text(inc.anky.android.core.privacy.PrivacyMessages.AnkyCoinContractAddress)
        OutlinedButton(onClick = {
            context.copyText(
                "Anky contract address",
                inc.anky.android.core.privacy.PrivacyMessages.AnkyCoinContractAddress,
            )
        }) {
            Text("Copy contract address")
        }
        Text("Your writing stays local unless you explicitly ask Anky.")
        state.error?.let { Text(it) }
    }
}

@Composable
private fun SettingSwitch(label: String, checked: Boolean, onChecked: (Boolean) -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Text(label)
        Switch(checked = checked, onCheckedChange = onChecked)
    }
}

private fun Context.copyText(label: String, text: String) {
    val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
    clipboard.setPrimaryClip(ClipData.newPlainText(label, text))
}

private fun Context.shareFile(file: File) {
    val uri = FileProvider.getUriForFile(this, "${BuildConfig.APPLICATION_ID}.fileprovider", file)
    val intent = Intent(Intent.ACTION_SEND)
        .setType("application/zip")
        .putExtra(Intent.EXTRA_STREAM, uri)
        .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    startActivity(Intent.createChooser(intent, "Export Anky archive"))
}

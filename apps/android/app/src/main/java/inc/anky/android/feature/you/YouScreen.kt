package inc.anky.android.feature.you

import android.Manifest
import android.app.Activity
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.biometric.BiometricManager
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ChevronLeft
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.FileProvider
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import inc.anky.android.BuildConfig
import inc.anky.android.R
import inc.anky.android.core.credits.CreditCatalog
import inc.anky.android.core.credits.CreditPackage
import inc.anky.android.core.privacy.PrivacyMessages
import inc.anky.android.ui.components.AnkyChatAction
import inc.anky.android.ui.components.AnkyConversationPrompt
import inc.anky.android.ui.theme.AnkyActionButton
import inc.anky.android.ui.theme.AnkyColors
import inc.anky.android.ui.theme.AnkyCosmicBackground
import inc.anky.android.ui.theme.AnkyPanel
import inc.anky.android.ui.theme.AnkyType
import java.io.File

@Composable
fun YouScreen(viewModel: YouViewModel) {
    val state = viewModel.state.collectAsStateWithLifecycle().value
    val context = LocalContext.current
    val page = remember { mutableStateOf<YouPage?>(null) }
    val activePrompt = remember { mutableStateOf(YouPrompt.Identity) }
    val isPromptVisible = remember { mutableStateOf(true) }
    val isShowingSystemPrompt = remember { mutableStateOf(false) }
    val mirrorUrl = remember(state.mirrorBaseUrl) { mutableStateOf(state.mirrorBaseUrl) }
    val showImportPhrase = remember { mutableStateOf(false) }
    val confirmDeleteLocalData = remember { mutableStateOf(false) }
    val confirmClearArchive = remember { mutableStateOf(false) }
    val confirmClearReflections = remember { mutableStateOf(false) }
    val confirmResetIdentity = remember { mutableStateOf(false) }
    val showReminderTime = remember { mutableStateOf(false) }
    val phraseInput = remember { mutableStateOf("") }
    val reminderHourInput = remember(state.dailyReminderMinutes) {
        mutableStateOf((state.dailyReminderMinutes / 60).toString().padStart(2, '0'))
    }
    val reminderMinuteInput = remember(state.dailyReminderMinutes) {
        mutableStateOf((state.dailyReminderMinutes % 60).toString().padStart(2, '0'))
    }
    val backupImporter = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        uri?.let(viewModel::importBackup)
    }
    val notificationPermissionLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) {
            viewModel.setDailyReminder(true)
        } else {
            viewModel.dailyReminderPermissionDenied()
        }
    }
    val setReminderWithPermission: (Boolean) -> Unit = { enabled ->
        if (
            enabled &&
            Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            notificationPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
        } else {
            viewModel.setDailyReminder(enabled)
        }
    }

    LaunchedEffect(Unit) {
        viewModel.refreshLocalStats()
        viewModel.exportArchive()
    }
    LaunchedEffect(state.statusMessage) {
        if (state.statusMessage != null) {
            isShowingSystemPrompt.value = true
            isPromptVisible.value = true
        }
    }
    LaunchedEffect(state.error) {
        if (state.error != null) {
            isShowingSystemPrompt.value = true
            isPromptVisible.value = true
        }
    }

    AnkyCosmicBackground(modifier = Modifier.testTag("you-screen")) {
        if (page.value == null) {
            Box(Modifier.fillMaxSize()) {
                YouHome(
                    state = state,
                    activePrompt = activePrompt.value,
                    onPrompt = {
                        activePrompt.value = it
                        isShowingSystemPrompt.value = false
                        isPromptVisible.value = true
                    },
                )
                if (isPromptVisible.value) {
                    AnkyConversationPrompt(
                        message = youConversationMessage(
                            state = state,
                            activePrompt = activePrompt.value,
                            isShowingSystemPrompt = isShowingSystemPrompt.value,
                        ),
                        actions = if (isShowingSystemPrompt.value) {
                            emptyList()
                        } else {
                            youPromptActions(
                                prompt = activePrompt.value,
                                state = state,
                                context = context,
                                viewModel = viewModel,
                                page = { page.value = it },
                                importBackup = {
                                    backupImporter.launch(
                                        arrayOf(
                                            "application/zip",
                                            "application/x-zip-compressed",
                                            "application/octet-stream",
                                            "application/json",
                                            "text/plain",
                                        ),
                                    )
                                },
                                confirmDeleteLocalData = { confirmDeleteLocalData.value = true },
                            )
                        },
                        onClose = { isPromptVisible.value = false },
                        modifier = Modifier
                            .align(Alignment.BottomCenter)
                            .padding(start = 108.dp, end = 18.dp, bottom = 96.dp),
                    )
                }
            }
        } else {
            YouDetailShell(page.value!!, onBack = { page.value = null }) {
                when (page.value!!) {
                    YouPage.Account -> AccountPage(
                        state = state,
                        onCopyAccountId = { context.copyText("Anky address", state.accountId) },
                        onRevealRecovery = viewModel::revealRecoveryPhrase,
                        onCopyRecovery = { state.recoveryPhrase?.let { context.copyText("Anky recovery key", it) } },
                        onHideRecovery = viewModel::hideRecoveryPhrase,
                        onImportPhrase = {
                            phraseInput.value = ""
                            showImportPhrase.value = true
                        },
                        onAppLock = viewModel::setAppLock,
                        onReminder = setReminderWithPermission,
                        onReminderTime = { showReminderTime.value = true },
                    )
                    YouPage.Privacy -> PrivacyPage()
                    YouPage.Export -> ExportPage(
                        state = state,
                        onExport = viewModel::exportArchive,
                        onShare = { state.exportedFile?.let(context::shareFile) },
                        onRestore = {
                            backupImporter.launch(
                                arrayOf(
                                    "application/zip",
                                    "application/x-zip-compressed",
                                    "application/octet-stream",
                                    "application/json",
                                    "text/plain",
                                ),
                            )
                        },
                        onDeleteLocalData = { confirmDeleteLocalData.value = true },
                    )
                    YouPage.Credits -> CreditsPage(
                        state = state,
                        onRefresh = viewModel::refreshCredits,
                        onRestorePurchases = viewModel::restorePurchases,
                        onPurchase = { packageId -> viewModel.purchaseCredits(packageId, context.findActivity()) },
                        onShareFreeCredit = { context.shareText(state.freeCreditMessage, "share credit request") },
                        onDmJp = { context.openUrl(state.freeCreditWhatsAppUrl) },
                    )
                    YouPage.Token -> TokenPage(
                        onCopy = { context.copyText("Anky contract address", PrivacyMessages.AnkyCoinContractAddress) },
                    )
                    YouPage.Developer -> if (BuildConfig.DEBUG) {
                        DeveloperPage(
                            mirrorUrl = mirrorUrl.value,
                            onMirrorUrl = { mirrorUrl.value = it },
                            onSaveMirrorUrl = { viewModel.setMirrorBaseUrl(mirrorUrl.value) },
                            onRepairMapIndex = viewModel::rebuildSessionIndex,
                            onClearReflections = { confirmClearReflections.value = true },
                            onClearArchive = { confirmClearArchive.value = true },
                            onResetIdentity = { confirmResetIdentity.value = true },
                        )
                    }
                }
            }
        }
    }

    if (showImportPhrase.value) {
        AlertDialog(
            onDismissRequest = { showImportPhrase.value = false },
            title = { Text("recover identity", style = AnkyType.Heading) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    OutlinedTextField(
                        value = phraseInput.value,
                        onValueChange = { phraseInput.value = it },
                        textStyle = AnkyType.Mono,
                        minLines = 4,
                        label = { Text("recovery key") },
                    )
                    Text("recovering replaces the local identity used for ask anky and future credit balances. local .anky files stay on this device.", style = AnkyType.Body.copy(fontSize = 14.sp, color = AnkyColors.PaperMuted))
                }
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        viewModel.importRecoveryPhrase(phraseInput.value) {
                            phraseInput.value = ""
                            showImportPhrase.value = false
                        }
                    },
                    enabled = phraseInput.value.isNotBlank(),
                ) { Text("recover") }
            },
            dismissButton = {
                TextButton(onClick = { showImportPhrase.value = false }) { Text("cancel") }
            },
            containerColor = AnkyColors.PanelStrong,
        )
    }

    if (confirmDeleteLocalData.value) {
        AlertDialog(
            onDismissRequest = { confirmDeleteLocalData.value = false },
            title = { Text("delete local writing data?", style = AnkyType.Heading.copy(color = AnkyColors.Danger)) },
            text = {
                Text(
                    "this removes local .anky files, local reflections, and the local map index from this device. export a backup first if you want to keep them.",
                    style = AnkyType.Body.copy(fontSize = 14.sp, color = AnkyColors.PaperMuted),
                )
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        confirmDeleteLocalData.value = false
                        viewModel.clearLocalWritingData()
                    },
                ) { Text("delete local writing data", color = AnkyColors.Danger) }
            },
            dismissButton = {
                TextButton(onClick = { confirmDeleteLocalData.value = false }) { Text("cancel") }
            },
            containerColor = AnkyColors.PanelStrong,
        )
    }

    if (confirmClearArchive.value) {
        DestructiveConfirmDialog(
            title = "clear local .anky archive?",
            action = "clear .anky archive",
            onDismiss = { confirmClearArchive.value = false },
            onConfirm = {
                confirmClearArchive.value = false
                viewModel.clearLocalArchive()
            },
        )
    }

    if (confirmClearReflections.value) {
        DestructiveConfirmDialog(
            title = "clear local reflections?",
            action = "clear reflections",
            onDismiss = { confirmClearReflections.value = false },
            onConfirm = {
                confirmClearReflections.value = false
                viewModel.clearLocalReflections()
            },
        )
    }

    if (confirmResetIdentity.value) {
        DestructiveConfirmDialog(
            title = "reset local identity?",
            action = "reset identity",
            onDismiss = { confirmResetIdentity.value = false },
            onConfirm = {
                confirmResetIdentity.value = false
                viewModel.resetIdentityForDevelopment()
            },
        )
    }

    if (showReminderTime.value) {
        AlertDialog(
            onDismissRequest = { showReminderTime.value = false },
            title = { Text("time", style = AnkyType.Heading) },
            text = {
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    OutlinedTextField(
                        value = reminderHourInput.value,
                        onValueChange = { reminderHourInput.value = it.filter(Char::isDigit).take(2) },
                        textStyle = AnkyType.Mono,
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                        label = { Text("hour") },
                        modifier = Modifier.weight(1f),
                    )
                    OutlinedTextField(
                        value = reminderMinuteInput.value,
                        onValueChange = { reminderMinuteInput.value = it.filter(Char::isDigit).take(2) },
                        textStyle = AnkyType.Mono,
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                        label = { Text("minute") },
                        modifier = Modifier.weight(1f),
                    )
                }
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        val hour = reminderHourInput.value.toIntOrNull()?.coerceIn(0, 23) ?: 9
                        val minute = reminderMinuteInput.value.toIntOrNull()?.coerceIn(0, 59) ?: 0
                        showReminderTime.value = false
                        viewModel.setDailyReminderTime(hour * 60 + minute)
                    },
                ) { Text("set") }
            },
            dismissButton = {
                TextButton(onClick = { showReminderTime.value = false }) { Text("cancel") }
            },
            containerColor = AnkyColors.PanelStrong,
        )
    }
}

@Composable
private fun DestructiveConfirmDialog(
    title: String,
    action: String,
    onDismiss: () -> Unit,
    onConfirm: () -> Unit,
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title, style = AnkyType.Heading.copy(color = AnkyColors.Danger)) },
        confirmButton = {
            TextButton(onClick = onConfirm) { Text(action, color = AnkyColors.Danger) }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("cancel") }
        },
        containerColor = AnkyColors.PanelStrong,
    )
}

@Composable
private fun YouHome(state: YouState, activePrompt: YouPrompt, onPrompt: (YouPrompt) -> Unit) {
    Column(
        modifier = Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(top = 62.dp, bottom = 220.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(20.dp),
    ) {
        Text("you", style = AnkyType.Title)
        YouStats(state)
        AnkyPanel(contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 16.dp, vertical = 0.dp)) {
            PromptRow(R.drawable.you_icon_account, "identity", "save it to secure storage", activePrompt == YouPrompt.Identity) { onPrompt(YouPrompt.Identity) }
            Divider()
            PromptRow(R.drawable.you_icon_privacy, "privacy", "what leaves this phone", activePrompt == YouPrompt.Privacy) { onPrompt(YouPrompt.Privacy) }
            Divider()
            PromptRow(R.drawable.you_icon_export, "data", "export or restore writing", activePrompt == YouPrompt.Export) { onPrompt(YouPrompt.Export) }
            Divider()
            PromptRow(R.drawable.you_icon_credits, "credits", "reflection balance", activePrompt == YouPrompt.Credits) { onPrompt(YouPrompt.Credits) }
            if (state.freeCreditWhatsAppUrl.isNotBlank()) {
                Divider()
                PromptRow(R.drawable.you_icon_credits, "support", "manual credit help", activePrompt == YouPrompt.Support) { onPrompt(YouPrompt.Support) }
            }
        }
        if (BuildConfig.DEBUG) {
            AnkyPanel(contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 16.dp, vertical = 0.dp)) {
                PromptRow(R.drawable.you_icon_settings, "developer", "local repair tools", activePrompt == YouPrompt.Developer) { onPrompt(YouPrompt.Developer) }
            }
        }
    }
}

@Composable
private fun YouStatusMessages(state: YouState) {
    state.error?.let { message ->
        AnkyPanel {
            Text(
                message.lowercase(),
                style = AnkyType.Body.copy(fontSize = 14.sp, color = AnkyColors.Danger),
                modifier = Modifier.fillMaxWidth(),
            )
        }
    }
    state.statusMessage?.let { message ->
        AnkyPanel {
            Text(
                message.lowercase(),
                style = AnkyType.Body.copy(fontSize = 14.sp, color = AnkyColors.PaperMuted),
                modifier = Modifier.fillMaxWidth(),
            )
        }
    }
}

@Composable
private fun YouAvatar() {
    Box(Modifier.size(144.dp), contentAlignment = Alignment.Center) {
        Box(
            Modifier
                .size(124.dp)
                .shadow(
                    elevation = 16.dp,
                    shape = CircleShape,
                    clip = false,
                    ambientColor = AnkyColors.Gold.copy(alpha = 0.24f),
                    spotColor = AnkyColors.Gold.copy(alpha = 0.24f),
                )
                .clip(CircleShape)
                .border(1.5.dp, AnkyColors.Gold.copy(alpha = 0.72f), CircleShape),
        )
        Box(Modifier.size(116.dp).clip(CircleShape).border(1.dp, AnkyColors.Gold.copy(alpha = 0.42f), CircleShape))
        Image(
            painter = painterResource(R.drawable.you_avatar_anky),
            contentDescription = null,
            contentScale = ContentScale.Crop,
            modifier = Modifier.size(108.dp).clip(CircleShape),
        )
        listOf(
            Alignment.TopCenter,
            Alignment.CenterEnd,
            Alignment.BottomCenter,
            Alignment.CenterStart,
        ).forEach { alignment ->
            Box(
                Modifier
                    .size(7.dp)
                    .align(alignment)
                    .rotate(45f)
                    .background(AnkyColors.Gold),
            )
        }
    }
}

@Composable
private fun YouStats(state: YouState) {
    AnkyPanel(contentPadding = androidx.compose.foundation.layout.PaddingValues(0.dp)) {
        Row(Modifier.fillMaxWidth().height(68.dp), verticalAlignment = Alignment.CenterVertically) {
            StatCell(R.drawable.you_icon_feather_stat, state.completeAnkyCount.toString(), "ankys")
            VerticalDivider()
            StatCell(R.drawable.you_icon_clock_stat, state.totalWritingMinutes.toString(), "minutes")
            VerticalDivider()
            StatCell(R.drawable.you_icon_flame_stat, state.currentStreak.toString(), "streak")
        }
    }
}

@Composable
private fun RowScope.StatCell(icon: Int, value: String, label: String) {
    Row(Modifier.weight(1f), horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
        Image(painterResource(icon), null, modifier = Modifier.size(28.dp))
        Column(Modifier.padding(start = 8.dp)) {
            Text(value, style = AnkyType.Body.copy(fontSize = 17.sp))
            Text(label, style = AnkyType.Caption.copy(fontSize = 10.sp, color = AnkyColors.PaperMuted))
        }
    }
}

@Composable
private fun MenuRow(icon: Int, title: String, subtitle: String, onClick: () -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick).padding(vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Image(painterResource(icon), null, modifier = Modifier.size(24.dp))
        Column(Modifier.weight(1f).padding(start = 13.dp)) {
            Text(title, style = AnkyType.Body.copy(fontSize = 17.sp, fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold), maxLines = 1)
            Text(subtitle, style = AnkyType.Caption.copy(fontSize = 12.sp, color = AnkyColors.PaperMuted), maxLines = 2, overflow = TextOverflow.Ellipsis)
        }
        Image(painterResource(R.drawable.you_icon_chevron_right), null, modifier = Modifier.size(14.dp).alpha(0.82f))
    }
}

@Composable
private fun PromptRow(icon: Int, title: String, subtitle: String, selected: Boolean, onClick: () -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick).padding(vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Image(painterResource(icon), null, modifier = Modifier.size(24.dp).alpha(if (selected) 1f else 0.86f))
        Column(Modifier.weight(1f).padding(start = 13.dp)) {
            Text(
                title,
                style = AnkyType.Body.copy(
                    fontSize = 17.sp,
                    fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold,
                    color = if (selected) AnkyColors.Gold else AnkyColors.Paper,
                ),
                maxLines = 1,
            )
            Text(subtitle, style = AnkyType.Caption.copy(fontSize = 12.sp, color = AnkyColors.PaperMuted), maxLines = 2, overflow = TextOverflow.Ellipsis)
        }
    }
}

@Composable
private fun YouDetailShell(page: YouPage, onBack: () -> Unit, content: @Composable () -> Unit) {
    Column(Modifier.fillMaxSize()) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 18.dp).padding(top = 60.dp, bottom = 14.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(
                modifier = Modifier
                    .size(44.dp)
                    .clip(CircleShape)
                    .background(AnkyColors.Panel)
                    .border(1.dp, AnkyColors.GoldDim, CircleShape)
                    .clickable(onClick = onBack),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    imageVector = Icons.Filled.ChevronLeft,
                    contentDescription = "Back",
                    tint = AnkyColors.Gold,
                    modifier = Modifier.size(24.dp),
                )
            }
            Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally) {
                Text(page.title, style = AnkyType.Heading.copy(fontSize = 26.sp))
                Text(page.subtitle, style = AnkyType.Caption.copy(color = AnkyColors.PaperMuted))
            }
            Spacer(Modifier.size(44.dp))
        }
        Column(
            modifier = Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(bottom = 120.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) { content() }
    }
}

@Composable
private fun AccountPage(
    state: YouState,
    onCopyAccountId: () -> Unit,
    onRevealRecovery: () -> Unit,
    onCopyRecovery: () -> Unit,
    onHideRecovery: () -> Unit,
    onImportPhrase: () -> Unit,
    onAppLock: (Boolean) -> Unit,
    onReminder: (Boolean) -> Unit,
    onReminderTime: () -> Unit,
) {
    val context = LocalContext.current
    val lockLabel = remember(context) { biometricLockLabel(context) }
    AnkyPanel {
        Text("local identity", style = AnkyType.Caption)
        Text(
            "anky created a private identity for this device.",
            style = AnkyType.Body.copy(
                fontSize = 17.sp,
                fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold,
                color = AnkyColors.Paper,
            ),
        )
        Text("your writing and identity live here unless you choose to export or recover them elsewhere.", style = AnkyType.Body.copy(fontSize = 14.sp, color = AnkyColors.PaperMuted))
    }
    AnkyPanel {
        Text("advanced recovery", style = AnkyType.Caption)
        Text("anyone with this recovery key can restore this identity. keep it private.", style = AnkyType.Body.copy(fontSize = 14.sp, color = AnkyColors.PaperMuted))
        Divider()
        SwitchRow("$lockLabel app lock", state.appLockEnabled, onAppLock)
        Text("your recovery key can only be shown after $lockLabel lock is enabled.", style = AnkyType.Body.copy(fontSize = 14.sp, color = AnkyColors.PaperMuted))
        if (state.recoveryPhrase == null) {
            AnkyActionButton("show recovery key", enabled = state.appLockEnabled, onClick = onRevealRecovery)
        } else {
            Text(state.recoveryPhrase, style = AnkyType.Mono.copy(color = AnkyColors.Paper))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                AnkyActionButton("export recovery key", modifier = Modifier.weight(1f), onClick = onCopyRecovery)
                AnkyActionButton("hide", modifier = Modifier.weight(1f), onClick = onHideRecovery)
            }
        }
        AnkyActionButton("recover identity", onClick = onImportPhrase)
        Text("Anky address", style = AnkyType.Caption)
        Text(state.accountId, style = AnkyType.Mono.copy(color = AnkyColors.PaperMuted))
        AnkyActionButton("copy account", onClick = onCopyAccountId)
    }
    AnkyPanel {
        SwitchRow("daily reminder", state.dailyReminderEnabled, onReminder)
        DetailRow("time", YouViewModel.formatReminderTime(state.dailyReminderMinutes))
        AnkyActionButton("change time", enabled = state.dailyReminderEnabled, onClick = onReminderTime)
    }
    AnkyPanel {
        Text("ownership note", style = AnkyType.Caption)
        Text("your writing belongs to this device unless you choose to export or recover it elsewhere.", style = AnkyType.Body.copy(fontSize = 14.sp, color = AnkyColors.PaperMuted))
    }
}

@Composable
private fun PrivacyPage() {
    Text("privacy is the shape of anky, not a feature added later.", style = AnkyType.Heading.copy(fontSize = 19.sp, color = AnkyColors.Paper), textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())
    PrivacyCopy.forEach { ArticleLine(it) }
    AnkyPanel {
        Text("questions, deletion requests, and privacy reports", style = AnkyType.Caption)
        Text("jp@anky.app", style = AnkyType.Mono.copy(color = AnkyColors.Paper))
    }
}

@Composable
private fun ExportPage(
    state: YouState,
    onExport: () -> Unit,
    onShare: () -> Unit,
    onRestore: () -> Unit,
    onDeleteLocalData: () -> Unit,
) {
    LaunchedEffect(Unit) {
        onExport()
    }

    AnkyPanel {
        Text("${state.localAnkyFileCount} local .anky files · ${state.reflectionCount} reflections", style = AnkyType.Heading)
        Text("backups may include plaintext writing and reflections. keep them somewhere private.", style = AnkyType.Body.copy(fontSize = 14.sp, color = AnkyColors.PaperMuted))
    }
    AnkyPanel {
        when (exportBackupAction(state)) {
            ExportBackupAction.Share -> AnkyActionButton("export backup zip", onClick = onShare)
            ExportBackupAction.Empty -> DisabledRow("no local data to export yet")
        }
        AnkyActionButton("restore backup", onClick = onRestore)
    }
    YouDangerPanel {
        Text("danger zone", style = AnkyType.Heading.copy(fontSize = 18.sp, color = AnkyColors.Danger))
        Text("this removes local .anky files, local reflections, and the local map index from this device. export a backup first if you want to keep them.", style = AnkyType.Body.copy(fontSize = 14.sp, color = AnkyColors.PaperMuted))
        AnkyActionButton("delete local data", destructive = true, onClick = onDeleteLocalData)
    }
}

@Composable
private fun YouDangerPanel(content: @Composable () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(18.dp))
            .background(Color(0xB32E090E))
            .border(1.dp, AnkyColors.Danger.copy(alpha = 0.45f), RoundedCornerShape(18.dp))
            .padding(horizontal = 16.dp, vertical = 14.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
        content = { content() },
    )
}

@Composable
private fun CreditsPage(
    state: YouState,
    onRefresh: () -> Unit,
    onRestorePurchases: () -> Unit,
    onPurchase: (String) -> Unit,
    onShareFreeCredit: () -> Unit,
    onDmJp: () -> Unit,
) {
    AnkyPanel {
        Text(
            state.creditState.balance?.toString() ?: "...",
            style = AnkyType.Title.copy(
                fontSize = 62.sp,
                shadow = Shadow(color = AnkyColors.Gold.copy(alpha = 0.35f), blurRadius = 18f),
            ),
            modifier = Modifier.fillMaxWidth(),
            textAlign = TextAlign.Center,
        )
        Text("credits", style = AnkyType.Caption, modifier = Modifier.fillMaxWidth(), textAlign = TextAlign.Center)
    }
    AnkyPanel {
        Rule("1 credit = reflection")
        Rule("ask anky spends one credit")
        Rule("writing is always free")
    }
    AnkyPanel {
        when {
            state.creditState.isLoading && state.creditState.packages.isEmpty() -> DisabledRow("loading credit packs")
            state.creditState.packages.isEmpty() -> DisabledRow("no credit packs available")
            else -> {
                state.creditState.packages.forEach { creditPackage ->
                    CreditPackageButton(
                        creditPackage = creditPackage,
                        isPurchasing = state.purchasingCreditPackageId == creditPackage.packageId,
                        onPurchase = onPurchase,
                    )
                }
            }
        }
        AnkyActionButton("refresh credits", onClick = onRefresh)
        AnkyActionButton(
            if (state.isRestoringPurchases) "restoring purchases" else "restore purchases",
            enabled = !state.isRestoringPurchases,
            onClick = onRestorePurchases,
        )
        Text(CreditCatalog.RestoreIdentityNote, style = AnkyType.Body.copy(fontSize = 14.sp, color = AnkyColors.PaperMuted))
    }
    AnkyPanel {
        AnkyActionButton("share support request", onClick = onShareFreeCredit)
        AnkyActionButton("contact jp / support", onClick = onDmJp)
        Text("support credit requests use your account id only. no writing is included.", style = AnkyType.Body.copy(fontSize = 14.sp, color = AnkyColors.PaperMuted))
    }
}

@Composable
private fun CreditPackageButton(creditPackage: CreditPackage, isPurchasing: Boolean, onPurchase: (String) -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .background(AnkyColors.ButtonFill)
            .border(1.dp, AnkyColors.Gold.copy(alpha = 0.32f), RoundedCornerShape(14.dp))
            .clickable(enabled = !isPurchasing) { onPurchase(creditPackage.packageId) }
            .padding(horizontal = 14.dp, vertical = 12.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(
                creditPackage.title,
                style = AnkyType.Body.copy(fontSize = 17.sp, fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold),
            )
            if (creditPackage.subtitle.isNotBlank() && creditPackage.subtitle != creditPackage.title) {
                Text(creditPackage.subtitle, style = AnkyType.Caption)
            }
        }
        Text(if (isPurchasing) "..." else creditPackage.price, style = AnkyType.Caption.copy(fontSize = 15.sp, color = AnkyColors.Gold))
    }
}

@Composable
private fun DisabledRow(text: String) {
    Text(
        text,
        style = AnkyType.Body.copy(fontSize = 14.sp, color = AnkyColors.PaperMuted),
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .background(AnkyColors.PanelStrong.copy(alpha = 0.72f))
            .padding(horizontal = 14.dp, vertical = 12.dp),
    )
}

private fun biometricLockLabel(context: Context): String {
    val packageManager = context.packageManager
    val hasFingerprint = packageManager.hasSystemFeature(PackageManager.FEATURE_FINGERPRINT)
    val hasFace = Build.VERSION.SDK_INT >= 29 && packageManager.hasSystemFeature(PackageManager.FEATURE_FACE)
    val hasIris = Build.VERSION.SDK_INT >= 29 && packageManager.hasSystemFeature(PackageManager.FEATURE_IRIS)
    val canUseBiometric = BiometricManager.from(context).canAuthenticate(BiometricManager.Authenticators.BIOMETRIC_WEAK) ==
        BiometricManager.BIOMETRIC_SUCCESS

    return when {
        hasFingerprint && !hasFace -> "fingerprint"
        hasFace && !hasFingerprint -> "face"
        hasIris && !hasFingerprint && !hasFace -> "iris"
        canUseBiometric -> "biometric"
        else -> "device"
    }
}

@Composable
private fun TokenPage(onCopy: () -> Unit) {
    val copied = remember { mutableStateOf(false) }
    Box(Modifier.fillMaxWidth().padding(top = 10.dp, bottom = 8.dp), contentAlignment = Alignment.Center) {
        Image(
            painterResource(R.drawable.you_ankycoin),
            null,
            modifier = Modifier
                .size(136.dp)
                .shadow(
                    elevation = 18.dp,
                    shape = CircleShape,
                    clip = false,
                    ambientColor = AnkyColors.Gold.copy(alpha = 0.24f),
                    spotColor = AnkyColors.Gold.copy(alpha = 0.24f),
                )
                .clip(CircleShape)
                .border(1.dp, AnkyColors.Gold.copy(alpha = 0.5f), CircleShape),
        )
    }
    TokenCopy.forEach { ArticleLine(it) }
    AnkyPanel {
        Text(PrivacyMessages.AnkyCoinContractAddress, style = AnkyType.Mono)
        AnkyActionButton(if (copied.value) "copied!" else "copy contract address") {
            onCopy()
            copied.value = true
        }
    }
}

@Composable
private fun DeveloperPage(
    mirrorUrl: String,
    onMirrorUrl: (String) -> Unit,
    onSaveMirrorUrl: () -> Unit,
    onRepairMapIndex: () -> Unit,
    onClearReflections: () -> Unit,
    onClearArchive: () -> Unit,
    onResetIdentity: () -> Unit,
) {
    AnkyPanel {
        OutlinedTextField(
            value = mirrorUrl,
            onValueChange = onMirrorUrl,
            textStyle = AnkyType.Mono,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri),
            label = { Text("mirror base url") },
            modifier = Modifier.fillMaxWidth(),
        )
        Text("emulator local mirror: http://10.0.2.2:3000. physical devices should use the deployed https mirror or an https tunnel to local.", style = AnkyType.Body.copy(fontSize = 14.sp, color = AnkyColors.PaperMuted))
        AnkyActionButton("save mirror url", onClick = onSaveMirrorUrl)
        AnkyActionButton("repair map index", onClick = onRepairMapIndex)
    }
    AnkyPanel {
        AnkyActionButton("clear local reflections", destructive = true, onClick = onClearReflections)
        AnkyActionButton("clear local .anky archive", destructive = true, onClick = onClearArchive)
        AnkyActionButton("reset local identity", destructive = true, onClick = onResetIdentity)
    }
}

@Composable
private fun SwitchRow(label: String, checked: Boolean, onChecked: (Boolean) -> Unit) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
        Text(label, style = AnkyType.Body.copy(fontSize = 16.sp))
        Switch(checked = checked, onCheckedChange = onChecked)
    }
}

@Composable private fun DetailRow(title: String, value: String) = Row(Modifier.fillMaxWidth()) { Text(title, style = AnkyType.Caption); Spacer(Modifier.weight(1f)); Text(value, style = AnkyType.Body.copy(fontSize = 14.sp)) }
@Composable private fun Rule(text: String) = Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) { Box(Modifier.size(5.dp).clip(CircleShape).background(AnkyColors.Gold.copy(alpha = 0.72f))); Text(text, style = AnkyType.Body.copy(fontSize = 14.sp, color = AnkyColors.PaperMuted)) }
@Composable private fun Divider() = Box(Modifier.fillMaxWidth().height(1.dp).background(AnkyColors.Gold.copy(alpha = 0.13f)))
@Composable private fun VerticalDivider() = Box(Modifier.height(52.dp).size(width = 1.dp, height = 52.dp).background(AnkyColors.Gold.copy(alpha = 0.12f)))

@Composable
private fun ArticleLine(item: ArticleItem) {
    when (item) {
        is ArticleItem.Caption -> Text(item.text, style = AnkyType.Caption)
        is ArticleItem.Heading -> Text(item.text, style = AnkyType.Heading.copy(fontSize = 21.sp), modifier = Modifier.padding(top = 4.dp))
        is ArticleItem.Paragraph -> MarkdownArticleText(item.text)
    }
}

@Composable
private fun MarkdownArticleText(text: String) {
    Text(markdownLinks(text), style = AnkyType.Body.copy(fontSize = 16.sp))
}

private fun markdownLinks(text: String): AnnotatedString = buildAnnotatedString {
    var index = 0
    while (index < text.length) {
        val linkStart = text.indexOf('[', startIndex = index)
        if (linkStart < 0) {
            append(text.substring(index))
            break
        }
        val labelEnd = text.indexOf("](", startIndex = linkStart)
        if (labelEnd < 0) {
            append(text.substring(index))
            break
        }
        val urlEnd = text.indexOf(')', startIndex = labelEnd + 2)
        if (urlEnd < 0) {
            append(text.substring(index))
            break
        }

        append(text.substring(index, linkStart))
        val label = text.substring(linkStart + 1, labelEnd)
        val url = text.substring(labelEnd + 2, urlEnd)
        pushLink(
            LinkAnnotation.Url(
                url = url,
                styles = TextLinkStyles(
                    style = SpanStyle(color = AnkyColors.Gold, textDecoration = TextDecoration.Underline),
                    pressedStyle = SpanStyle(color = AnkyColors.GoldSoft, textDecoration = TextDecoration.Underline),
                ),
            ),
        )
        withStyle(SpanStyle(color = AnkyColors.Gold, textDecoration = TextDecoration.Underline)) {
            append(label)
        }
        pop()
        index = urlEnd + 1
    }
}

private sealed interface ArticleItem {
    data class Caption(val text: String) : ArticleItem
    data class Heading(val text: String) : ArticleItem
    data class Paragraph(val text: String) : ArticleItem
}

private val PrivacyCopy = listOf(
    ArticleItem.Caption("last updated: 2026-05-14"),
    ArticleItem.Paragraph("anky is a local-first writing app. the core artifact is the `.anky` file on your device. the app should let you write, save, revisit, export, import, and delete your writing without making a server the owner of your interior life."),
    ArticleItem.Heading("the private artifact"),
    ArticleItem.Paragraph("your `.anky` writing is stored on your device by default. a saved `.anky` file contains the accepted writing stream and timing data for a session."),
    ArticleItem.Paragraph("anky computes a SHA-256 hash of the exact `.anky` bytes. the hash is for integrity. it is not encryption. if someone has the same `.anky` bytes, they can compute the same hash."),
    ArticleItem.Paragraph("the source is direct: [local archive](https://github.com/jpfraneto/anky-seed/blob/main/apps/ios/Anky/Core/Storage/LocalAnkyArchive.swift), [protocol](https://github.com/jpfraneto/anky-seed/tree/main/apps/ios/Anky/Core/Protocol)."),
    ArticleItem.Heading("local identity"),
    ArticleItem.Paragraph("anky creates a local identity, stores its recovery key in device secure storage, and derives the writing identity locally. the recovery key is not sent to anky."),
    ArticleItem.Paragraph("the relevant code is [writer identity](https://github.com/jpfraneto/anky-seed/blob/main/apps/ios/Anky/Core/Identity/WriterIdentityStore.swift) and [keychain storage](https://github.com/jpfraneto/anky-seed/blob/main/apps/ios/Anky/Core/Identity/KeychainClient.swift)."),
    ArticleItem.Heading("when plaintext leaves"),
    ArticleItem.Paragraph("writing, saving, hashing, reading the map, and keeping local backups do not require plaintext to leave your device."),
    ArticleItem.Paragraph("plaintext can leave when you choose an action that sends it somewhere: asking anky for a reflection, exporting or sharing files, importing a backup from a place you chose, or contacting support with text you provide."),
    ArticleItem.Paragraph("the processing and backup paths are [reflection client](https://github.com/jpfraneto/anky-seed/blob/main/apps/ios/Anky/Core/Mirror/MirrorClient.swift), [backup importer](https://github.com/jpfraneto/anky-seed/blob/main/apps/ios/Anky/Core/Storage/BackupImporter.swift), and [you page model](https://github.com/jpfraneto/anky-seed/blob/main/apps/ios/Anky/Features/You/YouViewModel.swift)."),
    ArticleItem.Heading("reflections"),
    ArticleItem.Paragraph("when you ask for a reflection, the app sends the saved `.anky` bytes to the configured mirror service. the mirror checks the hash, reconstructs readable text for processing, and returns a reflection."),
    ArticleItem.Paragraph("the local app stores the returned reflection as a local sidecar. reflections are optional. writing is free and does not depend on reflections."),
    ArticleItem.Heading("backups and deletion"),
    ArticleItem.Paragraph("exports and backups can contain plaintext writing, reflections, and related local metadata. keep them somewhere private."),
    ArticleItem.Paragraph("deleting local writing data removes local `.anky` files, local reflections, and the local session index from this app's storage area. it does not automatically delete backend records already created by optional processing."),
    ArticleItem.Heading("what this does not claim"),
    ArticleItem.Paragraph("anky does not claim that hashes encrypt writing. anky does not claim anonymity. timing, identity identifiers, processing requests, purchases, and support requests can be linkable."),
    ArticleItem.Paragraph("anky does not claim optional processing is local-only. if you ask for a reflection, plaintext writing is sent for processing."),
    ArticleItem.Paragraph("anky does claim the default direction of the app is local-first: the `.anky` file belongs first to the person who wrote it."),
)

private val TokenCopy = listOf(
    ArticleItem.Paragraph("a memecoin is the simplest possible expression of an idea on the internet. no pitch deck, no roadmap, no Series A. just a name, a ticker, and a bet that enough people will recognize what it points to."),
    ArticleItem.Paragraph("\$ANKY exists as a memecoin. that's it. no presale, no team allocation, no vesting schedule. the bonding curve did what bonding curves do."),
    ArticleItem.Heading("what it points to"),
    ArticleItem.Paragraph("anky is a writing practice. you sit down, you write for 8 minutes without stopping, and something emerges that your conscious mind didn't plan. the token doesn't change what the practice is. it doesn't unlock features or grant access. it's a flag planted in the ground that says: this idea exists, and the market gets to decide what it's worth."),
    ArticleItem.Heading("memecoins and the new internet"),
    ArticleItem.Paragraph("the old internet released ideas through products. you built something, charged for it, and hoped people would pay. the new internet releases ideas through tokens. the idea itself becomes tradeable the moment it has a name."),
    ArticleItem.Paragraph("this is either profoundly stupid or profoundly honest. probably both. a memecoin strips away every pretension about what makes something valuable and reduces it to the only question that ever mattered: do people care about this?"),
    ArticleItem.Paragraph("most memecoins are jokes. some jokes contain more truth than business plans. the cosmic joke of \$ANKY is that a tool designed to bypass your conscious mind — to help you stop thinking and just write — now has a price feed that people watch with their conscious minds, thinking very hard about whether the number will go up."),
    ArticleItem.Paragraph("the mirror doesn't care about the price. the practice remains free. write for 8 minutes. meet yourself. whether the token is worth a penny or a dollar, the words you wrote are still yours."),
)

internal fun identityStatus(state: YouState): String = "Local identity"

internal fun exportBackupAction(state: YouState): ExportBackupAction =
    if (state.exportedFile != null) ExportBackupAction.Share else ExportBackupAction.Empty

internal enum class ExportBackupAction {
    Share,
    Empty,
}

private enum class YouPage(val title: String, val subtitle: String) {
    Account("local identity", "private to this device"),
    Privacy("privacy", "local-first. private. sovereign."),
    Export("export data", "your archive is yours"),
    Credits("credits", "reflection fuel"),
    Token("\$ANKY", "the memetic layer"),
    Developer("developer", "local tools"),
}

private enum class YouPrompt(val message: String) {
    Identity("your identity can be saved to secure storage."),
    Privacy("writing stays local unless you export or ask for a reflection."),
    Export("your archive is yours. export it or restore one."),
    Credits("credits are only for reflections. writing is free."),
    Support("support messages include your account id, not your writing."),
    Developer("local tools. repair first, delete only when you mean it."),
}

private fun youConversationMessage(
    state: YouState,
    activePrompt: YouPrompt,
    isShowingSystemPrompt: Boolean,
): String =
    if (isShowingSystemPrompt) {
        state.error ?: state.statusMessage ?: activePrompt.message
    } else {
        activePrompt.message
    }

private fun youPromptActions(
    prompt: YouPrompt,
    state: YouState,
    context: Context,
    viewModel: YouViewModel,
    page: (YouPage) -> Unit,
    importBackup: () -> Unit,
    confirmDeleteLocalData: () -> Unit,
): List<AnkyChatAction> =
    when (prompt) {
        YouPrompt.Identity -> listOf(
            AnkyChatAction("back up identity", isPrimary = true) { viewModel.revealRecoveryPhrase() },
            AnkyChatAction("copy account") { context.copyText("Anky address", state.accountId) },
        )
        YouPrompt.Privacy -> listOf(
            AnkyChatAction("copy privacy email", isPrimary = true) { context.copyText("ANKY privacy", "jp@anky.app") },
        )
        YouPrompt.Export -> buildList {
            state.exportedFile?.let { file ->
                add(AnkyChatAction("export backup", isPrimary = true) { context.shareFile(file) })
            }
            add(AnkyChatAction("restore backup") { importBackup() })
        }
        YouPrompt.Credits -> {
            val firstPackage = state.creditState.packages.firstOrNull()
            buildList {
                if (firstPackage != null) {
                    add(AnkyChatAction("buy reflections", isPrimary = true) {
                        viewModel.purchaseCredits(firstPackage.packageId, context.findActivity())
                    })
                }
                add(AnkyChatAction("refresh credits") { viewModel.refreshCredits() })
            }
        }
        YouPrompt.Support -> listOf(
            AnkyChatAction("share request", isPrimary = true) { context.shareText(state.freeCreditMessage, "share credit request") },
            AnkyChatAction("message support") { context.openUrl(state.freeCreditWhatsAppUrl) },
        )
        YouPrompt.Developer -> if (BuildConfig.DEBUG) {
            listOf(
                AnkyChatAction("repair map", isPrimary = true) { viewModel.rebuildSessionIndex() },
                AnkyChatAction("delete local data") { confirmDeleteLocalData() },
            )
        } else {
            emptyList()
        }
    }

private fun Context.copyText(label: String, text: String) {
    val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
    clipboard.setPrimaryClip(ClipData.newPlainText(label, text))
}

private fun Context.openUrl(url: String) {
    startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
}

private fun Context.shareText(text: String, title: String) {
    val intent = Intent(Intent.ACTION_SEND)
        .setType("text/plain")
        .putExtra(Intent.EXTRA_TEXT, text)
    startActivity(Intent.createChooser(intent, title))
}

private fun Context.shareFile(file: File) {
    val uri = FileProvider.getUriForFile(this, "${BuildConfig.APPLICATION_ID}.fileprovider", file)
    val intent = Intent(Intent.ACTION_SEND)
        .setType("application/zip")
        .putExtra(Intent.EXTRA_STREAM, uri)
        .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    startActivity(Intent.createChooser(intent, "export backup zip"))
}

private tailrec fun Context.findActivity(): Activity? =
    when (this) {
        is Activity -> this
        is ContextWrapper -> baseContext.findActivity()
        else -> null
    }

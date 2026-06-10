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
import androidx.annotation.StringRes
import androidx.biometric.BiometricManager
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.ChevronLeft
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.PriorityHigh
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.FileProvider
import androidx.core.content.ContextCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import inc.anky.android.BuildConfig
import inc.anky.android.R
import inc.anky.android.core.credits.CreditCatalog
import inc.anky.android.core.credits.CreditPackage
import inc.anky.android.core.privacy.PrivacyMessages
import inc.anky.android.core.protocol.AnkyDuration
import inc.anky.android.core.protocol.AnkyParser
import inc.anky.android.core.protocol.AnkyReconstructor
import inc.anky.android.core.protocol.AnkyWriter
import inc.anky.android.core.storage.SessionSummary
import inc.anky.android.feature.write.HiddenTextInput
import inc.anky.android.ui.components.AnkyChatAction
import inc.anky.android.ui.components.AnkyConversationPrompt
import inc.anky.android.ui.theme.AnkyActionButton
import inc.anky.android.ui.theme.AnkyColors
import inc.anky.android.ui.theme.AnkyCosmicBackground
import inc.anky.android.ui.theme.AnkyPanel
import inc.anky.android.ui.theme.AnkyType
import java.io.File
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale
import kotlinx.coroutines.delay

private const val AnkyExperienceTotalSeconds = 88 * 60

enum class YouInitialPage {
    Credits,
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun YouScreen(
    viewModel: YouViewModel,
    initialPage: YouInitialPage? = null,
    onInitialPageBack: (() -> Unit)? = null,
    onOpenReveal: (String) -> Unit = {},
    onWriteRequested: () -> Unit = {},
    onAccountDeleted: () -> Unit = {},
    onAppLockChange: (Boolean) -> Unit = viewModel::setAppLock,
    onExperienceVisibilityChanged: (Boolean) -> Unit = {},
) {
    val state = viewModel.state.collectAsStateWithLifecycle().value
    val context = LocalContext.current
    val ankyAddressClipboardLabel = stringResource(R.string.anky_address)
    val recoveryWordsClipboardLabel = stringResource(R.string.you_recovery_words_label)
    val exportWritingsChooserTitle = stringResource(R.string.export_writings)
    val exportBackupZipChooserTitle = stringResource(R.string.export_backup_zip)
    val showRecoveryWordsReason = stringResource(R.string.show_anky_recovery_words_reason)
    val backupRecoveryWordsSecureStorageReason = stringResource(R.string.backup_anky_recovery_words_secure_storage_reason)
    val recoverAnkyAccessReason = stringResource(R.string.recover_anky_access_reason)
    val enableEncryptedBackupReason = stringResource(R.string.enable_encrypted_anky_backup_reason)
    val restoreEncryptedBackupReason = stringResource(R.string.restore_encrypted_anky_backup_reason)
    val couldNotConfirmIdentity = stringResource(R.string.could_not_confirm_identity)
    val page = remember(initialPage) { mutableStateOf(initialPage?.toYouPage()) }
    val activePrompt = remember { mutableStateOf<YouPrompt?>(null) }
    val isPromptVisible = remember { mutableStateOf(false) }
    val isShowingSystemPrompt = remember { mutableStateOf(false) }
    val mirrorUrl = remember(state.mirrorBaseUrl) { mutableStateOf(state.mirrorBaseUrl) }
    val showImportPhrase = remember { mutableStateOf(false) }
    val confirmDeleteLocalData = remember { mutableStateOf(false) }
    val confirmDeleteAccountAndData = remember { mutableStateOf(false) }
    val confirmClearArchive = remember { mutableStateOf(false) }
    val confirmClearReflections = remember { mutableStateOf(false) }
    val confirmResetIdentity = remember { mutableStateOf(false) }
    val showReminderTime = remember { mutableStateOf(false) }
    val isShowingAnkyExperience = remember { mutableStateOf(false) }
    val didCopyAnkyContract = remember { mutableStateOf(false) }
    val showsAccountDeletion = remember { mutableStateOf(false) }
    val showsReflectionCreditsSheet = remember { mutableStateOf(false) }
    val reflectionCreditsSheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
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
        viewModel.refresh()
        viewModel.exportArchive()
        viewModel.prepareFormattedWritingExport()
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
    LaunchedEffect(isShowingAnkyExperience.value) {
        onExperienceVisibilityChanged(isShowingAnkyExperience.value)
    }
    LaunchedEffect(didCopyAnkyContract.value) {
        if (didCopyAnkyContract.value) {
            delay(1_600)
            didCopyAnkyContract.value = false
        }
    }
    DisposableEffect(Unit) {
        onDispose { onExperienceVisibilityChanged(false) }
    }

    AnkyCosmicBackground(modifier = Modifier.testTag("you-screen")) {
        Box(Modifier.fillMaxSize()) {
            if (page.value == null) {
                YouHome(
                    state = state,
                    activePrompt = activePrompt.value,
                    onOpenPage = { page.value = it },
                    onCopyAnkyContract = {
                        context.copyText("Anky contract address", PrivacyMessages.AnkyCoinContractAddress)
                        didCopyAnkyContract.value = true
                    },
                    onOpenCreditsSheet = {
                        activePrompt.value = null
                        isShowingSystemPrompt.value = false
                        isPromptVisible.value = false
                        showsReflectionCreditsSheet.value = true
                        viewModel.refreshCredits()
                    },
                    didCopyAnkyContract = didCopyAnkyContract.value,
                    showsAccountDeletion = showsAccountDeletion.value,
                    onToggleAccountDeletion = { showsAccountDeletion.value = !showsAccountDeletion.value },
                    onDeleteAccountAndData = { confirmDeleteAccountAndData.value = true },
                    onAppLockChange = onAppLockChange,
                    onEncryptedBackupToggle = { enabled ->
                        if (enabled) {
                            viewModel.enableEncryptedBackup(enableEncryptedBackupReason, couldNotConfirmIdentity)
                        } else {
                            viewModel.disableEncryptedBackup()
                        }
                    },
                    onPrompt = {
                        activePrompt.value = it
                        isShowingSystemPrompt.value = false
                        isPromptVisible.value = true
                        if (it == YouPrompt.Credits) {
                            viewModel.refreshCredits()
                        }
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
                        } else if (isConversationThinking(activePrompt.value, state)) {
                            emptyList()
                        } else {
                            youPromptActions(
                                prompt = activePrompt.value,
                                state = state,
                                context = context,
                                viewModel = viewModel,
                                labels = YouPromptActionLabels(
                                    backUpRecoveryWords = stringResource(R.string.you_backup_recovery_words),
                                    backingUp = stringResource(R.string.backing_up),
                                    backUpNow = stringResource(R.string.back_up_now),
                                    exportWritings = stringResource(R.string.export_writings),
                                    copyAccount = stringResource(R.string.copy_account),
                                    ankyAddress = stringResource(R.string.anky_address),
                                    deleteLocalData = stringResource(R.string.delete_local_data),
                                    openEmail = stringResource(R.string.open_email),
                                    backupRecoveryWordsSecureStorageReason = backupRecoveryWordsSecureStorageReason,
                                    enableEncryptedBackupReason = enableEncryptedBackupReason,
                                    couldNotConfirmIdentity = couldNotConfirmIdentity,
                                ),
                                page = { page.value = it },
                                confirmDeleteLocalData = { confirmDeleteLocalData.value = true },
                            )
                        },
                        onClose = { isPromptVisible.value = false },
                        isThinking = !isShowingSystemPrompt.value && isConversationThinking(activePrompt.value, state),
                        modifier = Modifier
                            .align(Alignment.BottomCenter)
                            .padding(start = 18.dp, end = 18.dp, bottom = 96.dp),
                    )
                }
            } else if (page.value == YouPage.History) {
                YouHistoryPage(
                    state = state,
                    onBack = { page.value = null },
                    onOpenReveal = onOpenReveal,
                    onWriteRequested = onWriteRequested,
                )
            } else {
                YouDetailShell(
                    page = page.value!!,
                    onBack = {
                        if (initialPage != null && onInitialPageBack != null) {
                            onInitialPageBack()
                        } else {
                            page.value = null
                        }
                    },
                ) {
                    when (page.value!!) {
                        YouPage.Account -> AccountPage(
                            state = state,
                            onCopyAccountId = { context.copyText(ankyAddressClipboardLabel, state.accountId) },
                            onRevealRecovery = { viewModel.revealRecoveryPhrase(showRecoveryWordsReason, couldNotConfirmIdentity) },
                            onBackupIdentity = {
                                viewModel.backUpIdentityToDeviceSecureStorage(
                                    backupRecoveryWordsSecureStorageReason,
                                    couldNotConfirmIdentity,
                                )
                            },
                            onCopyRecovery = { state.recoveryPhrase?.let { context.copyText(recoveryWordsClipboardLabel, it) } },
                            onHideRecovery = viewModel::hideRecoveryPhrase,
                            onImportPhrase = {
                                phraseInput.value = ""
                                showImportPhrase.value = true
                            },
                            onAppLock = onAppLockChange,
                            onReminder = setReminderWithPermission,
                            onReminderTime = { showReminderTime.value = true },
                            onDeleteAccountAndData = { confirmDeleteAccountAndData.value = true },
                        )
                        YouPage.Privacy -> PrivacyPage()
                        YouPage.Terms -> TermsPage()
                        YouPage.Export -> ExportPage(
                            state = state,
                            onExport = viewModel::exportArchive,
                            onPrepareWritingExport = viewModel::prepareFormattedWritingExport,
                            onEncryptedBackupToggle = { enabled ->
                                if (enabled) {
                                    viewModel.enableEncryptedBackup(enableEncryptedBackupReason, couldNotConfirmIdentity)
                                } else {
                                    viewModel.disableEncryptedBackup()
                                }
                            },
                            onEncryptedBackupNow = viewModel::backUpEncryptedNow,
                            onRestoreEncryptedBackup = {
                                viewModel.restoreEncryptedBackup(restoreEncryptedBackupReason, couldNotConfirmIdentity)
                            },
                            onShareWritingExport = { state.formattedWritingExportFile?.let { context.shareFile(it, "text/markdown", exportWritingsChooserTitle) } },
                            onShareBackup = { state.exportedFile?.let { context.shareFile(it, "application/zip", exportBackupZipChooserTitle) } },
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
                        YouPage.History -> Unit
                        YouPage.Credits -> CreditsPage(
                            state = state,
                            onRefresh = viewModel::refreshCredits,
                            onRestorePurchases = viewModel::restorePurchases,
                            onPurchase = { packageId -> viewModel.purchaseCredits(packageId, context.findActivity()) },
                            onSupportFeedback = { context.openUrl(state.supportFeedbackEmailUrl) },
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
            if (isShowingAnkyExperience.value) {
                AnkyExperienceOverlay(
                    onClose = { isShowingAnkyExperience.value = false },
                    modifier = Modifier.fillMaxSize(),
                )
            }
        }
    }

    if (showsReflectionCreditsSheet.value) {
        ModalBottomSheet(
            onDismissRequest = { showsReflectionCreditsSheet.value = false },
            sheetState = reflectionCreditsSheetState,
            containerColor = Color(0xFF06050A),
        ) {
            YouReflectionCreditsSheet(
                state = state,
                onRefresh = viewModel::refreshCredits,
                onPurchase = { packageId -> viewModel.purchaseCredits(packageId, context.findActivity()) },
                modifier = Modifier.padding(start = 22.dp, end = 22.dp, bottom = 28.dp),
            )
        }
    }

    if (showImportPhrase.value) {
        AlertDialog(
            onDismissRequest = { showImportPhrase.value = false },
            title = { Text(stringResource(R.string.you_recover_access_lower), style = AnkyType.Heading) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    OutlinedTextField(
                        value = phraseInput.value,
                        onValueChange = { phraseInput.value = it },
                        textStyle = AnkyType.Mono,
                        minLines = 4,
                        label = { Text(stringResource(R.string.you_recovery_words_label)) },
                    )
                    Text(stringResource(R.string.you_recovery_replaces_access), style = AnkyType.Body.copy(fontSize = 14.sp, color = AnkyColors.PaperMuted))
                }
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        viewModel.importRecoveryPhrase(
                            phraseInput.value,
                            recoverAnkyAccessReason,
                            couldNotConfirmIdentity,
                        ) {
                            phraseInput.value = ""
                            showImportPhrase.value = false
                        }
                    },
                    enabled = phraseInput.value.isNotBlank(),
                ) { Text(stringResource(R.string.recover)) }
            },
            dismissButton = {
                TextButton(onClick = { showImportPhrase.value = false }) { Text(stringResource(R.string.cancel)) }
            },
            containerColor = AnkyColors.PanelStrong,
        )
    }

    if (confirmDeleteLocalData.value) {
        AlertDialog(
            onDismissRequest = { confirmDeleteLocalData.value = false },
            title = { Text(stringResource(R.string.you_delete_local_writing_data_question), style = AnkyType.Heading.copy(color = AnkyColors.Danger)) },
            text = {
                Text(
                    stringResource(R.string.you_delete_local_data_body),
                    style = AnkyType.Body.copy(fontSize = 14.sp, color = AnkyColors.PaperMuted),
                )
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        confirmDeleteLocalData.value = false
                        viewModel.clearLocalWritingData()
                    },
                ) { Text(stringResource(R.string.you_delete_local_writing_data_action), color = AnkyColors.Danger) }
            },
            dismissButton = {
                TextButton(onClick = { confirmDeleteLocalData.value = false }) { Text(stringResource(R.string.cancel)) }
            },
            containerColor = AnkyColors.PanelStrong,
        )
    }

    if (confirmDeleteAccountAndData.value) {
        AlertDialog(
            onDismissRequest = { confirmDeleteAccountAndData.value = false },
            title = { Text(stringResource(R.string.you_delete_account_data_question), style = AnkyType.Heading.copy(color = AnkyColors.Danger)) },
            text = {
                Text(
                    stringResource(R.string.you_delete_account_data_body),
                    style = AnkyType.Body.copy(fontSize = 14.sp, color = AnkyColors.PaperMuted),
                )
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        confirmDeleteAccountAndData.value = false
                        viewModel.deleteAccountAndDataEverywhere(onDeleted = onAccountDeleted)
                    },
                ) { Text(stringResource(R.string.delete), color = AnkyColors.Danger) }
            },
            dismissButton = {
                TextButton(onClick = { confirmDeleteAccountAndData.value = false }) { Text(stringResource(R.string.cancel_title)) }
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
            message = "Resetting identity creates a new Anky Base account. Credits are tied to your current account. Save your recovery phrase before resetting.",
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
            title = { Text(stringResource(R.string.time), style = AnkyType.Heading) },
            text = {
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    OutlinedTextField(
                        value = reminderHourInput.value,
                        onValueChange = { reminderHourInput.value = it.filter(Char::isDigit).take(2) },
                        textStyle = AnkyType.Mono,
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                        label = { Text(stringResource(R.string.hour)) },
                        modifier = Modifier.weight(1f),
                    )
                    OutlinedTextField(
                        value = reminderMinuteInput.value,
                        onValueChange = { reminderMinuteInput.value = it.filter(Char::isDigit).take(2) },
                        textStyle = AnkyType.Mono,
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                        label = { Text(stringResource(R.string.minute)) },
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
                ) { Text(stringResource(R.string.set)) }
            },
            dismissButton = {
                TextButton(onClick = { showReminderTime.value = false }) { Text(stringResource(R.string.cancel)) }
            },
            containerColor = AnkyColors.PanelStrong,
        )
    }
}

@Composable
private fun DestructiveConfirmDialog(
    title: String,
    action: String,
    message: String? = null,
    onDismiss: () -> Unit,
    onConfirm: () -> Unit,
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title, style = AnkyType.Heading.copy(color = AnkyColors.Danger)) },
        text = message?.let {
            { Text(it, style = AnkyType.Body.copy(fontSize = 14.sp, color = AnkyColors.PaperMuted)) }
        },
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
private fun AnkyExperienceOverlay(
    onClose: () -> Unit,
    modifier: Modifier = Modifier,
) {
    AnkyExperienceSystemBarsHidden()
    val context = LocalContext.current
    val startedAtMs = remember { System.currentTimeMillis() }
    val elapsedSeconds = remember { mutableStateOf(0) }
    val writer = remember { mutableStateOf(AnkyWriter()) }
    val displayedText = remember { mutableStateOf("") }
    val protocolText = remember { mutableStateOf("") }
    val showCopyPrompt = remember { mutableStateOf(false) }
    val ankyExperienceArtifactLabel = stringResource(R.string.anky_experience_artifact_label)
    val ankyExperienceWritingLabel = stringResource(R.string.anky_experience_writing_label)
    val ankyExperienceOpen = stringResource(R.string.anky_experience_open)
    val ankyExperienceComplete = stringResource(R.string.anky_experience_complete)
    val closeAnkyExperienceLabel = stringResource(R.string.close_anky_experience)
    val ankyCompanionLabel = stringResource(R.string.anky_companion)
    val copyPromptMessage = stringResource(R.string.copy_your_anky_or_writing)
    val copyAnkyAction = stringResource(R.string.copy_your_anky)
    val copyWritingAction = stringResource(R.string.copy_your_writing)

    fun finishIfNeeded() {
        if (elapsedSeconds.value < AnkyExperienceTotalSeconds) return
        if (!writer.value.isStarted || writer.value.isClosed) return
        writer.value.closeWithTerminalSilence()
        protocolText.value = writer.value.text
    }

    fun acceptGlyph(glyph: String) {
        finishIfNeeded()
        if (elapsedSeconds.value >= AnkyExperienceTotalSeconds) return
        if (writer.value.accept(glyph, System.currentTimeMillis())) {
            displayedText.value += glyph
            protocolText.value = writer.value.text
        }
    }

    fun copyCurrentAnky() {
        finishIfNeeded()
        if (protocolText.value.isNotBlank()) {
            context.copyText(ankyExperienceArtifactLabel, protocolText.value)
        }
    }

    fun copyCurrentWriting() {
        finishIfNeeded()
        val writing = runCatching {
            AnkyReconstructor.reconstructText(AnkyParser.parse(protocolText.value))
        }.getOrDefault(displayedText.value)
        if (writing.isNotBlank()) {
            context.copyText(ankyExperienceWritingLabel, writing)
        }
    }

    LaunchedEffect(Unit) {
        while (true) {
            elapsedSeconds.value = minOf(
                AnkyExperienceTotalSeconds,
                ((System.currentTimeMillis() - startedAtMs) / 1000L).toInt(),
            )
            finishIfNeeded()
            if (elapsedSeconds.value >= AnkyExperienceTotalSeconds) break
            delay(250)
        }
    }

    val isFinished = elapsedSeconds.value >= AnkyExperienceTotalSeconds
    val remainingSeconds = maxOf(0, AnkyExperienceTotalSeconds - elapsedSeconds.value)
    val elapsedClock = experienceClock(elapsedSeconds.value)
    val remainingClock = experienceClock(remainingSeconds)
    val subtitle = if (isFinished) ankyExperienceComplete else ankyExperienceOpen
    val elapsedTimeLabel = stringResource(R.string.anky_experience_time_format, elapsedClock)
    val progress = 1f - (remainingSeconds.toFloat() / AnkyExperienceTotalSeconds.toFloat())

    Box(
        modifier = modifier
            .background(AnkyColors.Ink.copy(alpha = 0.98f))
            .testTag("anky-experience"),
    ) {
        if (!isFinished) {
            HiddenTextInput(
                onGlyph = ::acceptGlyph,
                onGlyphs = { glyphs -> glyphs.forEach(::acceptGlyph) },
                onRejectedMutation = {},
                modifier = Modifier.fillMaxSize(),
            )
            Text(
                displayedText.value,
                style = AnkyType.Body.copy(fontSize = 20.sp, color = AnkyColors.Paper.copy(alpha = 0.34f)),
                modifier = Modifier
                    .fillMaxSize()
                    .padding(24.dp),
            )
        }

        Text(
            elapsedClock,
            style = AnkyType.Mono.copy(fontSize = 13.sp, color = AnkyColors.Paper.copy(alpha = 0.58f)),
            modifier = Modifier
                .align(Alignment.TopStart)
                .padding(top = 48.dp, start = 12.dp)
                .clip(CircleShape)
                .background(AnkyColors.Panel.copy(alpha = 0.70f))
                .semantics {
                    contentDescription = elapsedTimeLabel
                }
                .padding(horizontal = 10.dp, vertical = 8.dp),
        )

        Box(
            modifier = Modifier
                .align(Alignment.TopEnd)
                .padding(top = 42.dp, end = 12.dp)
                .size(42.dp)
                .clip(CircleShape)
                .background(AnkyColors.Panel.copy(alpha = 0.70f))
                .clickable(onClick = onClose),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                "x",
                style = AnkyType.Body.copy(fontSize = 18.sp, color = AnkyColors.Paper.copy(alpha = 0.72f)),
                modifier = Modifier.semantics {
                    contentDescription = closeAnkyExperienceLabel
                },
            )
        }

        ExperiencePortalRing(
            progress = progress,
            clockText = remainingClock,
            subtitle = subtitle,
            modifier = Modifier.align(Alignment.Center),
        )

        Box(
            modifier = Modifier
                .align(Alignment.BottomEnd)
                .padding(end = 18.dp, bottom = 18.dp)
                .size(44.dp)
                .clip(CircleShape)
                .clickable { showCopyPrompt.value = true },
            contentAlignment = Alignment.Center,
        ) {
            Image(
                painter = painterResource(R.drawable.anky001),
                contentDescription = ankyCompanionLabel,
                contentScale = ContentScale.Fit,
                modifier = Modifier.size(44.dp),
            )
        }

        if (showCopyPrompt.value) {
            AnkyConversationPrompt(
                message = copyPromptMessage,
                actions = listOf(
                    AnkyChatAction(copyAnkyAction, isPrimary = true) { copyCurrentAnky() },
                    AnkyChatAction(copyWritingAction) { copyCurrentWriting() },
                ),
                onClose = { showCopyPrompt.value = false },
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .padding(start = 18.dp, end = 18.dp, bottom = 76.dp),
            )
        }
    }
}

@Composable
private fun AnkyExperienceSystemBarsHidden() {
    val activity = LocalContext.current.findActivity() ?: return
    DisposableEffect(activity) {
        val window = activity.window
        val controller = WindowCompat.getInsetsController(window, window.decorView)
        WindowCompat.setDecorFitsSystemWindows(window, false)
        controller.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        controller.hide(WindowInsetsCompat.Type.systemBars())
        onDispose {
            controller.show(WindowInsetsCompat.Type.systemBars())
            WindowCompat.setDecorFitsSystemWindows(window, true)
        }
    }
}

@Composable
private fun ExperiencePortalRing(
    progress: Float,
    clockText: String,
    subtitle: String,
    modifier: Modifier = Modifier,
) {
    val ringAccessibilityLabel = stringResource(R.string.anky_experience_ring_accessibility, clockText, subtitle)
    val colors = listOf(
        Color.Red,
        Color(0xFFFF9800),
        Color.Yellow,
        Color.Green,
        Color.Blue,
        Color(0xFF4B0082),
        Color(0xFF8A2BE2),
        Color.White,
    )

    Box(
        modifier = modifier
            .size(220.dp)
            .semantics {
                contentDescription = ringAccessibilityLabel
            },
        contentAlignment = Alignment.Center,
    ) {
        Canvas(Modifier.size(220.dp)) {
            val diameter = 206.dp.toPx()
            val topLeft = Offset((size.width - diameter) / 2f, (size.height - diameter) / 2f)
            val arcSize = Size(diameter, diameter)
            colors.forEachIndexed { index, color ->
                val segmentProgress = ((progress * 8f) - index).coerceIn(0f, 1f)
                val start = -90f + index * 45f
                drawArc(
                    color = color.copy(alpha = 0.18f),
                    startAngle = start,
                    sweepAngle = 45f,
                    useCenter = false,
                    topLeft = topLeft,
                    size = arcSize,
                    style = Stroke(width = 12.dp.toPx(), cap = StrokeCap.Butt),
                )
                if (segmentProgress > 0f) {
                    drawArc(
                        color = color,
                        startAngle = start,
                        sweepAngle = 45f * segmentProgress,
                        useCenter = false,
                        topLeft = topLeft,
                        size = arcSize,
                        style = Stroke(width = 12.dp.toPx(), cap = StrokeCap.Butt),
                    )
                }
            }
        }
        Box(
            modifier = Modifier
                .size(176.dp)
                .clip(CircleShape)
                .background(AnkyColors.Panel.copy(alpha = 0.82f))
                .border(1.dp, Color.White.copy(alpha = 0.16f), CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Text(
                    clockText,
                    style = AnkyType.Mono.copy(fontSize = 38.sp, color = AnkyColors.Paper.copy(alpha = 0.88f)),
                    maxLines = 1,
                )
                Text(
                    subtitle,
                    style = AnkyType.Caption.copy(fontSize = 11.sp, color = AnkyColors.PaperMuted.copy(alpha = 0.86f)),
                    textAlign = TextAlign.Center,
                    modifier = Modifier.size(width = 128.dp, height = 36.dp),
                )
            }
        }
    }
}

private fun experienceClock(seconds: Int): String {
    val safeSeconds = maxOf(0, seconds)
    val minutes = safeSeconds / 60
    val remainder = safeSeconds % 60
    return "$minutes:${remainder.toString().padStart(2, '0')}"
}

@Composable
private fun YouHome(
    state: YouState,
    activePrompt: YouPrompt?,
    onOpenPage: (YouPage) -> Unit,
    onCopyAnkyContract: () -> Unit,
    onOpenCreditsSheet: () -> Unit,
    didCopyAnkyContract: Boolean,
    showsAccountDeletion: Boolean,
    onToggleAccountDeletion: () -> Unit,
    onDeleteAccountAndData: () -> Unit,
    onAppLockChange: (Boolean) -> Unit,
    onEncryptedBackupToggle: (Boolean) -> Unit,
    onPrompt: (YouPrompt) -> Unit,
) {
    val context = LocalContext.current
    val shouldShowDeviceLockControl = remember(context) { canUseDeviceLock(context) }
    val lockTitle = deviceLockControlTitle(context)
    val hideDeleteAccountActionLabel = stringResource(R.string.hide_delete_account_action)
    val showDeleteAccountActionLabel = stringResource(R.string.show_delete_account_action)
    val dataSubtitle = if (state.isEncryptedBackupEnabled) {
        stringResource(R.string.you_encrypted_backup_on)
    } else {
        stringResource(R.string.you_export_writings_or_enable_backup)
    }
    val creditsSubtitle = creditsMenuSubtitle(
        state = state,
        loadingBalance = stringResource(R.string.you_loading_balance),
        reflectionBalance = stringResource(R.string.you_reflection_balance),
        creditSingular = stringResource(R.string.credit),
        creditPlural = stringResource(R.string.credits),
    )
    Box(Modifier.fillMaxSize()) {
        Text(
            stringResource(R.string.you_title),
            style = AnkyType.Body.copy(
                fontSize = 17.sp,
                fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold,
                color = AnkyColors.Paper,
            ),
            modifier = Modifier
                .align(Alignment.TopCenter)
                .padding(top = 56.dp),
            maxLines = 1,
        )
        Column(
            modifier = Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(top = 106.dp, bottom = 220.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(20.dp),
        ) {
            AnkyPanel(contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 16.dp, vertical = 0.dp)) {
                DataToggleRow(
                    title = stringResource(R.string.you_data),
                    subtitle = dataSubtitle,
                    checked = state.isEncryptedBackupEnabled,
                    onToggle = onEncryptedBackupToggle,
                    onClick = { onPrompt(YouPrompt.Export) },
                )
                Divider()
                PromptRow(R.drawable.you_icon_credits, stringResource(R.string.you_credits), creditsSubtitle, activePrompt == YouPrompt.Credits) { onOpenCreditsSheet() }
                Divider()
                PromptRow(R.drawable.you_icon_support, stringResource(R.string.you_support_feedback), stringResource(R.string.you_email_support), activePrompt == YouPrompt.Support) { onPrompt(YouPrompt.Support) }
                Divider()
                PromptRow(R.drawable.you_icon_privacy, stringResource(R.string.you_privacy_policy), stringResource(R.string.you_privacy_subtitle), selected = false) { onOpenPage(YouPage.Privacy) }
                Divider()
                PromptRow(R.drawable.you_icon_terms, stringResource(R.string.you_terms_conditions), stringResource(R.string.you_terms_subtitle), selected = false) { onOpenPage(YouPage.Terms) }
                if (shouldShowDeviceLockControl) {
                    Divider()
                    DeviceLockRow(
                        title = lockTitle,
                        checked = state.appLockEnabled,
                        checkedText = stringResource(R.string.on),
                        uncheckedText = stringResource(R.string.off),
                        onChecked = onAppLockChange,
                    )
                }
                /*
                Divider()
                PromptRow(R.drawable.you_icon_anky_token, "\$ANKY", if (didCopyAnkyContract) stringResource(R.string.you_copied_to_clipboard) else ankyContractDisplayAddress(), selected = false) { onCopyAnkyContract() }
                */
            }
            if (showsAccountDeletion) {
                AnkyPanel(contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 16.dp, vertical = 0.dp)) {
                    DestructiveMenuRow(stringResource(R.string.you_delete_account_data_caps), onClick = onDeleteAccountAndData)
                }
            }
        }
        IconButton(
            onClick = onToggleAccountDeletion,
            modifier = Modifier
                .align(Alignment.TopEnd)
                .padding(top = 46.dp, end = 16.dp)
                .semantics {
                    contentDescription = if (showsAccountDeletion) {
                        hideDeleteAccountActionLabel
                    } else {
                        showDeleteAccountActionLabel
                    }
                },
        ) {
            Icon(
                imageVector = Icons.Filled.PriorityHigh,
                contentDescription = null,
                tint = AnkyColors.Danger.copy(alpha = 0.88f),
                modifier = Modifier.size(24.dp),
            )
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
private fun YouStats(state: YouState, onClick: () -> Unit) {
    val openAllAnkysLabel = stringResource(R.string.open_all_ankys)
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .semantics { contentDescription = openAllAnkysLabel },
    ) {
        AnkyPanel(contentPadding = androidx.compose.foundation.layout.PaddingValues(0.dp)) {
            Row(Modifier.fillMaxWidth().height(68.dp), verticalAlignment = Alignment.CenterVertically) {
                StatCell(R.drawable.you_icon_feather_stat, state.completeAnkyCount.toString(), stringResource(R.string.you_stat_ankys))
                VerticalDivider()
                StatCell(R.drawable.you_icon_clock_stat, state.totalWritingMinutes.toString(), stringResource(R.string.you_stat_minutes))
                VerticalDivider()
                StatCell(R.drawable.you_icon_flame_stat, state.currentStreak.toString(), stringResource(R.string.you_stat_streak))
            }
        }
    }
}

@Composable
private fun YouHistoryPage(
    state: YouState,
    onBack: () -> Unit,
    onOpenReveal: (String) -> Unit,
    onWriteRequested: () -> Unit,
) {
    val sessions = state.completeAnkySessions
    val backLabel = stringResource(R.string.back)
    val oneAnkyFormat = stringResource(R.string.one_anky_count_format)
    val ankysFormat = stringResource(R.string.ankys_count_format)
    val wordSingular = stringResource(R.string.word)
    val wordPlural = stringResource(R.string.words)
    Box(Modifier.fillMaxSize()) {
        Image(
            painter = painterResource(R.drawable.map_background),
            contentDescription = null,
            contentScale = ContentScale.Crop,
            modifier = Modifier.fillMaxSize(),
        )
        Box(Modifier.fillMaxSize().background(AnkyColors.Ink.copy(alpha = 0.76f)))
        Column(Modifier.fillMaxSize()) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(AnkyColors.Ink.copy(alpha = 0.96f))
                    .padding(horizontal = 12.dp, vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                IconButton(onClick = onBack) {
                    Icon(
                        imageVector = Icons.Filled.ChevronLeft,
                        contentDescription = backLabel,
                        tint = AnkyColors.Gold,
                        modifier = Modifier.size(30.dp),
                    )
                }
                Text(
                    historyTitle(sessions.size, oneAnkyFormat, ankysFormat),
                    style = AnkyType.Body.copy(
                        fontSize = 17.sp,
                        fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold,
                        color = AnkyColors.Paper,
                    ),
                    modifier = Modifier.weight(1f),
                    textAlign = TextAlign.Center,
                )
                Spacer(Modifier.size(48.dp))
            }
            BoxWithConstraints(Modifier.fillMaxSize()) {
                val contentWidth = maxWidth * 0.87f
                val horizontalPadding = (maxWidth - contentWidth) / 2
                if (sessions.isEmpty()) {
                    Column(
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(horizontal = horizontalPadding)
                            .padding(top = 96.dp, bottom = 152.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(24.dp),
                    ) {
                        Text(
                            stringResource(R.string.zero_ankys),
                            style = AnkyType.Title.copy(fontSize = 36.sp, color = AnkyColors.Gold),
                            textAlign = TextAlign.Center,
                        )
                        AnkyActionButton(
                            stringResource(R.string.write_minutes_caps, AnkyDuration.CompleteRitualMinutes),
                            onClick = onWriteRequested,
                            modifier = Modifier.fillMaxWidth(),
                        )
                    }
                } else {
                    LazyColumn(
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(horizontal = horizontalPadding)
                            .padding(top = 24.dp, bottom = 152.dp),
                    ) {
                        items(sessions, key = { it.hash }) { session ->
                            YouHistorySessionRow(
                                session = session,
                                wordSingular = wordSingular,
                                wordPlural = wordPlural,
                                onOpenReveal = onOpenReveal,
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun YouHistorySessionRow(
    session: SessionSummary,
    wordSingular: String,
    wordPlural: String,
    onOpenReveal: (String) -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable { onOpenReveal(session.hash) }
            .semantics(mergeDescendants = true) { contentDescription = historySessionAccessibilityLabel(session) }
            .padding(vertical = 15.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Text(
                session.title.lowercase(),
                style = AnkyType.Mono.copy(
                    fontSize = 15.sp,
                    fontWeight = androidx.compose.ui.text.font.FontWeight.Bold,
                    color = AnkyColors.Gold.copy(alpha = 0.9f),
                ),
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                session.createdAt.formattedForYouHistory(),
                style = AnkyType.Mono.copy(
                    fontSize = 12.sp,
                    fontWeight = androidx.compose.ui.text.font.FontWeight.Medium,
                    color = AnkyColors.Paper.copy(alpha = 0.58f),
                ),
            )
            Text(
                "${session.wordCount} ${if (session.wordCount == 1) wordSingular else wordPlural}",
                style = AnkyType.Mono.copy(
                    fontSize = 12.sp,
                    fontWeight = androidx.compose.ui.text.font.FontWeight.Medium,
                    color = AnkyColors.Paper.copy(alpha = 0.48f),
                ),
            )
        }
        Icon(
            imageVector = Icons.Filled.ChevronRight,
            contentDescription = null,
            tint = AnkyColors.Gold.copy(alpha = 0.7f),
            modifier = Modifier.size(13.dp),
        )
    }
    Box(
        Modifier
            .fillMaxWidth()
            .height(1.dp)
            .background(AnkyColors.Gold.copy(alpha = 0.13f)),
    )
}

private fun historyTitle(count: Int, oneAnkyFormat: String, ankysFormat: String): String =
    if (count == 1) oneAnkyFormat.format(count) else ankysFormat.format(count)

private fun historySessionAccessibilityLabel(session: SessionSummary): String =
    listOf(session.title, session.preview).joinToString(", ")

private fun java.time.Instant.formattedForYouHistory(): String =
    DateTimeFormatter
        .ofLocalizedDateTime(FormatStyle.MEDIUM, FormatStyle.SHORT)
        .withLocale(Locale.getDefault())
        .withZone(ZoneId.systemDefault())
        .format(this)

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
private fun DestructiveMenuRow(title: String, onClick: () -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick).padding(vertical = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            imageVector = Icons.Filled.PriorityHigh,
            contentDescription = null,
            tint = AnkyColors.Danger.copy(alpha = 0.9f),
            modifier = Modifier.size(22.dp),
        )
        Text(
            title,
            style = AnkyType.Body.copy(
                fontSize = 16.sp,
                fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold,
                color = AnkyColors.Danger.copy(alpha = 0.94f),
            ),
            modifier = Modifier.padding(start = 13.dp),
            maxLines = 1,
        )
    }
}

@Composable
private fun DeviceLockRow(
    title: String,
    checked: Boolean,
    checkedText: String,
    uncheckedText: String,
    onChecked: (Boolean) -> Unit,
) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            imageVector = Icons.Filled.Lock,
            contentDescription = null,
            tint = AnkyColors.PaperMuted.copy(alpha = 0.86f),
            modifier = Modifier.size(24.dp),
        )
        Column(Modifier.weight(1f).padding(start = 13.dp)) {
            Text(
                title,
                style = AnkyType.Body.copy(
                    fontSize = 17.sp,
                    fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold,
                    color = AnkyColors.Paper,
                ),
                maxLines = 1,
            )
            Text(
                if (checked) checkedText else uncheckedText,
                style = AnkyType.Caption.copy(fontSize = 12.sp, color = AnkyColors.PaperMuted),
                maxLines = 1,
            )
        }
        Switch(checked = checked, onCheckedChange = onChecked)
    }
}

@Composable
private fun DataToggleRow(
    title: String,
    subtitle: String,
    checked: Boolean,
    onToggle: (Boolean) -> Unit,
    onClick: () -> Unit,
) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Row(
            modifier = Modifier.weight(1f).clickable(onClick = onClick),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Image(painterResource(R.drawable.you_icon_export), contentDescription = null, modifier = Modifier.size(30.dp))
            Column(Modifier.padding(start = 13.dp)) {
                Text(
                    title,
                    style = AnkyType.Body.copy(
                        fontSize = 17.sp,
                        fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold,
                        color = AnkyColors.Paper,
                    ),
                    maxLines = 1,
                )
                Text(
                    subtitle,
                    style = AnkyType.Caption.copy(fontSize = 12.sp, color = AnkyColors.PaperMuted),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
        Switch(checked = checked, onCheckedChange = onToggle)
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
    val backLabel = stringResource(R.string.back)
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
                    contentDescription = backLabel,
                    tint = AnkyColors.Gold,
                    modifier = Modifier.size(24.dp),
                )
            }
            Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally) {
                Text(stringResource(page.titleRes), style = AnkyType.Heading.copy(fontSize = 26.sp))
                Text(stringResource(page.subtitleRes), style = AnkyType.Caption.copy(color = AnkyColors.PaperMuted))
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
    onBackupIdentity: () -> Unit,
    onCopyRecovery: () -> Unit,
    onHideRecovery: () -> Unit,
    onImportPhrase: () -> Unit,
    onAppLock: (Boolean) -> Unit,
    onReminder: (Boolean) -> Unit,
    onReminderTime: () -> Unit,
    onDeleteAccountAndData: () -> Unit,
) {
    val context = LocalContext.current
    val lockLabel = remember(context) { biometricLockLabel(context) }
    AnkyPanel {
        Text(stringResource(R.string.you_private_access), style = AnkyType.Caption)
        Text(
            stringResource(R.string.you_private_profile),
            style = AnkyType.Body.copy(
                fontSize = 17.sp,
                fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold,
                color = AnkyColors.Paper,
            ),
        )
        Text(stringResource(R.string.you_writing_access_stays), style = AnkyType.Body.copy(fontSize = 14.sp, color = AnkyColors.PaperMuted))
    }
    AnkyPanel {
        Text(stringResource(R.string.you_advanced_recovery), style = AnkyType.Caption)
        Text(stringResource(R.string.you_recovery_words_restore), style = AnkyType.Body.copy(fontSize = 14.sp, color = AnkyColors.PaperMuted))
        Divider()
        SwitchRow(stringResource(R.string.device_lock_app_protection), state.appLockEnabled, onAppLock)
        Text(stringResource(R.string.you_recovery_words_gate), style = AnkyType.Body.copy(fontSize = 14.sp, color = AnkyColors.PaperMuted))
        Text(stringResource(R.string.you_passcode_biometrics_note), style = AnkyType.Body.copy(fontSize = 14.sp, color = AnkyColors.PaperMuted))
        if (state.recoveryPhrase == null) {
            AnkyActionButton(stringResource(R.string.you_reveal_recovery_words), enabled = state.appLockEnabled, onClick = onRevealRecovery)
        } else {
            Text(state.recoveryPhrase, style = AnkyType.Mono.copy(color = AnkyColors.Paper))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                AnkyActionButton(stringResource(R.string.you_copy_recovery_words), modifier = Modifier.weight(1f), onClick = onCopyRecovery)
                AnkyActionButton(stringResource(R.string.hide), modifier = Modifier.weight(1f), onClick = onHideRecovery)
            }
        }
        AnkyActionButton(stringResource(R.string.you_recover_access), onClick = onImportPhrase)
        AnkyActionButton(stringResource(R.string.you_backup_recovery_words_secure_storage), onClick = onBackupIdentity)
        Text(stringResource(R.string.you_secure_storage_note), style = AnkyType.Body.copy(fontSize = 14.sp, color = AnkyColors.PaperMuted))
        Text(stringResource(R.string.anky_address), style = AnkyType.Caption)
        Text(state.accountId, style = AnkyType.Mono.copy(color = AnkyColors.PaperMuted))
        AnkyActionButton(stringResource(R.string.copy_account), onClick = onCopyAccountId)
    }
    AnkyPanel {
        SwitchRow(stringResource(R.string.daily_reminder), state.dailyReminderEnabled, onReminder)
        DetailRow(stringResource(R.string.time), YouViewModel.formatReminderTime(state.dailyReminderMinutes))
        AnkyActionButton(stringResource(R.string.change_time), enabled = state.dailyReminderEnabled, onClick = onReminderTime)
    }
    AnkyPanel {
        Text(stringResource(R.string.you_ownership_note), style = AnkyType.Caption)
        Text(stringResource(R.string.you_ownership_body), style = AnkyType.Body.copy(fontSize = 14.sp, color = AnkyColors.PaperMuted))
    }
    YouDangerPanel {
        Text(stringResource(R.string.danger_zone), style = AnkyType.Heading.copy(fontSize = 18.sp, color = AnkyColors.Danger))
        Text(stringResource(R.string.you_delete_account_data_detail_body), style = AnkyType.Body.copy(fontSize = 14.sp, color = AnkyColors.PaperMuted))
        AnkyActionButton(stringResource(R.string.you_delete_account_data_caps), destructive = true, onClick = onDeleteAccountAndData)
    }
}

@Composable
private fun PrivacyPage() {
    Text(stringResource(R.string.privacy_page_heading), style = AnkyType.Heading.copy(fontSize = 19.sp, color = AnkyColors.Paper), textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())
    PrivacyCopy.forEach { ArticleLine(it) }
    AnkyPanel {
        Text(stringResource(R.string.privacy_contact_caption), style = AnkyType.Caption)
        Text("jp@anky.app", style = AnkyType.Mono.copy(color = AnkyColors.Paper))
    }
}

@Composable
private fun TermsPage() {
    Text(stringResource(R.string.you_terms_conditions), style = AnkyType.Heading.copy(fontSize = 24.sp, color = AnkyColors.Paper), textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())
    Text(stringResource(R.string.terms_reflection_agreement), style = AnkyType.Caption.copy(color = AnkyColors.PaperMuted), textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())
    TermsCopy.forEach { ArticleLine(it) }
}

@Composable
private fun ExportPage(
    state: YouState,
    onExport: () -> Unit,
    onPrepareWritingExport: () -> Unit,
    onEncryptedBackupToggle: (Boolean) -> Unit,
    onEncryptedBackupNow: () -> Unit,
    onRestoreEncryptedBackup: () -> Unit,
    onShareWritingExport: () -> Unit,
    onShareBackup: () -> Unit,
    onRestore: () -> Unit,
    onDeleteLocalData: () -> Unit,
) {
    LaunchedEffect(Unit) {
        onExport()
        onPrepareWritingExport()
    }

    AnkyPanel {
        Text(stringResource(R.string.you_local_files_reflections_format, state.localAnkyFileCount, state.reflectionCount), style = AnkyType.Heading)
        Text(stringResource(R.string.you_readable_exports_note), style = AnkyType.Body.copy(fontSize = 14.sp, color = AnkyColors.PaperMuted))
    }
    AnkyPanel {
        when (formattedWritingExportAction(state)) {
            FormattedWritingExportAction.Share -> AnkyActionButton(stringResource(R.string.export_writings), onClick = onShareWritingExport)
            FormattedWritingExportAction.Empty -> DisabledRow(stringResource(R.string.you_no_writing_to_export))
        }
    }
    AnkyPanel {
        SwitchRow(stringResource(R.string.you_encrypted_backup), state.isEncryptedBackupEnabled, onEncryptedBackupToggle)
        Text(encryptedBackupDetail(state), style = AnkyType.Body.copy(fontSize = 14.sp, color = AnkyColors.PaperMuted))
        if (state.isEncryptedBackupEnabled) {
            AnkyActionButton(if (state.isEncryptedBackupWorking) stringResource(R.string.backing_up) else stringResource(R.string.back_up_now), enabled = !state.isEncryptedBackupWorking, onClick = onEncryptedBackupNow)
        }
        AnkyActionButton(stringResource(R.string.you_restore_encrypted_backup), enabled = !state.isEncryptedBackupWorking, onClick = onRestoreEncryptedBackup)
    }
    AnkyPanel {
        AnkyActionButton(stringResource(R.string.export_backup_zip), onClick = onExport)
        when (exportBackupAction(state)) {
            ExportBackupAction.Share -> AnkyActionButton(stringResource(R.string.share_backup_zip), onClick = onShareBackup)
            ExportBackupAction.Empty -> DisabledRow(stringResource(R.string.no_local_data_to_back_up_yet))
        }
        AnkyActionButton(stringResource(R.string.restore_backup), onClick = onRestore)
    }
    YouDangerPanel {
        Text(stringResource(R.string.danger_zone), style = AnkyType.Heading.copy(fontSize = 18.sp, color = AnkyColors.Danger))
        Text(stringResource(R.string.you_delete_local_data_body), style = AnkyType.Body.copy(fontSize = 14.sp, color = AnkyColors.PaperMuted))
        AnkyActionButton(stringResource(R.string.delete_local_data), destructive = true, onClick = onDeleteLocalData)
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
    onSupportFeedback: () -> Unit,
) {
    AnkyPanel {
        Text(
            state.creditDetailTitle,
            style = AnkyType.Title.copy(
                fontSize = 62.sp,
                shadow = Shadow(color = AnkyColors.Gold.copy(alpha = 0.35f), blurRadius = 18f),
            ),
            modifier = Modifier.fillMaxWidth(),
            textAlign = TextAlign.Center,
        )
        Text(state.creditDetailCaption, style = AnkyType.Caption, modifier = Modifier.fillMaxWidth(), textAlign = TextAlign.Center)
    }
    AnkyPanel {
        Rule(stringResource(R.string.credit_rule_one_reflection))
        Rule(stringResource(R.string.credit_rule_ask_spends))
        Rule(stringResource(R.string.credit_rule_writing_free))
    }
    AnkyPanel {
        when {
            state.hasUnspentGiftCredit -> {
                DisabledRow(YouStatusCopy.CreditPacksLocked)
                Text(YouStatusCopy.CreditGiftDetail, style = AnkyType.Body.copy(fontSize = 14.sp, color = AnkyColors.PaperMuted))
            }
            state.creditState.isLoading && state.creditState.packages.isEmpty() -> DisabledRow(stringResource(R.string.loading_credit_packs))
            state.creditState.packages.isEmpty() -> DisabledRow(stringResource(R.string.no_credit_packs_available))
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
        AnkyActionButton(stringResource(R.string.refresh_credits), onClick = onRefresh)
        AnkyActionButton(
            if (state.isRestoringPurchases) stringResource(R.string.restoring_purchases) else stringResource(R.string.restore_purchases),
            enabled = !state.isRestoringPurchases,
            onClick = onRestorePurchases,
        )
        Text(CreditCatalog.RestoreIdentityNote, style = AnkyType.Body.copy(fontSize = 14.sp, color = AnkyColors.PaperMuted))
    }
    AnkyPanel {
        AnkyActionButton(stringResource(R.string.support_feedback_lower), onClick = onSupportFeedback)
        Text(stringResource(R.string.support_feedback_note), style = AnkyType.Body.copy(fontSize = 14.sp, color = AnkyColors.PaperMuted))
    }
}

@Composable
private fun YouReflectionCreditsSheet(
    state: YouState,
    onRefresh: () -> Unit,
    onPurchase: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(modifier = modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(18.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Icon(
                imageVector = Icons.Filled.AutoAwesome,
                contentDescription = null,
                tint = AnkyColors.Gold,
                modifier = Modifier.size(28.dp),
            )
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(
                    stringResource(R.string.credits_sheet_title),
                    style = AnkyType.Heading.copy(fontSize = 29.sp, fontWeight = FontWeight.Medium),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                Text(
                    stringResource(R.string.credits_sheet_subtitle),
                    style = AnkyType.Body.copy(fontSize = 15.sp, color = AnkyColors.Paper.copy(alpha = 0.68f)),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
            Box(
                modifier = Modifier
                    .size(46.dp)
                    .clip(CircleShape)
                    .background(AnkyColors.Violet.copy(alpha = 0.20f))
                    .border(1.2.dp, AnkyColors.Gold.copy(alpha = 0.42f), CircleShape)
                    .clickable(
                        enabled = !state.creditState.isLoading,
                        onClickLabel = stringResource(R.string.refresh_reflection_credits),
                        onClick = onRefresh,
                    ),
                contentAlignment = Alignment.Center,
            ) {
                if (state.creditState.isLoading) {
                    CircularProgressIndicator(
                        color = AnkyColors.Gold,
                        strokeWidth = 2.dp,
                        modifier = Modifier.size(22.dp),
                    )
                } else {
                    Icon(
                        imageVector = Icons.Filled.Refresh,
                        contentDescription = stringResource(R.string.refresh_reflection_credits),
                        tint = AnkyColors.Gold,
                        modifier = Modifier.size(22.dp),
                    )
                }
            }
        }

        YouCreditBalancePanel(state.presentedCreditBalance)

        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            when {
                state.creditState.isLoading && state.creditState.packages.isEmpty() -> YouCreditDisabledRow(stringResource(R.string.loading_credit_packs))
                state.creditState.packages.isEmpty() -> YouCreditDisabledRow(stringResource(R.string.no_credit_packs_available))
                else -> {
                    state.creditState.packages.take(3).forEach { creditPackage ->
                        YouCreditPackageRow(
                            creditPackage = creditPackage,
                            isRecommended = creditPackage.title == "11 reflections" ||
                                creditPackage.packageId.endsWith(".credits.11"),
                            isPurchasing = state.purchasingCreditPackageId == creditPackage.packageId,
                            onPurchase = onPurchase,
                        )
                    }
                }
            }
        }

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.Center,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(Icons.Filled.AutoAwesome, contentDescription = null, tint = AnkyColors.Gold.copy(alpha = 0.78f), modifier = Modifier.size(13.dp))
            Text(
                stringResource(R.string.writing_is_free_one_credit_reflection),
                style = AnkyType.Body.copy(fontSize = 15.sp, fontWeight = FontWeight.Medium, color = AnkyColors.Paper.copy(alpha = 0.68f)),
                modifier = Modifier.padding(horizontal = 10.dp),
                textAlign = TextAlign.Center,
            )
            Icon(Icons.Filled.AutoAwesome, contentDescription = null, tint = AnkyColors.Gold.copy(alpha = 0.78f), modifier = Modifier.size(13.dp))
        }
        Text(
            stringResource(R.string.credits_sheet_prompt_copy_fallback),
            style = AnkyType.Body.copy(fontSize = 14.sp, fontWeight = FontWeight.Medium, color = AnkyColors.Paper.copy(alpha = 0.58f)),
            modifier = Modifier.fillMaxWidth(),
            textAlign = TextAlign.Center,
        )

        state.error?.let { error ->
            Text(
                error.lowercase(),
                style = AnkyType.Mono.copy(fontSize = 12.sp, color = AnkyColors.Danger.copy(alpha = 0.82f)),
            )
        }
    }
}

@Composable
private fun YouCreditBalancePanel(balance: Int?) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(124.dp)
            .clip(RoundedCornerShape(18.dp))
            .background(Color.Black.copy(alpha = 0.58f))
            .border(1.dp, AnkyColors.Gold.copy(alpha = 0.34f), RoundedCornerShape(18.dp)),
        contentAlignment = Alignment.CenterStart,
    ) {
        Image(
            painter = painterResource(R.drawable.credits_thread_background),
            contentDescription = null,
            contentScale = ContentScale.Crop,
            modifier = Modifier.fillMaxSize(),
        )
        Box(
            Modifier
                .fillMaxSize()
                .background(
                    Brush.horizontalGradient(
                        listOf(
                            AnkyColors.Ink.copy(alpha = 0.90f),
                            AnkyColors.Ink.copy(alpha = 0.38f),
                            Color.Transparent,
                        ),
                    ),
                ),
        )
        Row(
            modifier = Modifier.padding(horizontal = 26.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(22.dp),
        ) {
            Text(
                balance?.toString() ?: "...",
                style = AnkyType.Title.copy(
                    fontSize = 68.sp,
                    fontWeight = FontWeight.Bold,
                    shadow = Shadow(color = AnkyColors.Gold.copy(alpha = 0.35f), blurRadius = 14f),
                ),
            )
            Text(
                stringResource(R.string.available_credits),
                style = AnkyType.Heading.copy(fontSize = 23.sp, fontWeight = FontWeight.Medium, color = AnkyColors.Paper.copy(alpha = 0.78f)),
                lineHeight = 28.sp,
            )
        }
    }
}

@Composable
private fun YouCreditPackageRow(
    creditPackage: CreditPackage,
    isRecommended: Boolean,
    isPurchasing: Boolean,
    onPurchase: (String) -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .height(86.dp)
            .clip(RoundedCornerShape(16.dp))
            .background(
                Brush.linearGradient(
                    listOf(
                        Color(0xFF150B20).copy(alpha = 0.95f),
                        Color(0xFF07050D).copy(alpha = 0.98f),
                    ),
                ),
            )
            .border(
                if (isRecommended) 1.5.dp else 1.dp,
                AnkyColors.Gold.copy(alpha = if (isRecommended) 0.52f else 0.28f),
                RoundedCornerShape(16.dp),
            )
            .clickable(enabled = !isPurchasing) { onPurchase(creditPackage.packageId) }
            .padding(horizontal = 16.dp),
        horizontalArrangement = Arrangement.spacedBy(14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            Modifier
                .size(48.dp)
                .clip(CircleShape)
                .background(AnkyColors.Gold.copy(alpha = 0.16f))
                .border(1.dp, AnkyColors.Gold.copy(alpha = 0.24f), CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            Icon(Icons.Filled.AutoAwesome, contentDescription = null, tint = AnkyColors.Gold, modifier = Modifier.size(18.dp))
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(
                creditPackage.title,
                style = AnkyType.Heading.copy(fontSize = 25.sp, fontWeight = FontWeight.SemiBold),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                creditPackage.subtitle,
                style = AnkyType.Body.copy(fontSize = 16.sp, fontWeight = FontWeight.Medium, color = AnkyColors.Paper.copy(alpha = 0.58f)),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
        Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(8.dp)) {
            if (isRecommended && !isPurchasing) {
                Text(
                    stringResource(R.string.best_value),
                    style = AnkyType.Mono.copy(fontSize = 12.sp, fontWeight = FontWeight.Bold, color = AnkyColors.Ink),
                    modifier = Modifier
                        .clip(RoundedCornerShape(999.dp))
                        .background(AnkyColors.Gold)
                        .padding(horizontal = 10.dp, vertical = 5.dp),
                )
            }
            Text(
                if (isPurchasing) "..." else creditPackage.price,
                style = AnkyType.Heading.copy(fontSize = 23.sp, fontWeight = FontWeight.SemiBold, color = AnkyColors.Gold),
                maxLines = 1,
            )
        }
    }
}

@Composable
private fun YouCreditDisabledRow(text: String) {
    Text(
        text,
        style = AnkyType.Body.copy(fontSize = 15.sp, fontWeight = FontWeight.Medium, color = AnkyColors.Paper.copy(alpha = 0.58f)),
        modifier = Modifier
            .fillMaxWidth()
            .height(68.dp)
            .clip(RoundedCornerShape(16.dp))
            .background(Color.Black.copy(alpha = 0.14f))
            .border(1.dp, AnkyColors.Gold.copy(alpha = 0.22f), RoundedCornerShape(16.dp))
            .padding(horizontal = 18.dp, vertical = 22.dp),
    )
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

private fun canUseDeviceLock(context: Context): Boolean =
    BiometricManager.from(context).canAuthenticate(
        BiometricManager.Authenticators.BIOMETRIC_WEAK or
            BiometricManager.Authenticators.DEVICE_CREDENTIAL,
    ) == BiometricManager.BIOMETRIC_SUCCESS

@Composable
private fun deviceLockControlTitle(context: Context): String =
    when (biometricLockLabel(context)) {
        "fingerprint" -> stringResource(R.string.fingerprint)
        "face" -> stringResource(R.string.face_unlock)
        "iris" -> stringResource(R.string.iris)
        "biometric" -> stringResource(R.string.biometric_lock)
        else -> stringResource(R.string.device_lock)
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
        is ArticleItem.Callout -> AnkyPanel {
            MarkdownArticleText(item.text)
        }
        is ArticleItem.Heading -> Text(item.text, style = AnkyType.Heading.copy(fontSize = 21.sp), modifier = Modifier.padding(top = 4.dp))
        is ArticleItem.Paragraph -> MarkdownArticleText(item.text)
        is ArticleItem.Bullets -> Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            item.items.forEach { Rule(it) }
        }
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
    data class Callout(val text: String) : ArticleItem
    data class Heading(val text: String) : ArticleItem
    data class Paragraph(val text: String) : ArticleItem
    data class Bullets(val items: List<String>) : ArticleItem
}

private val PrivacyCopy = listOf(
    ArticleItem.Caption("last updated: 2026-05-14"),
    ArticleItem.Paragraph("anky is a local-first writing app. the core artifact is the `.anky` file on your device. the app should let you write, save, revisit, export, import, and delete your writing without making a server the owner of your interior life."),
    ArticleItem.Heading("the private artifact"),
    ArticleItem.Paragraph("your `.anky` writing is stored on your device by default. a saved `.anky` file contains the accepted writing stream and timing data for a session."),
    ArticleItem.Paragraph("anky computes a SHA-256 hash of the exact `.anky` bytes. the hash is for integrity. it is not encryption. if someone has the same `.anky` bytes, they can compute the same hash."),
    ArticleItem.Paragraph("the source is direct: [local archive](https://github.com/jpfraneto/anky-seed/blob/main/apps/android/app/src/main/java/inc/anky/android/core/storage/LocalAnkyArchive.kt), [protocol](https://github.com/jpfraneto/anky-seed/tree/main/apps/android/app/src/main/java/inc/anky/android/core/protocol)."),
    ArticleItem.Heading("local identity"),
    ArticleItem.Paragraph("anky creates a local Base account, stores its recovery phrase in device secure storage, and derives the Anky address locally. the recovery phrase is not sent to anky."),
    ArticleItem.Paragraph("the relevant code is [writer identity](https://github.com/jpfraneto/anky-seed/blob/main/apps/android/app/src/main/java/inc/anky/android/core/identity/WriterIdentityStore.kt) and [android keystore storage](https://github.com/jpfraneto/anky-seed/blob/main/apps/android/app/src/main/java/inc/anky/android/core/identity/WriterIdentityStore.kt)."),
    ArticleItem.Heading("when plaintext leaves"),
    ArticleItem.Paragraph("writing, saving, hashing, reading the map, and keeping local backups do not require plaintext to leave your device."),
    ArticleItem.Paragraph("plaintext can leave when you choose an action that sends it somewhere: asking anky for a reflection, exporting or sharing files, importing a backup from a place you chose, or contacting support with text you provide."),
    ArticleItem.Paragraph("the processing and backup paths are [reflection client](https://github.com/jpfraneto/anky-seed/blob/main/apps/android/app/src/main/java/inc/anky/android/core/mirror/MirrorClient.kt), [backup importer](https://github.com/jpfraneto/anky-seed/blob/main/apps/android/app/src/main/java/inc/anky/android/core/storage/BackupImporter.kt), and [you page model](https://github.com/jpfraneto/anky-seed/blob/main/apps/android/app/src/main/java/inc/anky/android/feature/you/YouViewModel.kt)."),
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

private val TermsCopy = listOf(
    ArticleItem.Caption("Anky, Inc. - Effective June 7, 2026"),
    ArticleItem.Callout("Important: Anky is a writing and reflection app. It is not therapy, medical care, crisis support, financial advice, legal advice, or spiritual authority. By using Anky, you agree that you remain responsible for your writing, your decisions, your device, your recovery phrase, your purchases, and how you use AI-generated reflections."),
    ArticleItem.Heading("1. Acceptance"),
    ArticleItem.Paragraph("These Terms and Conditions are an agreement between you and **Anky, Inc.**, a Delaware corporation."),
    ArticleItem.Paragraph("By downloading, accessing, or using Anky, you agree to these Terms."),
    ArticleItem.Paragraph("If you do not agree, do not use Anky."),
    ArticleItem.Heading("2. What Anky Provides"),
    ArticleItem.Paragraph("Anky lets you:"),
    ArticleItem.Bullets(
        listOf(
            "Write forward-only `.anky` sessions",
            "Save writing locally",
            "Revisit local writing history",
            "Export or import writing files",
            "Manage a local Anky identity",
            "Buy or use reflection credits",
            "Ask Anky for AI-generated reflections",
            "Use related features we provide over time",
        ),
    ),
    ArticleItem.Paragraph("We may change, suspend, or discontinue any part of Anky at any time."),
    ArticleItem.Heading("3. Age Requirement"),
    ArticleItem.Paragraph("Anky is not intended for children under 13."),
    ArticleItem.Paragraph("If you are under 18, you may use Anky only with permission from a parent or guardian."),
    ArticleItem.Paragraph("By using Anky, you represent that you meet these requirements."),
    ArticleItem.Heading("4. Anky Is Not Professional Advice"),
    ArticleItem.Paragraph("Anky is not a therapist, doctor, emergency service, financial advisor, legal advisor, religious authority, or spiritual authority."),
    ArticleItem.Paragraph("AI-generated reflections are for personal writing reflection only."),
    ArticleItem.Paragraph("They may be inaccurate, incomplete, unexpected, emotionally intense, or not useful."),
    ArticleItem.Paragraph("Do not rely on Anky for medical, mental health, legal, financial, emergency, or safety decisions."),
    ArticleItem.Paragraph("If you may hurt yourself or someone else, or if you are in immediate danger, contact local emergency services or a trusted person immediately."),
    ArticleItem.Heading("5. Your Writing"),
    ArticleItem.Paragraph("You own your writing."),
    ArticleItem.Paragraph("By using Anky, you give Anky, Inc. a limited permission to process your writing only as needed to provide the features you choose, such as saving locally, generating a reflection, exporting, importing, backing up, debugging, support, security, and abuse prevention."),
    ArticleItem.Paragraph("You are responsible for what you write, export, send, share, or back up."),
    ArticleItem.Paragraph("Do not write, upload, export, or share content through Anky in a way that violates the law or harms others."),
    ArticleItem.Heading("6. Local-First Design"),
    ArticleItem.Paragraph("Anky is designed to be local-first."),
    ArticleItem.Paragraph("Your writing normally stays on your device."),
    ArticleItem.Paragraph("When you ask for a reflection, you understand that your `.anky` writing is sent to Anky's mirror service and AI service providers to generate the reflection."),
    ArticleItem.Paragraph("When you export, share, back up, or contact support, you are choosing to send or store data outside the app."),
    ArticleItem.Heading("7. Local Identity and Recovery Phrase"),
    ArticleItem.Paragraph("Anky may create a local account/identity for your device."),
    ArticleItem.Paragraph("You are responsible for protecting your recovery phrase, private key, device passcode, biometric access, account backups, and exported files."),
    ArticleItem.Paragraph("Never share your recovery phrase."),
    ArticleItem.Paragraph("If you lose your recovery phrase, Anky may not be able to recover your identity, credits, account state, or related data."),
    ArticleItem.Paragraph("Anky is not responsible for losses caused by lost recovery phrases, compromised devices, shared credentials, or unauthorized access to your device or accounts."),
    ArticleItem.Heading("8. Purchases, Credits, and Refunds"),
    ArticleItem.Paragraph("Writing in Anky is free."),
    ArticleItem.Paragraph("Reflections may require credits."),
    ArticleItem.Paragraph("Credits are digital app credits used only inside Anky for reflection requests. Credits are not money, not cryptocurrency, not stored value, not withdrawable, not redeemable for cash, and not transferable unless we explicitly say otherwise."),
    ArticleItem.Paragraph("Purchases are processed through Google Play and may be managed by RevenueCat."),
    ArticleItem.Paragraph("We do not handle or store your full payment card details."),
    ArticleItem.Paragraph("Refunds are handled by Google Play according to Google's policies."),
    ArticleItem.Paragraph("We may change pricing, credit packs, free trials, or credit rules at any time, subject to applicable law and Google Play rules."),
    ArticleItem.Heading("9. AI-Generated Reflections"),
    ArticleItem.Paragraph("AI-generated reflections are produced automatically."),
    ArticleItem.Paragraph("You understand that reflections may:"),
    ArticleItem.Bullets(
        listOf(
            "Be wrong",
            "Miss important context",
            "Sound more certain than they are",
            "Be emotionally uncomfortable",
            "Fail to understand your language, tone, or intent",
            "Contain unexpected content",
            "Be unavailable because of technical errors",
        ),
    ),
    ArticleItem.Paragraph("You remain responsible for interpreting and using any reflection."),
    ArticleItem.Paragraph("Anky, Inc. is not responsible for decisions you make based on AI-generated content."),
    ArticleItem.Heading("10. Blockchain and Token References"),
    ArticleItem.Paragraph("Anky may display blockchain addresses, token references, contract addresses, or related information."),
    ArticleItem.Paragraph("These references are informational only."),
    ArticleItem.Paragraph("Nothing in Anky is financial advice, investment advice, tax advice, legal advice, or an offer to buy or sell any token, security, or asset."),
    ArticleItem.Paragraph("Using Anky does not require buying, holding, or trading any token."),
    ArticleItem.Paragraph("Blockchain transactions may be public, irreversible, volatile, risky, and outside Anky's control."),
    ArticleItem.Paragraph("You are responsible for your own wallets, keys, transactions, taxes, and financial decisions."),
    ArticleItem.Heading("11. User Conduct"),
    ArticleItem.Paragraph("You agree not to:"),
    ArticleItem.Bullets(
        listOf(
            "Use Anky if you do not meet the age requirements",
            "Use Anky for illegal activity",
            "Abuse, attack, disrupt, or overload Anky's systems",
            "Circumvent credits, paywalls, trials, signatures, app attestation, or security controls",
            "Reverse engineer, scrape, extract, or publish Anky's private prompts, model instructions, keys, or backend systems",
            "Use bots, scripts, or automation to abuse the app",
            "Attempt to access another person's data, identity, recovery phrase, or account",
            "Upload or share content that violates another person's rights",
            "Use Anky to generate instructions for harming yourself or others",
            "Misrepresent Anky, Anky, Inc., or any affiliation with us",
        ),
    ),
    ArticleItem.Paragraph("We may suspend, restrict, or terminate access if we believe you violated these Terms, abused the service, created risk, or used Anky unlawfully."),
    ArticleItem.Heading("12. Intellectual Property"),
    ArticleItem.Paragraph("Anky, Inc. owns Anky's software, design, name, logos, characters, visual assets, prompts, product concepts, documentation, and related intellectual property."),
    ArticleItem.Paragraph("You may not copy, modify, distribute, sell, reverse engineer, or create derivative works from Anky except where allowed by law or by an open-source license we explicitly provide."),
    ArticleItem.Paragraph("You retain ownership of your own writing."),
    ArticleItem.Heading("13. Feedback"),
    ArticleItem.Paragraph("If you send us feedback, ideas, suggestions, bug reports, or feature requests, you give Anky, Inc. permission to use them without restriction or compensation."),
    ArticleItem.Paragraph("This does not give us ownership of your private writing."),
    ArticleItem.Heading("14. Third-Party Services"),
    ArticleItem.Paragraph("Anky depends on third-party services, which may include Google, RevenueCat, OpenRouter, AI model providers, cloud hosting providers, email providers, and blockchain networks."),
    ArticleItem.Paragraph("We are not responsible for third-party services, terms, outages, policies, prices, decisions, or data practices."),
    ArticleItem.Paragraph("Your use of third-party services may be subject to their terms and privacy policies."),
    ArticleItem.Heading("15. App Store Terms"),
    ArticleItem.Paragraph("If you downloaded Anky from Google Play, Google's terms also apply."),
    ArticleItem.Paragraph("Google is not responsible for Anky, its content, support, warranties, or claims, except as required by applicable law or Google's own terms."),
    ArticleItem.Heading("16. Availability"),
    ArticleItem.Paragraph("Anky may be unavailable, delayed, interrupted, inaccurate, or discontinued."),
    ArticleItem.Paragraph("We do not guarantee that Anky will always work, that reflections will always be available, that credits will always sync instantly, or that local data will never be lost."),
    ArticleItem.Paragraph("Back up anything important."),
    ArticleItem.Heading("17. Termination"),
    ArticleItem.Paragraph("You may stop using Anky at any time."),
    ArticleItem.Paragraph("You can delete the app and delete local data where the app provides deletion tools."),
    ArticleItem.Paragraph("We may suspend, limit, or terminate your access to Anky at any time if we believe it is necessary to protect Anky, users, third parties, or the integrity of the service."),
    ArticleItem.Heading("18. Disclaimer of Warranties"),
    ArticleItem.Paragraph("ANKY IS PROVIDED \"AS IS\" AND \"AS AVAILABLE.\""),
    ArticleItem.Paragraph("TO THE FULLEST EXTENT PERMITTED BY LAW, ANKY, INC. DISCLAIMS ALL WARRANTIES, EXPRESS OR IMPLIED, INCLUDING WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, TITLE, NON-INFRINGEMENT, ACCURACY, AVAILABILITY, SECURITY, AND RELIABILITY."),
    ArticleItem.Paragraph("YOUR USE OF ANKY IS AT YOUR OWN RISK."),
    ArticleItem.Heading("19. Limitation of Liability"),
    ArticleItem.Paragraph("TO THE FULLEST EXTENT PERMITTED BY LAW, ANKY, INC. AND ITS OWNERS, DIRECTORS, OFFICERS, EMPLOYEES, CONTRACTORS, SERVICE PROVIDERS, AND AFFILIATES WILL NOT BE LIABLE FOR INDIRECT, INCIDENTAL, SPECIAL, CONSEQUENTIAL, EXEMPLARY, OR PUNITIVE DAMAGES, OR FOR LOST PROFITS, LOST DATA, LOST WRITING, LOST CREDITS, LOST TOKENS, LOST KEYS, DEVICE COMPROMISE, EMOTIONAL DISTRESS, OR DECISIONS MADE BASED ON AI-GENERATED CONTENT."),
    ArticleItem.Paragraph("TO THE FULLEST EXTENT PERMITTED BY LAW, ANKY, INC.'S TOTAL LIABILITY FOR ANY CLAIM WILL NOT EXCEED THE GREATER OF:"),
    ArticleItem.Paragraph("(A) THE AMOUNT YOU PAID TO ANKY, INC. THROUGH THE APP IN THE 12 MONTHS BEFORE THE CLAIM, OR"),
    ArticleItem.Paragraph("(B) $50 USD."),
    ArticleItem.Paragraph("Some jurisdictions do not allow certain limitations, so some of these limits may not apply to you."),
    ArticleItem.Heading("20. Indemnification"),
    ArticleItem.Paragraph("You agree to defend, indemnify, and hold harmless Anky, Inc. and its owners, directors, officers, employees, contractors, service providers, and affiliates from claims, damages, losses, liabilities, costs, and expenses arising from:"),
    ArticleItem.Bullets(
        listOf(
            "Your use of Anky",
            "Your writing or exported content",
            "Your violation of these Terms",
            "Your violation of law",
            "Your violation of another person's rights",
            "Your misuse of AI-generated reflections",
            "Your blockchain, wallet, token, or recovery phrase activity",
        ),
    ),
    ArticleItem.Heading("21. Governing Law"),
    ArticleItem.Paragraph("These Terms are governed by the laws of the State of Delaware, without regard to conflict-of-law principles, except where your local law requires otherwise."),
    ArticleItem.Heading("22. Disputes and Arbitration"),
    ArticleItem.Paragraph("To the fullest extent permitted by law, disputes between you and Anky, Inc. will be resolved through binding individual arbitration, not in a class action or jury trial."),
    ArticleItem.Paragraph("You and Anky, Inc. agree to bring claims only on an individual basis."),
    ArticleItem.Paragraph("This section does not prevent either party from seeking relief in small claims court or seeking injunctive relief for intellectual property, security, or unauthorized access issues."),
    ArticleItem.Paragraph("If this arbitration section is not enforceable where you live, the rest of these Terms still apply."),
    ArticleItem.Heading("23. Changes"),
    ArticleItem.Paragraph("We may update these Terms from time to time."),
    ArticleItem.Paragraph("When we do, we will update the effective date. Continued use of Anky after changes means you accept the updated Terms."),
    ArticleItem.Heading("24. Contact"),
    ArticleItem.Paragraph("**Anky, Inc.**"),
    ArticleItem.Paragraph("Contact: **[support@anky.app](mailto:support@anky.app)**"),
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

internal fun formattedWritingExportAction(state: YouState): FormattedWritingExportAction =
    if (state.formattedWritingExportFile != null) FormattedWritingExportAction.Share else FormattedWritingExportAction.Empty

internal enum class FormattedWritingExportAction {
    Share,
    Empty,
}

private enum class YouPage(@StringRes val titleRes: Int, @StringRes val subtitleRes: Int) {
    Account(R.string.you_private_access, R.string.you_writing_access_stays),
    Privacy(R.string.you_privacy_policy, R.string.you_privacy_subtitle),
    Terms(R.string.you_terms_conditions, R.string.you_terms_subtitle),
    Export(R.string.you_export_data, R.string.you_archive_yours),
    History(R.string.you_history_title, R.string.you_history_subtitle),
    Credits(R.string.you_credits, R.string.you_reflection_balance),
    Token(R.string.you_token_title, R.string.you_token_subtitle),
    Developer(R.string.you_developer_title, R.string.you_developer_subtitle),
}

private fun YouInitialPage.toYouPage(): YouPage =
    when (this) {
        YouInitialPage.Credits -> YouPage.Credits
    }

private enum class YouPrompt(val message: String) {
    Identity("your identity can be saved to secure storage."),
    Privacy("Writing stays local unless you export or ask for a reflection."),
    Export("Your archive is yours. Export readable writings or keep a local backup."),
    Credits("Credits are only for reflections. Writing is free."),
    Support("Send us an email! We want to evolve this app based on your feedback."),
    Developer("Local tools. Repair first, delete only when you mean it."),
}

private fun youConversationMessage(
    state: YouState,
    activePrompt: YouPrompt?,
    isShowingSystemPrompt: Boolean,
): String =
    if (isShowingSystemPrompt) {
        state.error ?: state.statusMessage ?: activePrompt?.message.orEmpty()
    } else if (activePrompt == YouPrompt.Credits) {
        val purchasingPackage = state.purchasingCreditPackageId
            ?.let { packageId -> state.creditState.packages.firstOrNull { it.packageId == packageId } }
        when {
            purchasingPackage != null -> "anky is opening the ${purchasingPackage.title.lowercase()} pack."
            state.creditState.isLoading -> "anky is checking the credit gate."
            else -> creditsPromptMessage(state)
        }
    } else if (activePrompt == YouPrompt.Export) {
        if (state.isEncryptedBackupWorking) {
            "Anky is updating the encrypted backup."
        } else {
            encryptedBackupDetail(state)
        }
    } else {
        activePrompt?.message.orEmpty()
    }

private fun isConversationThinking(activePrompt: YouPrompt?, state: YouState): Boolean =
    (activePrompt == YouPrompt.Credits &&
        (state.creditState.isLoading || state.purchasingCreditPackageId != null)) ||
        (activePrompt == YouPrompt.Export && state.isEncryptedBackupWorking)

private fun encryptedBackupDetail(state: YouState): String {
    if (state.isEncryptedBackupEnabled) {
        val lastBackup = state.encryptedBackupLastDate
        return if (lastBackup != null) {
            "Encrypted backup is on. Last updated ${lastBackup.formattedForYouBackup()}."
        } else {
            YouStatusCopy.EncryptedBackupOnAfterNextWriting
        }
    }
    return "Export readable writings or turn on encrypted backup for reinstall recovery."
}

private fun Instant.formattedForYouBackup(): String =
    DateTimeFormatter
        .ofLocalizedDateTime(FormatStyle.MEDIUM, FormatStyle.SHORT)
        .withLocale(Locale.getDefault())
        .withZone(ZoneId.systemDefault())
        .format(this)

private fun creditsMenuSubtitle(
    state: YouState,
    loadingBalance: String = "Loading balance",
    reflectionBalance: String = "Reflection balance",
    creditSingular: String = "credit",
    creditPlural: String = "credits",
): String =
    when {
        state.hasUnspentGiftCredit -> YouStatusCopy.CreditGiftSummary
        state.creditState.isLoading && state.creditState.balance == null -> loadingBalance
        state.creditState.balance != null -> "${state.creditState.balance} ${if (state.creditState.balance == 1) creditSingular else creditPlural}"
        else -> reflectionBalance
    }

private fun creditsPromptMessage(state: YouState): String {
    if (state.hasUnspentGiftCredit) return YouStatusCopy.CreditGiftPrompt

    val balance = when {
        state.creditState.isLoading && state.creditState.balance == null -> "loading..."
        state.creditState.balance != null -> state.creditState.balance.toString()
        else -> "unknown"
    }
    return "you have $balance reflection ${if (balance == "1") "credit" else "credits"}. choose a pack to add more."
}

private fun ankyContractDisplayAddress(): String {
    val address = PrivacyMessages.AnkyCoinContractAddress
    return "${address.take(5)}...${address.takeLast(5)}"
}

private data class YouPromptActionLabels(
    val backUpRecoveryWords: String,
    val backingUp: String,
    val backUpNow: String,
    val exportWritings: String,
    val copyAccount: String,
    val ankyAddress: String,
    val deleteLocalData: String,
    val openEmail: String,
    val backupRecoveryWordsSecureStorageReason: String,
    val enableEncryptedBackupReason: String,
    val couldNotConfirmIdentity: String,
)

private fun youPromptActions(
    prompt: YouPrompt?,
    state: YouState,
    context: Context,
    viewModel: YouViewModel,
    labels: YouPromptActionLabels,
    page: (YouPage) -> Unit,
    confirmDeleteLocalData: () -> Unit,
): List<AnkyChatAction> =
    when (prompt) {
        YouPrompt.Identity -> listOf(
            AnkyChatAction(labels.backUpRecoveryWords, isPrimary = true) {
                viewModel.backUpIdentityToDeviceSecureStorage(
                    labels.backupRecoveryWordsSecureStorageReason,
                    labels.couldNotConfirmIdentity,
                )
            },
            AnkyChatAction(labels.copyAccount) { context.copyText(labels.ankyAddress, state.accountId) },
        )
        YouPrompt.Privacy -> emptyList()
        YouPrompt.Export -> buildList {
            add(
                AnkyChatAction(if (state.isEncryptedBackupWorking) labels.backingUp else labels.backUpNow, isPrimary = true) {
                    if (state.isEncryptedBackupEnabled) {
                        viewModel.backUpEncryptedNow()
                    } else {
                        viewModel.enableEncryptedBackup(
                            labels.enableEncryptedBackupReason,
                            labels.couldNotConfirmIdentity,
                        )
                    }
                },
            )
            add(
                AnkyChatAction(labels.exportWritings) {
                    viewModel.prepareFormattedWritingExport()
                    state.formattedWritingExportFile?.let { file ->
                        context.shareFile(file, "text/markdown", labels.exportWritings)
                    }
                },
            )
        }
        YouPrompt.Credits -> {
            val packages = state.creditState.packages.take(3)
            if (state.hasUnspentGiftCredit) {
                emptyList()
            } else if (packages.isEmpty()) {
                listOf(
                    AnkyChatAction(if (state.creditState.isLoading) "loading packs" else "refresh credits", isPrimary = true) {
                        viewModel.refreshCredits()
                    },
                )
            } else {
                packages.map { creditPackage ->
                    val isRecommended = creditPackage.title == "11 reflections" ||
                        creditPackage.packageId.endsWith(".credits.11")
                    AnkyChatAction(
                        title = creditPackage.title,
                        isPrimary = isRecommended,
                        subtitle = creditPackage.price,
                        badge = if (isRecommended) "recommended" else null,
                    ) {
                        viewModel.purchaseCredits(creditPackage.packageId, context.findActivity())
                    }
                }
            }
        }
        YouPrompt.Support -> listOf(
            AnkyChatAction(labels.openEmail, isPrimary = true) { context.openUrl(state.supportFeedbackEmailUrl) },
        )
        YouPrompt.Developer -> if (BuildConfig.DEBUG) {
            listOf(
                AnkyChatAction("repair map", isPrimary = true) { viewModel.rebuildSessionIndex() },
                AnkyChatAction(labels.deleteLocalData) { confirmDeleteLocalData() },
            )
        } else {
            emptyList()
        }
        null -> emptyList()
    }

private fun Context.copyText(label: String, text: String) {
    val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
    clipboard.setPrimaryClip(ClipData.newPlainText(label, text))
}

private fun Context.openUrl(url: String) {
    startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
}

private fun Context.shareFile(file: File, mimeType: String, chooserTitle: String) {
    val uri = FileProvider.getUriForFile(this, "${BuildConfig.APPLICATION_ID}.fileprovider", file)
    val intent = Intent(Intent.ACTION_SEND)
        .setType(mimeType)
        .putExtra(Intent.EXTRA_STREAM, uri)
        .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    startActivity(Intent.createChooser(intent, chooserTitle))
}

private tailrec fun Context.findActivity(): Activity? =
    when (this) {
        is Activity -> this
        is ContextWrapper -> baseContext.findActivity()
        else -> null
    }

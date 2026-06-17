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
import androidx.compose.ui.zIndex
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
    val contractAddressClipboardLabel = stringResource(R.string.contract_address_clipboard_label)
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
                        if (hasCanonicalAnkyContractAddress()) {
                            context.copyText(contractAddressClipboardLabel, PrivacyMessages.AnkyCoinContractAddress)
                            didCopyAnkyContract.value = true
                        }
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
                                    repairMapIndex = stringResource(R.string.repair_map_index),
                                    deleteLocalData = stringResource(R.string.delete_local_data),
                                    openEmail = stringResource(R.string.open_email),
                                    loadingCreditPacks = stringResource(R.string.loading_credit_packs),
                                    refreshCredits = stringResource(R.string.refresh_credits),
                                    bestValue = stringResource(R.string.best_value),
                                    creditPack3Title = stringResource(R.string.credit_pack_3_title),
                                    creditPack11Title = stringResource(R.string.credit_pack_11_title),
                                    creditPack33Title = stringResource(R.string.credit_pack_33_title),
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
                            .zIndex(220f)
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
                            onCopy = {
                                if (hasCanonicalAnkyContractAddress()) {
                                    context.copyText(contractAddressClipboardLabel, PrivacyMessages.AnkyCoinContractAddress)
                                }
                            },
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
            title = stringResource(R.string.clear_local_anky_archive_question),
            action = stringResource(R.string.clear_local_anky_archive_action),
            onDismiss = { confirmClearArchive.value = false },
            onConfirm = {
                confirmClearArchive.value = false
                viewModel.clearLocalArchive()
            },
        )
    }

    if (confirmClearReflections.value) {
        DestructiveConfirmDialog(
            title = stringResource(R.string.clear_local_reflections_question),
            action = stringResource(R.string.clear_local_reflections_action),
            onDismiss = { confirmClearReflections.value = false },
            onConfirm = {
                confirmClearReflections.value = false
                viewModel.clearLocalReflections()
            },
        )
    }

    if (confirmResetIdentity.value) {
        DestructiveConfirmDialog(
            title = stringResource(R.string.reset_local_identity_question),
            action = stringResource(R.string.reset_identity_action),
            message = stringResource(R.string.reset_identity_warning),
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
            TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) }
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
                    .zIndex(220f)
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
                localizedYouStatusMessage(message),
                style = AnkyType.Body.copy(fontSize = 14.sp, color = AnkyColors.Danger),
                modifier = Modifier.fillMaxWidth(),
            )
        }
    }
    state.statusMessage?.let { message ->
        AnkyPanel {
            Text(
                localizedYouStatusMessage(message),
                style = AnkyType.Body.copy(fontSize = 14.sp, color = AnkyColors.PaperMuted),
                modifier = Modifier.fillMaxWidth(),
            )
        }
    }
}

private val importedCountsRegex = Regex("""Imported (\d+) \.anky files? and (\d+) reflections?\.""")

@Composable
private fun localizedYouStatusMessage(message: String): String {
    importedCountsRegex.matchEntire(message)?.let { match ->
        return stringResource(R.string.you_status_imported_counts, match.groupValues[1], match.groupValues[2])
    }
    return when (message) {
        "Notifications are not allowed for ANKY." -> stringResource(R.string.you_status_notifications_not_allowed)
        "loading credit packs" -> stringResource(R.string.you_status_loading_credit_packs)
        "Could not complete that credit purchase." -> stringResource(R.string.you_status_could_not_complete_credit_purchase)
        "Credits updated." -> stringResource(R.string.you_status_credits_updated)
        "restoring purchases" -> stringResource(R.string.you_status_restoring_purchases)
        "Anky could not restore from encrypted backup." -> stringResource(R.string.you_status_could_not_restore_encrypted_backup)
        "Could not import that backup." -> stringResource(R.string.you_status_could_not_import_backup)
        "Could not open that backup." -> stringResource(R.string.you_status_could_not_open_backup)
        "No .anky files or reflections were found in that import." -> stringResource(R.string.you_status_no_importable_backup_data)
        "That backup could not be read." -> stringResource(R.string.you_status_backup_could_not_be_read)
        "Choose a .zip backup, .anky file, or exported reflection JSON." -> stringResource(R.string.you_status_choose_supported_backup_file)
        "That zip backup appears to be corrupt." -> stringResource(R.string.you_status_zip_backup_corrupt)
        "Encrypted zip backups are not supported." -> stringResource(R.string.you_status_encrypted_zip_not_supported)
        "That zip backup uses unsupported compression." -> stringResource(R.string.you_status_zip_unsupported_compression)
        "i couldn't find a readable .anky in that." -> stringResource(R.string.write_import_readable_error)
        "That .anky file could not be read." -> stringResource(R.string.you_status_anky_file_could_not_be_read)
        "There is no writing to back up yet." -> stringResource(R.string.you_status_no_writing_to_back_up)
        "No Anky encrypted backup was found." -> stringResource(R.string.you_status_no_encrypted_backup_found)
        "The encrypted backup could not be read." -> stringResource(R.string.you_status_encrypted_backup_could_not_be_read)
        "The encrypted backup could not be encrypted." -> stringResource(R.string.you_status_encrypted_backup_could_not_be_encrypted)
        "The encrypted backup could not be decrypted." -> stringResource(R.string.you_status_encrypted_backup_could_not_be_decrypted)
        "Could not clear local writing data." -> stringResource(R.string.you_status_could_not_clear_local_writing_data)
        "Could not rebuild the local session index." -> stringResource(R.string.you_status_could_not_rebuild_local_session_index)
        "Could not clear local reflections." -> stringResource(R.string.you_status_could_not_clear_local_reflections)
        "Could not clear local .anky files." -> stringResource(R.string.you_status_could_not_clear_local_anky_files)
        "Could not reset the local identity." -> stringResource(R.string.you_status_could_not_reset_local_identity)
        "Recovery words must be 12 words." -> stringResource(R.string.you_status_recovery_words_must_be_12)
        "Recovery words contain an unrecognized word." -> stringResource(R.string.you_status_recovery_words_unrecognized)
        "Could not recover that identity." -> stringResource(R.string.you_status_could_not_recover_identity)
        "no credit packs available" -> stringResource(R.string.you_status_no_credit_packs_available)
        "credits refreshed." -> stringResource(R.string.you_status_credits_refreshed)
        "That credit package is not available." -> stringResource(R.string.you_status_credit_package_unavailable)
        CreditCatalog.RestoreSuccessMessage -> stringResource(R.string.you_status_purchases_restored_identity)
        CreditCatalog.RestoreFailureMessage -> stringResource(R.string.you_status_could_not_restore_purchases_identity)
        YouStatusCopy.IdentityBackupSaved -> stringResource(R.string.you_status_identity_backup_saved)
        YouStatusCopy.RecoveryPhraseImported -> stringResource(R.string.you_status_identity_recovered)
        YouStatusCopy.MapIndexRepaired -> stringResource(R.string.you_status_map_index_repaired)
        YouStatusCopy.LocalReflectionsCleared -> stringResource(R.string.you_status_local_reflections_cleared)
        YouStatusCopy.LocalAnkyArchiveCleared -> stringResource(R.string.you_status_local_anky_archive_cleared)
        YouStatusCopy.LocalWritingDataCleared -> stringResource(R.string.you_status_local_writing_data_cleared)
        YouStatusCopy.LocalIdentityReset -> stringResource(R.string.you_status_local_identity_reset)
        YouStatusCopy.AccountAndDataDeleted -> stringResource(R.string.you_status_account_data_deleted)
        YouStatusCopy.CouldNotDeleteAllAccountData -> stringResource(R.string.you_status_could_not_delete_all_account_data)
        YouStatusCopy.CouldNotCreateBackupZip -> stringResource(R.string.you_status_could_not_create_backup_zip)
        YouStatusCopy.CouldNotCreateWritingExport -> stringResource(R.string.you_status_could_not_create_writing_export)
        YouStatusCopy.NoWritingToExportYet -> stringResource(R.string.you_status_no_writing_to_export_yet)
        YouStatusCopy.CouldNotLoadLocalWriterIdentity -> stringResource(R.string.you_status_could_not_load_local_writer_identity)
        YouStatusCopy.CouldNotLoadRecoveryPhrase -> stringResource(R.string.you_status_could_not_load_recovery_words)
        YouStatusCopy.CouldNotBackUpAnkyIdentity -> stringResource(R.string.you_status_could_not_backup_anky_identity)
        YouStatusCopy.CouldNotScheduleDailyReminder -> stringResource(R.string.you_status_could_not_schedule_daily_reminder)
        YouStatusCopy.CouldNotLoadCredits -> stringResource(R.string.you_status_could_not_load_credits)
        YouStatusCopy.EncryptedBackupOn -> stringResource(R.string.you_status_encrypted_backup_on)
        YouStatusCopy.EncryptedBackupOff -> stringResource(R.string.you_status_encrypted_backup_off)
        YouStatusCopy.EncryptedBackupUpdated -> stringResource(R.string.you_status_encrypted_backup_updated)
        YouStatusCopy.EncryptedBackupOnAfterNextWriting -> stringResource(R.string.you_status_encrypted_backup_on_after_next_writing)
        YouStatusCopy.CouldNotEnableEncryptedBackup -> stringResource(R.string.you_status_could_not_enable_encrypted_backup)
        YouStatusCopy.CouldNotUpdateEncryptedBackup -> stringResource(R.string.you_status_could_not_update_encrypted_backup)
        else -> stringResource(R.string.you_status_unexpected_problem)
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
                        Text(
                            stringResource(R.string.all_ankys_empty_message),
                            style = AnkyType.Body.copy(fontSize = 17.sp, color = AnkyColors.PaperMuted),
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
    val importedReflection = stringResource(R.string.imported_reflection_title)
    val fragmentTitle = stringResource(R.string.session_fragment_title)
    val noReadableText = stringResource(R.string.map_no_readable_text)
    val title = session.localizedHistoryTitle(importedReflection, fragmentTitle)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable { onOpenReveal(session.hash) }
            .semantics(mergeDescendants = true) {
                contentDescription = historySessionAccessibilityLabel(
                    session = session,
                    importedReflection = importedReflection,
                    fragmentTitle = fragmentTitle,
                    noReadableText = noReadableText,
                )
            }
            .padding(vertical = 15.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Text(
                title,
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

private fun historySessionAccessibilityLabel(
    session: SessionSummary,
    importedReflection: String,
    fragmentTitle: String,
    noReadableText: String,
): String =
    listOf(
        session.localizedHistoryTitle(importedReflection, fragmentTitle),
        session.localizedHistoryPreview(noReadableText),
    ).joinToString(", ")

private fun SessionSummary.localizedHistoryTitle(importedReflection: String, fragmentTitle: String): String =
    when (title) {
        "Imported reflection" -> importedReflection
        "Fragment" -> fragmentTitle
        else -> title
    }

private fun SessionSummary.localizedHistoryPreview(noReadableText: String): String =
    if (preview == "No readable text") noReadableText else preview

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
    ArticleBodyText(stringResource(R.string.privacy_article_body))
}

@Composable
private fun TermsPage() {
    Text(stringResource(R.string.you_terms_conditions), style = AnkyType.Heading.copy(fontSize = 24.sp, color = AnkyColors.Paper), textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())
    Text(stringResource(R.string.terms_reflection_agreement), style = AnkyType.Caption.copy(color = AnkyColors.PaperMuted), textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())
    ArticleBodyText(stringResource(R.string.terms_article_body))
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
        Text(stringResource(R.string.you_restore_identity_note), style = AnkyType.Body.copy(fontSize = 14.sp, color = AnkyColors.PaperMuted))
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
                            isRecommended = creditPackage.productId == "inc.anky.credits.11" ||
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
                localizedYouStatusMessage(error),
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
            .height(94.dp)
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
            .padding(horizontal = 14.dp),
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
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
            Text(
                localizedCreditPackageTitle(creditPackage),
                style = AnkyType.Heading.copy(fontSize = 20.sp, fontWeight = FontWeight.SemiBold),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                localizedCreditPackageSubtitle(creditPackage),
                style = AnkyType.Body.copy(fontSize = 13.sp, lineHeight = 17.sp, fontWeight = FontWeight.Medium, color = AnkyColors.Paper.copy(alpha = 0.58f)),
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
        }
        Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(8.dp)) {
            if (isRecommended && !isPurchasing) {
                Text(
                    stringResource(R.string.best_value),
                    style = AnkyType.Mono.copy(fontSize = 10.sp, fontWeight = FontWeight.Bold, color = AnkyColors.Ink),
                    modifier = Modifier
                        .clip(RoundedCornerShape(999.dp))
                        .background(AnkyColors.Gold)
                        .padding(horizontal = 10.dp, vertical = 5.dp),
                )
            }
            Text(
                if (isPurchasing) "..." else creditPackage.price,
                style = AnkyType.Heading.copy(fontSize = 18.sp, fontWeight = FontWeight.SemiBold, color = AnkyColors.Gold),
                maxLines = 1,
            )
        }
    }
}

@Composable
private fun localizedCreditPackageTitle(creditPackage: CreditPackage): String =
    when (creditPackage.productId) {
        "inc.anky.credits.3" -> stringResource(R.string.credit_pack_3_title)
        "inc.anky.credits.11" -> stringResource(R.string.credit_pack_11_title)
        "inc.anky.credits.33" -> stringResource(R.string.credit_pack_33_title)
        else -> creditPackage.title
    }

@Composable
private fun localizedCreditPackageSubtitle(creditPackage: CreditPackage): String =
    when (creditPackage.productId) {
        "inc.anky.credits.3" -> stringResource(R.string.credit_pack_3_subtitle)
        "inc.anky.credits.11" -> stringResource(R.string.credit_pack_11_subtitle)
        "inc.anky.credits.33" -> stringResource(R.string.credit_pack_33_subtitle)
        else -> creditPackage.subtitle
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
                localizedCreditPackageTitle(creditPackage),
                style = AnkyType.Body.copy(fontSize = 17.sp, fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold),
            )
            val localizedSubtitle = localizedCreditPackageSubtitle(creditPackage)
            if (localizedSubtitle.isNotBlank() && localizedSubtitle != localizedCreditPackageTitle(creditPackage)) {
                Text(localizedSubtitle, style = AnkyType.Caption)
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
    ArticleBodyText(stringResource(R.string.token_article_body))
        AnkyPanel {
            Text(PrivacyMessages.AnkyCoinContractAddress, style = AnkyType.Mono)
        if (hasCanonicalAnkyContractAddress()) {
            AnkyActionButton(if (copied.value) stringResource(R.string.copied_exclamation) else stringResource(R.string.copy_contract_address)) {
                onCopy()
                copied.value = true
            }
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
            label = { Text(stringResource(R.string.mirror_base_url)) },
            modifier = Modifier.fillMaxWidth(),
        )
        Text(stringResource(R.string.mirror_base_url_help), style = AnkyType.Body.copy(fontSize = 14.sp, color = AnkyColors.PaperMuted))
        AnkyActionButton(stringResource(R.string.save_mirror_url), onClick = onSaveMirrorUrl)
        AnkyActionButton(stringResource(R.string.repair_map_index), onClick = onRepairMapIndex)
    }
    AnkyPanel {
        AnkyActionButton(stringResource(R.string.clear_local_reflections_action), destructive = true, onClick = onClearReflections)
        AnkyActionButton(stringResource(R.string.clear_local_anky_archive_action), destructive = true, onClick = onClearArchive)
        AnkyActionButton(stringResource(R.string.reset_identity_action), destructive = true, onClick = onResetIdentity)
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
@Composable private fun Rule(text: String) = Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) { Box(Modifier.size(5.dp).clip(CircleShape).background(AnkyColors.Gold.copy(alpha = 0.72f))); Text(text, style = AnkyType.Body.copy(color = AnkyColors.PaperMuted)) }
@Composable private fun Divider() = Box(Modifier.fillMaxWidth().height(1.dp).background(AnkyColors.Gold.copy(alpha = 0.13f)))
@Composable private fun VerticalDivider() = Box(Modifier.height(52.dp).size(width = 1.dp, height = 52.dp).background(AnkyColors.Gold.copy(alpha = 0.12f)))

@Composable
private fun MarkdownArticleText(text: String) {
    Text(markdownLinks(text), style = AnkyType.Body)
}

@Composable
private fun ArticleBodyText(text: String) {
    text.trimIndent()
        .split(Regex("\\n\\s*\\n"))
        .map { it.trim() }
        .filter { it.isNotEmpty() }
        .forEach { paragraph ->
            when {
                paragraph.startsWith("## ") -> {
                    Text(paragraph.removePrefix("## "), style = AnkyType.Heading.copy(fontSize = 21.sp), modifier = Modifier.padding(top = 4.dp))
                }
                paragraph.startsWith("- ") -> Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    paragraph.lines()
                        .map { it.removePrefix("- ").trim() }
                        .filter { it.isNotEmpty() }
                        .forEach { Rule(it) }
                }
                else -> MarkdownArticleText(paragraph)
            }
        }
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

private enum class YouPrompt {
    Identity,
    Privacy,
    Export,
    Credits,
    Support,
    Developer,
}

@Composable
private fun localizedYouPromptMessage(prompt: YouPrompt): String =
    when (prompt) {
        YouPrompt.Identity -> stringResource(R.string.you_prompt_identity)
        YouPrompt.Privacy -> stringResource(R.string.you_prompt_privacy)
        YouPrompt.Export -> stringResource(R.string.you_prompt_export)
        YouPrompt.Credits -> stringResource(R.string.you_prompt_credits)
        YouPrompt.Support -> stringResource(R.string.you_prompt_support)
        YouPrompt.Developer -> stringResource(R.string.you_prompt_developer)
    }

@Composable
private fun youConversationMessage(
    state: YouState,
    activePrompt: YouPrompt?,
    isShowingSystemPrompt: Boolean,
): String =
    if (isShowingSystemPrompt) {
        state.error?.let { localizedYouStatusMessage(it) }
            ?: state.statusMessage?.let { localizedYouStatusMessage(it) }
            ?: activePrompt?.let { localizedYouPromptMessage(it) }.orEmpty()
    } else if (activePrompt == YouPrompt.Credits) {
        val purchasingPackage = state.purchasingCreditPackageId
            ?.let { packageId -> state.creditState.packages.firstOrNull { it.packageId == packageId } }
        when {
            purchasingPackage != null -> stringResource(R.string.you_conversation_opening_pack, localizedCreditPackageTitle(purchasingPackage))
            state.creditState.isLoading -> stringResource(R.string.you_conversation_checking_credit_gate)
            else -> creditsPromptMessage(state)
        }
    } else if (activePrompt == YouPrompt.Export) {
        if (state.isEncryptedBackupWorking) {
            stringResource(R.string.you_conversation_updating_encrypted_backup)
        } else {
            encryptedBackupDetail(state)
        }
    } else {
        activePrompt?.let { localizedYouPromptMessage(it) }.orEmpty()
    }

private fun isConversationThinking(activePrompt: YouPrompt?, state: YouState): Boolean =
    (activePrompt == YouPrompt.Credits &&
        (state.creditState.isLoading || state.purchasingCreditPackageId != null)) ||
        (activePrompt == YouPrompt.Export && state.isEncryptedBackupWorking)

@Composable
private fun encryptedBackupDetail(state: YouState): String {
    if (state.isEncryptedBackupEnabled) {
        val lastBackup = state.encryptedBackupLastDate
        return if (lastBackup != null) {
            stringResource(R.string.you_encrypted_backup_last_updated, lastBackup.formattedForYouBackup())
        } else {
            stringResource(R.string.you_status_encrypted_backup_on_after_next_writing)
        }
    }
    return stringResource(R.string.you_encrypted_backup_export_or_turn_on)
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
        state.creditState.isLoading && state.creditState.balance == null -> loadingBalance
        state.creditState.balance != null -> "${state.creditState.balance} ${if (state.creditState.balance == 1) creditSingular else creditPlural}"
        else -> reflectionBalance
    }

@Composable
private fun creditsPromptMessage(state: YouState): String {
    val balance = when {
        state.creditState.isLoading && state.creditState.balance == null -> stringResource(R.string.you_credit_balance_loading)
        state.creditState.balance != null -> state.creditState.balance.toString()
        else -> stringResource(R.string.you_credit_balance_unknown)
    }
    return stringResource(R.string.you_credit_prompt_message, balance)
}

private fun hasCanonicalAnkyContractAddress(): Boolean {
    val address = PrivacyMessages.AnkyCoinContractAddress
    return address.startsWith("0x") && address.length == 42
}

private fun ankyContractDisplayAddress(): String {
    val address = PrivacyMessages.AnkyCoinContractAddress
    return if (hasCanonicalAnkyContractAddress()) {
        "${address.take(5)}...${address.takeLast(5)}"
    } else {
        address
    }
}

private data class YouPromptActionLabels(
    val backUpRecoveryWords: String,
    val backingUp: String,
    val backUpNow: String,
    val exportWritings: String,
    val copyAccount: String,
    val ankyAddress: String,
    val repairMapIndex: String,
    val deleteLocalData: String,
    val openEmail: String,
    val loadingCreditPacks: String,
    val refreshCredits: String,
    val bestValue: String,
    val creditPack3Title: String,
    val creditPack11Title: String,
    val creditPack33Title: String,
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
            if (packages.isEmpty()) {
                listOf(
                    AnkyChatAction(if (state.creditState.isLoading) labels.loadingCreditPacks else labels.refreshCredits, isPrimary = true) {
                        viewModel.refreshCredits()
                    },
                )
            } else {
                packages.map { creditPackage ->
                    val isRecommended = creditPackage.productId == "inc.anky.credits.11" ||
                        creditPackage.packageId.endsWith(".credits.11")
                    AnkyChatAction(
                        title = localizedCreditPackageTitle(creditPackage, labels),
                        isPrimary = isRecommended,
                        subtitle = creditPackage.price,
                        badge = if (isRecommended) labels.bestValue else null,
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
                AnkyChatAction(labels.repairMapIndex, isPrimary = true) { viewModel.rebuildSessionIndex() },
                AnkyChatAction(labels.deleteLocalData) { confirmDeleteLocalData() },
            )
        } else {
            emptyList()
        }
        null -> emptyList()
    }

private fun localizedCreditPackageTitle(creditPackage: CreditPackage, labels: YouPromptActionLabels): String =
    when (creditPackage.productId) {
        "inc.anky.credits.3" -> labels.creditPack3Title
        "inc.anky.credits.11" -> labels.creditPack11Title
        "inc.anky.credits.33" -> labels.creditPack33Title
        else -> creditPackage.title
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

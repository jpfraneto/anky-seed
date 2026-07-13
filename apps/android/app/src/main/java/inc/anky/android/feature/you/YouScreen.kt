package inc.anky.android.feature.you

import android.Manifest
import android.app.Activity
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.BitmapFactory
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
import androidx.compose.material.icons.filled.ChevronLeft
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.PriorityHigh
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.asImageBitmap
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
import inc.anky.android.core.gate.DailyTargetStore
import inc.anky.android.core.gate.GateStorage
import inc.anky.android.core.gate.WriteBeforeScrollEventLogStore
import inc.anky.android.core.gate.WriteBeforeScrollEventName
import inc.anky.android.core.gate.WritingAnchorStore
import inc.anky.android.core.protocol.AnkyDuration
import inc.anky.android.core.protocol.AnkyParser
import inc.anky.android.core.protocol.AnkyReconstructor
import inc.anky.android.core.protocol.AnkyWriter
import inc.anky.android.core.storage.AvatarStore
import inc.anky.android.core.storage.SessionSummary
import inc.anky.android.core.subscription.EntitlementStore
import inc.anky.android.feature.settings.AnkySettingsScreen
import inc.anky.android.feature.write.HiddenTextInput
import inc.anky.android.ui.components.AnkyChatAction
import inc.anky.android.ui.components.AnkyConversationPrompt
import inc.anky.android.ui.lazure.LazureMood
import inc.anky.android.ui.lazure.LazurePigments
import inc.anky.android.ui.lazure.LazureWall
import inc.anky.android.ui.theme.AnkyActionButton
import inc.anky.android.ui.theme.AnkyColors
import inc.anky.android.ui.theme.AnkyType
import java.io.File
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale
import kotlinx.coroutines.delay

private const val AnkyExperienceTotalSeconds = 88 * 60

/**
 * Compatibility entry for any old in-process caller that still asks for the
 * removed credits page. It lands on subscription truth instead.
 */
enum class YouInitialPage {
    Credits,
}

/** Lazure remap for the You surfaces: paper wall, violet-ink text, gold accents. */
private object YouLz {
    val paper = LazurePigments.ankyInk
    val paperMuted = LazurePigments.ankyInkSoft
    val gold = LazurePigments.ankyGold
    val goldDim = LazurePigments.ankyGold.copy(alpha = 0.32f)
    val panel = LazurePigments.ankyPaper.copy(alpha = 0.72f)
    val panelStrong = LazurePigments.ankyPaperDeep
    val danger = LazurePigments.ankyMadder
    val hairline = LazurePigments.hairline
}

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
    onGateSetupRequested: () -> Unit = {},
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
    val showsAccountDeletion = remember { mutableStateOf(false) }
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
    val onEncryptedBackupToggle: (Boolean) -> Unit = { enabled ->
        if (enabled) {
            viewModel.enableEncryptedBackup(enableEncryptedBackupReason, couldNotConfirmIdentity)
        } else {
            viewModel.disableEncryptedBackup()
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
    DisposableEffect(Unit) {
        onDispose { onExperienceVisibilityChanged(false) }
    }

    Box(Modifier.fillMaxSize().testTag("you-screen")) {
        LazureWall(mood = LazureMood.Dawn, modifier = Modifier.fillMaxSize())
        Box(Modifier.fillMaxSize()) {
            if (page.value == null) {
                YouHome(
                    state = state,
                    onOpenPage = { page.value = it },
                    showsAccountDeletion = showsAccountDeletion.value,
                    onToggleAccountDeletion = { showsAccountDeletion.value = !showsAccountDeletion.value },
                    onDeleteAccountAndData = { confirmDeleteAccountAndData.value = true },
                    onAppLockChange = onAppLockChange,
                    onEncryptedBackupToggle = onEncryptedBackupToggle,
                    onGateSetupRequested = onGateSetupRequested,
                    onFounderChat = { context.openUrl(FounderChatUrl) },
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
            } else if (page.value == YouPage.Settings) {
                AnkySettingsScreen(
                    appLockEnabled = state.appLockEnabled,
                    canUseAppLock = canUseDeviceLock(context),
                    onAppLockChange = onAppLockChange,
                    isEncryptedBackupEnabled = state.isEncryptedBackupEnabled,
                    encryptedBackupLastDate = state.encryptedBackupLastDate,
                    onEncryptedBackupToggle = onEncryptedBackupToggle,
                    mirrorBaseUrl = state.mirrorBaseUrl,
                    onMirrorBaseUrlSave = viewModel::setMirrorBaseUrl,
                    subscriptionTitle = subscriptionStatusTitle(state.subscription),
                    subscriptionDetail = subscriptionStatusDetail(state.subscription, state.isSubscriptionTruthAvailable),
                    isSubscriptionEntitled = state.subscription.isEntitled,
                    isRestoringSubscription = state.isRestoringPurchases,
                    restoreStatusLine = state.statusMessage?.takeIf { it in subscriptionRestoreLines },
                    onRestoreSubscription = viewModel::restorePurchases,
                    onManageSubscription = { context.openUrl(PlayManageSubscriptionsUrl) },
                    onGateSetupRequested = onGateSetupRequested,
                    onFounderChat = { context.openUrl(FounderChatUrl) },
                    onContactSupport = { context.openUrl(state.supportFeedbackEmailUrl) },
                    onClearLocalData = { confirmDeleteLocalData.value = true },
                    appVersion = state.appVersion,
                    onBack = { page.value = null },
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
                            onEncryptedBackupToggle = onEncryptedBackupToggle,
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
                        YouPage.Settings -> Unit
                        YouPage.Subscription -> SubscriptionPage(
                            state = state,
                            onRestorePurchases = viewModel::restorePurchases,
                            onManageSubscription = { context.openUrl(PlayManageSubscriptionsUrl) },
                            onFounderChat = { context.openUrl(FounderChatUrl) },
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

/** Restore truth lines from [EntitlementStore] surfaced under the settings restore link. */
private val subscriptionRestoreLines = setOf(
    EntitlementStore.RESTORE_SUCCESS_LINE,
    EntitlementStore.RESTORE_NOTHING_LINE,
    EntitlementStore.RESTORE_FAILED_LINE,
    EntitlementStore.STORE_UNREACHABLE_LINE,
)

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
    onOpenPage: (YouPage) -> Unit,
    showsAccountDeletion: Boolean,
    onToggleAccountDeletion: () -> Unit,
    onDeleteAccountAndData: () -> Unit,
    onAppLockChange: (Boolean) -> Unit,
    onEncryptedBackupToggle: (Boolean) -> Unit,
    onGateSetupRequested: () -> Unit,
    onFounderChat: () -> Unit,
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
    val writerName = remember(context) { WritingAnchorStore(GateStorage.preferences(context)).writerName ?: WritingAnchorStore.DefaultWriterName }
    val dailyTargetStore = remember(context) { DailyTargetStore(GateStorage.preferences(context)) }
    val effectiveTargetMinutes = remember { mutableStateOf(DailyTargetStore.DefaultMinutes) }
    val pendingTargetMinutes = remember { mutableStateOf<Int?>(null) }
    fun refreshDailyTarget() {
        effectiveTargetMinutes.value = dailyTargetStore.effectiveTargetMinutes()
        pendingTargetMinutes.value = dailyTargetStore.pendingTargetMinutes()
    }
    LaunchedEffect(Unit) { refreshDailyTarget() }
    val onDailyTargetChange: (Int) -> Unit = { minutes ->
        val change = dailyTargetStore.requestTargetChange(minutes)
        WriteBeforeScrollEventLogStore(GateStorage.preferences(context)).append(
            WriteBeforeScrollEventName.TargetChanged,
            metadata = mapOf(
                "oldMinutes" to "${change.oldMinutes}",
                "newMinutes" to "${change.newMinutes}",
            ),
        )
        refreshDailyTarget()
    }
    Box(Modifier.fillMaxSize()) {
        Text(
            stringResource(R.string.you_title),
            style = AnkyType.Body.copy(
                fontSize = 17.sp,
                fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold,
                color = YouLz.paper,
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
            YouHeader(writerName = writerName, accountId = state.accountId)
            YouStats(
                state = state,
                onClick = { onOpenPage(YouPage.History) },
            )
            YouPanel(spacing = 0.dp) {
                MenuRow(
                    R.drawable.you_icon_settings,
                    stringResource(R.string.you_customize_row_title),
                    stringResource(R.string.you_customize_row_subtitle),
                ) { onOpenPage(YouPage.Settings) }
                Divider()
                DataToggleRow(
                    title = stringResource(R.string.you_data),
                    subtitle = dataSubtitle,
                    checked = state.isEncryptedBackupEnabled,
                    onToggle = onEncryptedBackupToggle,
                    onClick = { onOpenPage(YouPage.Export) },
                )
                Divider()
                MenuRow(
                    R.drawable.you_icon_settings,
                    stringResource(R.string.you_wbs_row_title),
                    stringResource(R.string.you_wbs_row_subtitle),
                ) { onGateSetupRequested() }
                Divider()
                DailyTargetRow(
                    effectiveTargetMinutes = effectiveTargetMinutes.value,
                    pendingTargetMinutes = pendingTargetMinutes.value,
                    onChange = onDailyTargetChange,
                )
                Divider()
                MenuRow(
                    R.drawable.you_icon_account,
                    stringResource(R.string.you_private_access),
                    stringResource(R.string.you_writing_access_stays),
                ) { onOpenPage(YouPage.Account) }
                Divider()
                PromptRow(R.drawable.you_icon_support, stringResource(R.string.you_support_feedback), stringResource(R.string.you_email_support), false) { onPrompt(YouPrompt.Support) }
                Divider()
                PromptRow(R.drawable.you_icon_privacy, stringResource(R.string.you_privacy_policy), stringResource(R.string.you_privacy_subtitle), selected = false) { onOpenPage(YouPage.Privacy) }
                Divider()
                PromptRow(R.drawable.you_icon_terms, stringResource(R.string.you_terms_conditions), stringResource(R.string.you_terms_subtitle), selected = false) { onOpenPage(YouPage.Terms) }
                Divider()
                MenuRow(
                    R.drawable.you_icon_credits,
                    stringResource(R.string.you_subscription),
                    subscriptionStatusTitle(state.subscription),
                ) { onOpenPage(YouPage.Subscription) }
                Divider()
                MenuRow(
                    R.drawable.you_icon_support,
                    stringResource(R.string.you_founder_chat),
                    stringResource(R.string.you_founder_chat_subtitle),
                ) { onFounderChat() }
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
                Divider()
                VersionRow(appVersion = state.appVersion)
            }
            if (showsAccountDeletion) {
                YouPanel(spacing = 0.dp) {
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
                tint = YouLz.danger.copy(alpha = 0.88f),
                modifier = Modifier.size(24.dp),
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
        YouStatusCopy.RecoveryWordsInvalidChecksum -> stringResource(R.string.you_status_recovery_words_invalid_checksum)
        YouStatusCopy.SubscriptionTruthUnavailable -> stringResource(R.string.you_status_subscription_unavailable)
        EntitlementStore.RESTORE_SUCCESS_LINE -> stringResource(R.string.you_status_subscription_restored)
        EntitlementStore.RESTORE_NOTHING_LINE -> stringResource(R.string.you_status_subscription_nothing_to_restore)
        EntitlementStore.RESTORE_FAILED_LINE -> stringResource(R.string.you_status_subscription_restore_failed)
        EntitlementStore.STORE_UNREACHABLE_LINE -> stringResource(R.string.you_status_subscription_store_unreachable)
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
private fun YouHeader(writerName: String, accountId: String) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        YouAvatar()
        Text(
            writerName,
            style = AnkyType.Heading.copy(fontSize = 24.sp, color = YouLz.paper),
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
        if (accountId.isNotBlank()) {
            Text(
                accountId,
                style = AnkyType.Mono.copy(fontSize = 11.sp, color = YouLz.paperMuted),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}

@Composable
private fun YouAvatar() {
    val context = LocalContext.current
    val avatarBitmap = remember(context) {
        AvatarStore(context).loadData()?.let { bytes ->
            runCatching { BitmapFactory.decodeByteArray(bytes, 0, bytes.size)?.asImageBitmap() }.getOrNull()
        }
    }
    Box(Modifier.size(144.dp), contentAlignment = Alignment.Center) {
        Box(
            Modifier
                .size(124.dp)
                .shadow(
                    elevation = 16.dp,
                    shape = CircleShape,
                    clip = false,
                    ambientColor = YouLz.gold.copy(alpha = 0.24f),
                    spotColor = YouLz.gold.copy(alpha = 0.24f),
                )
                .clip(CircleShape)
                .border(1.5.dp, YouLz.gold.copy(alpha = 0.72f), CircleShape),
        )
        Box(Modifier.size(116.dp).clip(CircleShape).border(1.dp, YouLz.gold.copy(alpha = 0.42f), CircleShape))
        if (avatarBitmap != null) {
            Image(
                bitmap = avatarBitmap,
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.size(108.dp).clip(CircleShape),
            )
        } else {
            Image(
                painter = painterResource(R.drawable.you_avatar_anky),
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.size(108.dp).clip(CircleShape),
            )
        }
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
                    .background(YouLz.gold),
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
        YouPanel(spacing = 0.dp, verticalPadding = 0.dp) {
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
            Text(value, style = AnkyType.Body.copy(fontSize = 17.sp, color = YouLz.paper))
            Text(label, style = AnkyType.Caption.copy(fontSize = 10.sp, color = YouLz.paperMuted))
        }
    }
}

/** The one card silhouette of the You surfaces — a translucent paper veil on the wall. */
@Composable
private fun YouPanel(
    modifier: Modifier = Modifier,
    spacing: androidx.compose.ui.unit.Dp = 12.dp,
    verticalPadding: androidx.compose.ui.unit.Dp = 14.dp,
    content: @Composable androidx.compose.foundation.layout.ColumnScope.() -> Unit,
) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(18.dp))
            .background(YouLz.panel)
            .border(0.5.dp, YouLz.hairline, RoundedCornerShape(18.dp))
            .padding(horizontal = 16.dp, vertical = verticalPadding),
        verticalArrangement = Arrangement.spacedBy(spacing),
        content = content,
    )
}

@Composable
private fun MenuRow(icon: Int, title: String, subtitle: String, onClick: () -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick).padding(vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Image(painterResource(icon), null, modifier = Modifier.size(24.dp))
        Column(Modifier.weight(1f).padding(start = 13.dp)) {
            Text(title, style = AnkyType.Body.copy(fontSize = 17.sp, fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold, color = YouLz.paper), maxLines = 1)
            Text(subtitle, style = AnkyType.Caption.copy(fontSize = 12.sp, color = YouLz.paperMuted), maxLines = 2, overflow = TextOverflow.Ellipsis)
        }
        Image(painterResource(R.drawable.you_icon_chevron_right), null, modifier = Modifier.size(14.dp).alpha(0.82f))
    }
}

@Composable
private fun VersionRow(appVersion: String) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Image(painterResource(R.drawable.you_app_logo), null, modifier = Modifier.size(24.dp).clip(CircleShape))
        Column(Modifier.weight(1f).padding(start = 13.dp)) {
            Text(
                stringResource(R.string.app_name_anky),
                style = AnkyType.Body.copy(fontSize = 17.sp, fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold, color = YouLz.paper),
                maxLines = 1,
            )
            Text(
                stringResource(R.string.you_app_version_format, appVersion),
                style = AnkyType.Caption.copy(fontSize = 12.sp, color = YouLz.paperMuted),
                maxLines = 1,
            )
        }
    }
}

@Composable
private fun DailyTargetRow(
    effectiveTargetMinutes: Int,
    pendingTargetMinutes: Int?,
    onChange: (Int) -> Unit,
) {
    val shownMinutes = pendingTargetMinutes ?: effectiveTargetMinutes
    val subtitle = if (pendingTargetMinutes != null && pendingTargetMinutes != effectiveTargetMinutes) {
        stringResource(R.string.you_daily_target_pending_format, effectiveTargetMinutes, pendingTargetMinutes)
    } else if (effectiveTargetMinutes == 1) {
        stringResource(R.string.you_daily_target_subtitle_one, effectiveTargetMinutes)
    } else {
        stringResource(R.string.you_daily_target_subtitle_other, effectiveTargetMinutes)
    }
    Row(
        modifier = Modifier.fillMaxWidth().padding(vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Image(painterResource(R.drawable.you_icon_clock_stat), null, modifier = Modifier.size(24.dp))
        Column(Modifier.weight(1f).padding(start = 13.dp)) {
            Text(
                stringResource(R.string.you_daily_target),
                style = AnkyType.Body.copy(fontSize = 17.sp, fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold, color = YouLz.paper),
                maxLines = 1,
            )
            Text(subtitle, style = AnkyType.Caption.copy(fontSize = 12.sp, color = YouLz.paperMuted), maxLines = 2, overflow = TextOverflow.Ellipsis)
        }
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            DailyTargetStepButton(
                glyph = "−",
                label = stringResource(R.string.you_daily_target_decrease),
                enabled = shownMinutes > DailyTargetStore.MinutesRange.first,
            ) { onChange(shownMinutes - 1) }
            Text(
                shownMinutes.toString(),
                style = AnkyType.Mono.copy(fontSize = 16.sp, fontWeight = FontWeight.SemiBold, color = YouLz.paper),
            )
            DailyTargetStepButton(
                glyph = "+",
                label = stringResource(R.string.you_daily_target_increase),
                enabled = shownMinutes < DailyTargetStore.MinutesRange.last,
            ) { onChange(shownMinutes + 1) }
        }
    }
}

@Composable
private fun DailyTargetStepButton(
    glyph: String,
    label: String,
    enabled: Boolean,
    onClick: () -> Unit,
) {
    Box(
        modifier = Modifier
            .size(32.dp)
            .clip(CircleShape)
            .background(YouLz.panelStrong.copy(alpha = if (enabled) 0.9f else 0.4f))
            .border(0.5.dp, YouLz.goldDim, CircleShape)
            .clickable(enabled = enabled, onClick = onClick)
            .semantics { contentDescription = label },
        contentAlignment = Alignment.Center,
    ) {
        Text(
            glyph,
            style = AnkyType.Body.copy(fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = YouLz.paper.copy(alpha = if (enabled) 1f else 0.4f)),
        )
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
            tint = YouLz.danger.copy(alpha = 0.9f),
            modifier = Modifier.size(22.dp),
        )
        Text(
            title,
            style = AnkyType.Body.copy(
                fontSize = 16.sp,
                fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold,
                color = YouLz.danger.copy(alpha = 0.94f),
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
            tint = YouLz.paperMuted.copy(alpha = 0.86f),
            modifier = Modifier.size(24.dp),
        )
        Column(Modifier.weight(1f).padding(start = 13.dp)) {
            Text(
                title,
                style = AnkyType.Body.copy(
                    fontSize = 17.sp,
                    fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold,
                    color = YouLz.paper,
                ),
                maxLines = 1,
            )
            Text(
                if (checked) checkedText else uncheckedText,
                style = AnkyType.Caption.copy(fontSize = 12.sp, color = YouLz.paperMuted),
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
                        color = YouLz.paper,
                    ),
                    maxLines = 1,
                )
                Text(
                    subtitle,
                    style = AnkyType.Caption.copy(fontSize = 12.sp, color = YouLz.paperMuted),
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
                    color = if (selected) YouLz.gold else YouLz.paper,
                ),
                maxLines = 1,
            )
            Text(subtitle, style = AnkyType.Caption.copy(fontSize = 12.sp, color = YouLz.paperMuted), maxLines = 2, overflow = TextOverflow.Ellipsis)
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
                    .background(YouLz.panel)
                    .border(1.dp, YouLz.goldDim, CircleShape)
                    .clickable(onClick = onBack),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    imageVector = Icons.Filled.ChevronLeft,
                    contentDescription = backLabel,
                    tint = YouLz.gold,
                    modifier = Modifier.size(24.dp),
                )
            }
            Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally) {
                Text(stringResource(page.titleRes), style = AnkyType.Heading.copy(fontSize = 26.sp, color = YouLz.paper))
                Text(stringResource(page.subtitleRes), style = AnkyType.Caption.copy(color = YouLz.paperMuted))
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
    YouPanel {
        Text(stringResource(R.string.you_private_access), style = AnkyType.Caption.copy(color = YouLz.gold))
        Text(
            stringResource(R.string.you_private_profile),
            style = AnkyType.Body.copy(
                fontSize = 17.sp,
                fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold,
                color = YouLz.paper,
            ),
        )
        Text(stringResource(R.string.you_writing_access_stays), style = AnkyType.Body.copy(fontSize = 14.sp, color = YouLz.paperMuted))
    }
    YouPanel {
        Text(stringResource(R.string.you_advanced_recovery), style = AnkyType.Caption.copy(color = YouLz.gold))
        Text(stringResource(R.string.you_recovery_words_restore), style = AnkyType.Body.copy(fontSize = 14.sp, color = YouLz.paperMuted))
        Divider()
        SwitchRow(stringResource(R.string.device_lock_app_protection), state.appLockEnabled, onAppLock)
        Text(stringResource(R.string.you_recovery_words_gate), style = AnkyType.Body.copy(fontSize = 14.sp, color = YouLz.paperMuted))
        Text(stringResource(R.string.you_passcode_biometrics_note), style = AnkyType.Body.copy(fontSize = 14.sp, color = YouLz.paperMuted))
        if (state.recoveryPhrase == null) {
            AnkyActionButton(stringResource(R.string.you_reveal_recovery_words), enabled = state.appLockEnabled, onClick = onRevealRecovery)
        } else {
            Text(state.recoveryPhrase, style = AnkyType.Mono.copy(color = YouLz.paper))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                AnkyActionButton(stringResource(R.string.you_copy_recovery_words), modifier = Modifier.weight(1f), onClick = onCopyRecovery)
                AnkyActionButton(stringResource(R.string.hide), modifier = Modifier.weight(1f), onClick = onHideRecovery)
            }
        }
        AnkyActionButton(stringResource(R.string.you_recover_access), onClick = onImportPhrase)
        AnkyActionButton(stringResource(R.string.you_backup_recovery_words_secure_storage), onClick = onBackupIdentity)
        Text(stringResource(R.string.you_secure_storage_note), style = AnkyType.Body.copy(fontSize = 14.sp, color = YouLz.paperMuted))
        Text(stringResource(R.string.anky_address), style = AnkyType.Caption.copy(color = YouLz.gold))
        Text(state.accountId, style = AnkyType.Mono.copy(color = YouLz.paperMuted))
        AnkyActionButton(stringResource(R.string.copy_account), onClick = onCopyAccountId)
    }
    YouPanel {
        SwitchRow(stringResource(R.string.daily_reminder), state.dailyReminderEnabled, onReminder)
        DetailRow(stringResource(R.string.time), YouViewModel.formatReminderTime(state.dailyReminderMinutes))
        AnkyActionButton(stringResource(R.string.change_time), enabled = state.dailyReminderEnabled, onClick = onReminderTime)
    }
    YouPanel {
        Text(stringResource(R.string.you_ownership_note), style = AnkyType.Caption.copy(color = YouLz.gold))
        Text(stringResource(R.string.you_ownership_body), style = AnkyType.Body.copy(fontSize = 14.sp, color = YouLz.paperMuted))
    }
    YouDangerPanel {
        Text(stringResource(R.string.danger_zone), style = AnkyType.Heading.copy(fontSize = 18.sp, color = YouLz.danger))
        Text(stringResource(R.string.you_delete_account_data_detail_body), style = AnkyType.Body.copy(fontSize = 14.sp, color = YouLz.paperMuted))
        AnkyActionButton(stringResource(R.string.you_delete_account_data_caps), destructive = true, onClick = onDeleteAccountAndData)
    }
}

@Composable
internal fun PrivacyPage() {
    Text(stringResource(R.string.privacy_page_heading), style = AnkyType.Heading.copy(fontSize = 19.sp, color = YouLz.paper), textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())
    ArticleBodyText(stringResource(R.string.privacy_article_body))
}

@Composable
internal fun TermsPage() {
    Text(stringResource(R.string.you_terms_conditions), style = AnkyType.Heading.copy(fontSize = 24.sp, color = YouLz.paper), textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())
    Text(stringResource(R.string.terms_reflection_agreement), style = AnkyType.Caption.copy(color = YouLz.paperMuted), textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())
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

    YouPanel {
        Text(stringResource(R.string.you_local_files_reflections_format, state.localAnkyFileCount, state.reflectionCount), style = AnkyType.Heading.copy(color = YouLz.gold))
        Text(stringResource(R.string.you_readable_exports_note), style = AnkyType.Body.copy(fontSize = 14.sp, color = YouLz.paperMuted))
    }
    YouPanel {
        when (formattedWritingExportAction(state)) {
            FormattedWritingExportAction.Share -> AnkyActionButton(stringResource(R.string.export_writings), onClick = onShareWritingExport)
            FormattedWritingExportAction.Empty -> DisabledRow(stringResource(R.string.you_no_writing_to_export))
        }
    }
    YouPanel {
        SwitchRow(stringResource(R.string.you_encrypted_backup), state.isEncryptedBackupEnabled, onEncryptedBackupToggle)
        Text(encryptedBackupDetail(state), style = AnkyType.Body.copy(fontSize = 14.sp, color = YouLz.paperMuted))
        if (state.isEncryptedBackupEnabled) {
            AnkyActionButton(if (state.isEncryptedBackupWorking) stringResource(R.string.backing_up) else stringResource(R.string.back_up_now), enabled = !state.isEncryptedBackupWorking, onClick = onEncryptedBackupNow)
        }
        AnkyActionButton(stringResource(R.string.you_restore_encrypted_backup), enabled = !state.isEncryptedBackupWorking, onClick = onRestoreEncryptedBackup)
    }
    YouPanel {
        AnkyActionButton(stringResource(R.string.export_backup_zip), onClick = onExport)
        when (exportBackupAction(state)) {
            ExportBackupAction.Share -> AnkyActionButton(stringResource(R.string.share_backup_zip), onClick = onShareBackup)
            ExportBackupAction.Empty -> DisabledRow(stringResource(R.string.no_local_data_to_back_up_yet))
        }
        AnkyActionButton(stringResource(R.string.restore_backup), onClick = onRestore)
    }
    YouDangerPanel {
        Text(stringResource(R.string.danger_zone), style = AnkyType.Heading.copy(fontSize = 18.sp, color = YouLz.danger))
        Text(stringResource(R.string.you_delete_local_data_body), style = AnkyType.Body.copy(fontSize = 14.sp, color = YouLz.paperMuted))
        AnkyActionButton(stringResource(R.string.delete_local_data), destructive = true, onClick = onDeleteLocalData)
    }
}

/**
 * The subscription status page — port of the iOS settings subscription
 * section: honest status, renewal truth, Google Play as the single manage
 * surface, and a user-triggered RevenueCat restore.
 */
@Composable
private fun SubscriptionPage(
    state: YouState,
    onRestorePurchases: () -> Unit,
    onManageSubscription: () -> Unit,
    onFounderChat: () -> Unit,
) {
    YouPanel {
        Text(stringResource(R.string.you_subscription), style = AnkyType.Caption.copy(color = YouLz.gold))
        Text(
            subscriptionStatusTitle(state.subscription),
            style = AnkyType.Body.copy(
                fontSize = 20.sp,
                fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold,
                color = YouLz.paper,
            ),
        )
        Text(
            subscriptionStatusDetail(state.subscription, state.isSubscriptionTruthAvailable),
            style = AnkyType.Body.copy(fontSize = 14.sp, color = YouLz.paperMuted),
        )
    }
    YouPanel {
        AnkyActionButton(stringResource(R.string.you_subscription_manage), onClick = onManageSubscription)
        Text(stringResource(R.string.you_subscription_manage_note), style = AnkyType.Body.copy(fontSize = 14.sp, color = YouLz.paperMuted))
        AnkyActionButton(
            if (state.isRestoringPurchases) stringResource(R.string.restoring_purchases) else stringResource(R.string.restore_purchases),
            enabled = !state.isRestoringPurchases,
            onClick = onRestorePurchases,
        )
        Text(stringResource(R.string.you_subscription_restore_note), style = AnkyType.Body.copy(fontSize = 14.sp, color = YouLz.paperMuted))
    }
    YouPanel {
        AnkyActionButton(stringResource(R.string.you_founder_chat), onClick = onFounderChat)
        Text(stringResource(R.string.you_founder_chat_subtitle), style = AnkyType.Body.copy(fontSize = 14.sp, color = YouLz.paperMuted))
    }
}

@Composable
private fun YouDangerPanel(content: @Composable () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(18.dp))
            .background(YouLz.danger.copy(alpha = 0.10f))
            .border(1.dp, YouLz.danger.copy(alpha = 0.30f), RoundedCornerShape(18.dp))
            .padding(horizontal = 16.dp, vertical = 14.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
        content = { content() },
    )
}

@Composable
private fun DisabledRow(text: String) {
    Text(
        text,
        style = AnkyType.Body.copy(fontSize = 14.sp, color = YouLz.paperMuted),
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .background(YouLz.panelStrong.copy(alpha = 0.72f))
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
private fun DeveloperPage(
    mirrorUrl: String,
    onMirrorUrl: (String) -> Unit,
    onSaveMirrorUrl: () -> Unit,
    onRepairMapIndex: () -> Unit,
    onClearReflections: () -> Unit,
    onClearArchive: () -> Unit,
    onResetIdentity: () -> Unit,
) {
    YouPanel {
        OutlinedTextField(
            value = mirrorUrl,
            onValueChange = onMirrorUrl,
            textStyle = AnkyType.Mono.copy(color = YouLz.paper),
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri),
            label = { Text(stringResource(R.string.mirror_base_url)) },
            modifier = Modifier.fillMaxWidth(),
        )
        Text(stringResource(R.string.mirror_base_url_help), style = AnkyType.Body.copy(fontSize = 14.sp, color = YouLz.paperMuted))
        AnkyActionButton(stringResource(R.string.save_mirror_url), onClick = onSaveMirrorUrl)
        AnkyActionButton(stringResource(R.string.repair_map_index), onClick = onRepairMapIndex)
    }
    YouPanel {
        AnkyActionButton(stringResource(R.string.clear_local_reflections_action), destructive = true, onClick = onClearReflections)
        AnkyActionButton(stringResource(R.string.clear_local_anky_archive_action), destructive = true, onClick = onClearArchive)
        AnkyActionButton(stringResource(R.string.reset_identity_action), destructive = true, onClick = onResetIdentity)
    }
}

@Composable
private fun SwitchRow(label: String, checked: Boolean, onChecked: (Boolean) -> Unit) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
        Text(label, style = AnkyType.Body.copy(fontSize = 16.sp, color = YouLz.paper), modifier = Modifier.weight(1f))
        Switch(checked = checked, onCheckedChange = onChecked)
    }
}

@Composable private fun DetailRow(title: String, value: String) = Row(Modifier.fillMaxWidth()) { Text(title, style = AnkyType.Caption.copy(color = YouLz.gold)); Spacer(Modifier.weight(1f)); Text(value, style = AnkyType.Body.copy(fontSize = 14.sp, color = YouLz.paper)) }
@Composable internal fun Rule(text: String) = Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) { Box(Modifier.size(5.dp).clip(CircleShape).background(YouLz.gold.copy(alpha = 0.72f))); Text(text, style = AnkyType.Body.copy(color = YouLz.paperMuted)) }
@Composable private fun Divider() = Box(Modifier.fillMaxWidth().height(1.dp).background(YouLz.hairline))
@Composable private fun VerticalDivider() = Box(Modifier.height(52.dp).size(width = 1.dp, height = 52.dp).background(YouLz.hairline))

@Composable
private fun MarkdownArticleText(text: String) {
    Text(markdownLinks(text), style = AnkyType.Body.copy(color = YouLz.paper))
}

@Composable
internal fun ArticleBodyText(text: String) {
    text.trimIndent()
        .split(Regex("\\n\\s*\\n"))
        .map { it.trim() }
        .filter { it.isNotEmpty() }
        .forEach { paragraph ->
            when {
                paragraph.startsWith("### ") -> {
                    Text(paragraph.removePrefix("### "), style = AnkyType.Body.copy(fontSize = 15.sp, fontWeight = FontWeight.Bold, color = YouLz.gold), modifier = Modifier.padding(top = 2.dp))
                }
                paragraph.startsWith("## ") -> {
                    Text(paragraph.removePrefix("## "), style = AnkyType.Heading.copy(fontSize = 21.sp, color = YouLz.paper), modifier = Modifier.padding(top = 4.dp))
                }
                paragraph.startsWith("> ") -> {
                    Text(
                        markdownLinks(paragraph.lines().joinToString(" ") { it.removePrefix("> ").removePrefix(">").trim() }),
                        style = AnkyType.Body.copy(fontSize = 16.sp, fontWeight = FontWeight.SemiBold, color = YouLz.paper),
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(8.dp))
                            .background(YouLz.gold.copy(alpha = 0.08f))
                            .padding(14.dp),
                    )
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
                    style = SpanStyle(color = YouLz.gold, textDecoration = TextDecoration.Underline),
                    pressedStyle = SpanStyle(color = YouLz.gold.copy(alpha = 0.7f), textDecoration = TextDecoration.Underline),
                ),
            ),
        )
        withStyle(SpanStyle(color = YouLz.gold, textDecoration = TextDecoration.Underline)) {
            append(label)
        }
        pop()
        index = urlEnd + 1
    }
}

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
    Subscription(R.string.you_subscription, R.string.you_subscription_page_subtitle),
    Settings(R.string.you_customize_row_title, R.string.you_customize_row_subtitle),
    Developer(R.string.you_developer_title, R.string.you_developer_subtitle),
}

private fun YouInitialPage.toYouPage(): YouPage =
    when (this) {
        // The credits page is gone; the old deep link lands on subscription truth.
        YouInitialPage.Credits -> YouPage.Subscription
    }

private enum class YouPrompt {
    Identity,
    Privacy,
    Export,
    Support,
    Developer,
}

@Composable
private fun localizedYouPromptMessage(prompt: YouPrompt): String =
    when (prompt) {
        YouPrompt.Identity -> stringResource(R.string.you_prompt_identity)
        YouPrompt.Privacy -> stringResource(R.string.you_prompt_privacy)
        YouPrompt.Export -> stringResource(R.string.you_prompt_export)
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
    activePrompt == YouPrompt.Export && state.isEncryptedBackupWorking

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

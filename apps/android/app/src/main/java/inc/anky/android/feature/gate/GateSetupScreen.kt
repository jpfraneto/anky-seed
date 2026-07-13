package inc.anky.android.feature.gate

import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CheckboxDefaults
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import androidx.core.graphics.drawable.toBitmap
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import inc.anky.android.R
import inc.anky.android.core.copy.AnkyCopyRegistry
import inc.anky.android.core.gate.runtime.BlockedApp
import inc.anky.android.core.gate.runtime.GateRuntime
import inc.anky.android.core.gate.runtime.GateRuntimeController
import inc.anky.android.core.gate.runtime.UsageAccess
import inc.anky.android.ui.lazure.AnkySunGlyph
import inc.anky.android.ui.lazure.LazureMood
import inc.anky.android.ui.lazure.LazurePigments
import inc.anky.android.ui.lazure.LazureWall
import inc.anky.android.ui.lazure.ThreadButton
import inc.anky.android.ui.lazure.WashButton
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * User-facing Write Before Scroll setup — port of iOS `GateSetupView`, with
 * the Screen Time authorization step replaced by Android's permission
 * funnel. Four steps, one line, one image, one action; the single button
 * always does the next needed thing.
 *
 *   authorize   → usage access (+ display-over-apps on Android 10+) as the
 *                 required pair; notifications and the battery-optimization
 *                 exemption as honest, optional rows (the "OEM reality").
 *   chooseApps  → installed-launcher-apps picker (Android's
 *                 FamilyActivityPicker), writing [BlockedAppSelectionStore].
 *   turnOn      → arm the gate (forceLock + watcher service).
 *   done        → summary + the honest exit: "turn the gate off", one
 *                 confirmation, no dark patterns in either direction.
 */
@Composable
fun GateSetupScreen(onDone: () -> Unit) {
    val context = LocalContext.current
    val runtime = remember(context) { GateRuntime(context) }

    var refreshTick by remember { mutableIntStateOf(0) }
    fun refresh() {
        refreshTick += 1
    }

    // Re-check permissions and state whenever we come back from Settings.
    val lifecycleOwner = LocalLifecycleOwner.current
    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) refreshTick += 1
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }

    val usageGranted = remember(refreshTick) { UsageAccess.hasUsageAccess(context) }
    val overlayGranted = remember(refreshTick) { Settings.canDrawOverlays(context) }
    val notificationsGranted = remember(refreshTick) { hasNotificationPermission(context) }
    val batteryExempt = remember(refreshTick) { isIgnoringBatteryOptimizations(context) }
    val overlayRequired = Build.VERSION.SDK_INT >= 29
    val authorized = usageGranted && (!overlayRequired || overlayGranted)

    val selection = remember(refreshTick) { runtime.selectionStore.load() }
    val gateState = remember(refreshTick) { runtime.stateStore.load() }
    val isGateOff = remember(refreshTick) { runtime.gateSwitchStore.isGateOff }

    val step = when {
        !authorized -> SetupStep.Authorize
        selection.isEmpty() -> SetupStep.ChooseApps
        isGateOff || !gateState.shieldActive -> SetupStep.TurnOn
        else -> SetupStep.Done
    }

    var showsPicker by remember { mutableStateOf(false) }
    var confirmsGateOff by remember { mutableStateOf(false) }

    val notificationLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { refresh() }

    if (showsPicker) {
        BlockedAppPicker(
            initiallySelected = selection,
            onSave = { chosen ->
                GateRuntimeController.saveSelection(context, chosen)
                showsPicker = false
                refresh()
            },
            onDismiss = { showsPicker = false },
        )
        return
    }

    Box(Modifier.fillMaxSize()) {
        LazureWall(mood = LazureMood.Dawn)

        Column(
            modifier = Modifier
                .fillMaxSize()
                .statusBarsPadding()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 40.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(22.dp),
        ) {
            Spacer(Modifier.height(24.dp))

            AnkySunGlyph(size = 96.dp)

            Text(
                text = stringResource(R.string.gate_setup_title),
                fontFamily = FontFamily.Serif,
                fontWeight = FontWeight.SemiBold,
                fontSize = 30.sp,
                lineHeight = 38.sp,
                color = LazurePigments.ankyInk,
                textAlign = TextAlign.Center,
            )

            Text(
                text = when (step) {
                    SetupStep.Authorize -> stringResource(R.string.gate_setup_caption_authorize)
                    SetupStep.ChooseApps -> stringResource(R.string.gate_setup_caption_choose)
                    SetupStep.TurnOn ->
                        if (isGateOff) {
                            AnkyCopyRegistry.gateOffStandingCaption
                        } else {
                            stringResource(R.string.gate_setup_caption_turn_on)
                        }
                    SetupStep.Done -> stringResource(R.string.gate_setup_caption_done)
                },
                fontFamily = FontFamily.Serif,
                fontSize = 15.sp,
                lineHeight = 22.sp,
                color = LazurePigments.ankyInkSoft,
                textAlign = TextAlign.Center,
            )

            if (step == SetupStep.Authorize) {
                PermissionFunnel(
                    usageGranted = usageGranted,
                    overlayGranted = overlayGranted,
                    overlayRequired = overlayRequired,
                    notificationsGranted = notificationsGranted,
                    batteryExempt = batteryExempt,
                    onRequestNotifications = {
                        if (Build.VERSION.SDK_INT >= 33) {
                            notificationLauncher.launch(android.Manifest.permission.POST_NOTIFICATIONS)
                        }
                    },
                )
            } else {
                SelectedAppsPanel(
                    selection = selection,
                    onChange = { showsPicker = true },
                )
            }

            ThreadButton(
                text = when (step) {
                    SetupStep.Authorize ->
                        if (!usageGranted) {
                            stringResource(R.string.gate_setup_button_allow_usage)
                        } else {
                            stringResource(R.string.gate_setup_button_allow_overlay)
                        }
                    SetupStep.ChooseApps -> stringResource(R.string.gate_setup_button_choose_apps)
                    SetupStep.TurnOn -> stringResource(R.string.gate_setup_button_turn_on)
                    SetupStep.Done -> stringResource(R.string.gate_setup_button_done)
                },
                onClick = {
                    when (step) {
                        SetupStep.Authorize ->
                            if (!usageGranted) {
                                openUsageAccessSettings(context)
                            } else {
                                openOverlaySettings(context)
                            }
                        SetupStep.ChooseApps -> showsPicker = true
                        SetupStep.TurnOn -> {
                            GateRuntimeController.turnGateOn(context)
                            refresh()
                        }
                        SetupStep.Done -> onDone()
                    }
                },
                modifier = Modifier.fillMaxWidth(),
            )

            if (step != SetupStep.Done) {
                QuietLink(text = stringResource(R.string.gate_setup_later), onClick = onDone)
            }

            // The honest exit (2026-07-06): one control, one confirmation.
            if (step == SetupStep.Done) {
                QuietLink(
                    text = AnkyCopyRegistry.gateOffLink,
                    onClick = { confirmsGateOff = true },
                )
            }

            Spacer(Modifier.height(26.dp))
        }
    }

    if (confirmsGateOff) {
        AlertDialog(
            onDismissRequest = { confirmsGateOff = false },
            title = { Text(AnkyCopyRegistry.gateOffConfirmTitle) },
            text = { Text(AnkyCopyRegistry.gateOffConfirmBody) },
            confirmButton = {
                TextButton(
                    onClick = {
                        confirmsGateOff = false
                        GateRuntimeController.turnGateOff(context)
                        refresh()
                    },
                ) {
                    Text(AnkyCopyRegistry.gateOffConfirm, color = LazurePigments.ankyMadder)
                }
            },
            dismissButton = {
                TextButton(onClick = { confirmsGateOff = false }) {
                    Text(AnkyCopyRegistry.gateOffCancel)
                }
            },
            containerColor = LazurePigments.ankyPaper,
            titleContentColor = LazurePigments.ankyInk,
            textContentColor = LazurePigments.ankyInkSoft,
        )
    }
}

private enum class SetupStep { Authorize, ChooseApps, TurnOn, Done }

// MARK: - Authorize step

@Composable
private fun PermissionFunnel(
    usageGranted: Boolean,
    overlayGranted: Boolean,
    overlayRequired: Boolean,
    notificationsGranted: Boolean,
    batteryExempt: Boolean,
    onRequestNotifications: () -> Unit,
) {
    val context = LocalContext.current
    Panel {
        PermissionRow(
            title = stringResource(R.string.gate_setup_permission_usage),
            caption = stringResource(R.string.gate_setup_permission_usage_caption),
            granted = usageGranted,
            onClick = { openUsageAccessSettings(context) },
        )
        PermissionRow(
            title = stringResource(R.string.gate_setup_permission_overlay),
            caption = stringResource(
                if (overlayRequired) {
                    R.string.gate_setup_permission_overlay_caption
                } else {
                    R.string.gate_setup_permission_optional_caption
                },
            ),
            granted = overlayGranted,
            onClick = { openOverlaySettings(context) },
        )
        PermissionRow(
            title = stringResource(R.string.gate_setup_permission_notifications),
            caption = stringResource(R.string.gate_setup_permission_notifications_caption),
            granted = notificationsGranted,
            onClick = onRequestNotifications,
        )
        PermissionRow(
            title = stringResource(R.string.gate_setup_permission_battery),
            caption = stringResource(R.string.gate_setup_permission_battery_caption),
            granted = batteryExempt,
            onClick = { requestBatteryExemption(context) },
        )
    }
}

@Composable
private fun PermissionRow(
    title: String,
    caption: String,
    granted: Boolean,
    onClick: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
                enabled = !granted,
                onClick = onClick,
            )
            .padding(vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = if (granted) "◉" else "○",
            fontSize = 16.sp,
            color = if (granted) LazurePigments.ankyGold else LazurePigments.ankyInkSoft.copy(alpha = 0.5f),
        )
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(
                text = title,
                fontSize = 14.sp,
                fontWeight = FontWeight.SemiBold,
                color = LazurePigments.ankyInk,
            )
            Text(
                text = caption,
                fontSize = 12.sp,
                lineHeight = 16.sp,
                color = LazurePigments.ankyInkSoft,
            )
        }
    }
}

// MARK: - Selected apps panel (iOS `selectedAppsPanel`)

@Composable
private fun SelectedAppsPanel(
    selection: List<BlockedApp>,
    onChange: () -> Unit,
) {
    Panel {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                text = stringResource(R.string.gate_setup_blocked_apps),
                fontSize = 14.sp,
                fontWeight = FontWeight.SemiBold,
                color = LazurePigments.ankyInk,
            )
            Spacer(Modifier.weight(1f))
            Text(
                text = stringResource(
                    if (selection.isEmpty()) R.string.gate_setup_choose else R.string.gate_setup_change,
                ),
                fontSize = 13.sp,
                fontWeight = FontWeight.SemiBold,
                color = LazurePigments.ankyViolet,
                modifier = Modifier.clickable(
                    interactionSource = remember { MutableInteractionSource() },
                    indication = null,
                    onClick = onChange,
                ),
            )
        }

        if (selection.isEmpty()) {
            Text(
                text = stringResource(R.string.gate_setup_choose_empty),
                fontSize = 12.sp,
                lineHeight = 17.sp,
                color = LazurePigments.ankyInkSoft,
            )
        } else {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                selection.take(5).forEach { app ->
                    BlockedAppIcon(app = app, size = 48.dp)
                }
            }
            Text(
                text = stringResource(R.string.gate_setup_selected_status, selection.size),
                fontSize = 12.sp,
                fontWeight = FontWeight.Medium,
                color = LazurePigments.ankyInkSoft,
            )
        }
    }
}

@Composable
private fun Panel(content: @Composable ColumnScope.() -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .widthIn(max = 620.dp)
            .clip(RoundedCornerShape(18.dp))
            .background(LazurePigments.ankyPaper.copy(alpha = 0.58f))
            .border(0.5.dp, LazurePigments.ankyInk.copy(alpha = 0.08f), RoundedCornerShape(18.dp))
            .padding(18.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
        content = content,
    )
}

@Composable
private fun QuietLink(text: String, onClick: () -> Unit) {
    Text(
        text = text,
        fontSize = 14.sp,
        fontWeight = FontWeight.Medium,
        color = LazurePigments.ankyInkSoft.copy(alpha = 0.8f),
        modifier = Modifier
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
                onClick = onClick,
            )
            .padding(horizontal = 12.dp, vertical = 6.dp),
    )
}

// MARK: - App picker (Android's FamilyActivityPicker)

private data class InstalledApp(
    val packageName: String,
    val label: String,
    val curatedIconRes: Int?,
)

@Composable
private fun BlockedAppPicker(
    initiallySelected: List<BlockedApp>,
    onSave: (List<BlockedApp>) -> Unit,
    onDismiss: () -> Unit,
) {
    val context = LocalContext.current
    var installed by remember { mutableStateOf<List<InstalledApp>?>(null) }
    var query by remember { mutableStateOf("") }
    val checked = remember { mutableStateOf<Set<String>>(emptySet()) }

    LaunchedEffect(Unit) {
        val apps = loadInstalledApps(context)
        installed = apps
        checked.value = if (initiallySelected.isNotEmpty()) {
            initiallySelected.mapTo(mutableSetOf()) { it.packageName }
        } else {
            // First visit: preselect the common social apps actually present.
            apps.asSequence()
                .map { it.packageName }
                .filter { it in BlockedAppIconCatalog.preselectedPackages }
                .toSet()
        }
    }

    Box(Modifier.fillMaxSize()) {
        LazureWall(mood = LazureMood.Dawn)

        Column(
            modifier = Modifier
                .fillMaxSize()
                .statusBarsPadding()
                .padding(horizontal = 24.dp),
        ) {
            Spacer(Modifier.height(16.dp))

            Text(
                text = stringResource(R.string.gate_picker_header),
                fontFamily = FontFamily.Serif,
                fontWeight = FontWeight.SemiBold,
                fontSize = 22.sp,
                lineHeight = 29.sp,
                color = LazurePigments.ankyInk,
            )
            Spacer(Modifier.height(4.dp))
            Text(
                text = stringResource(R.string.gate_picker_footer),
                fontFamily = FontFamily.Serif,
                fontSize = 14.sp,
                color = LazurePigments.ankyInkSoft,
            )

            Spacer(Modifier.height(14.dp))

            OutlinedTextField(
                value = query,
                onValueChange = { query = it },
                singleLine = true,
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                placeholder = {
                    Text(
                        stringResource(R.string.gate_picker_search_hint),
                        color = LazurePigments.ankyInkSoft.copy(alpha = 0.6f),
                    )
                },
                colors = OutlinedTextFieldDefaults.colors(
                    focusedBorderColor = LazurePigments.ankyGold,
                    unfocusedBorderColor = LazurePigments.ankyInk.copy(alpha = 0.15f),
                    focusedTextColor = LazurePigments.ankyInk,
                    unfocusedTextColor = LazurePigments.ankyInk,
                    cursorColor = LazurePigments.ankyGold,
                ),
                shape = RoundedCornerShape(14.dp),
                modifier = Modifier.fillMaxWidth(),
            )

            Spacer(Modifier.height(10.dp))

            val apps = installed
            if (apps == null) {
                Box(Modifier.weight(1f))
            } else {
                val filtered = remember(apps, query) {
                    val needle = query.trim().lowercase()
                    if (needle.isEmpty()) {
                        apps
                    } else {
                        apps.filter {
                            it.label.lowercase().contains(needle) ||
                                it.packageName.lowercase().contains(needle)
                        }
                    }
                }
                LazyColumn(Modifier.weight(1f)) {
                    items(filtered, key = { it.packageName }) { app ->
                        AppPickerRow(
                            app = app,
                            checked = app.packageName in checked.value,
                            onToggle = {
                                checked.value = if (app.packageName in checked.value) {
                                    checked.value - app.packageName
                                } else {
                                    checked.value + app.packageName
                                }
                            },
                        )
                    }
                }
            }

            Spacer(Modifier.height(10.dp))

            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                WashButton(
                    text = stringResource(R.string.gate_picker_cancel),
                    onClick = onDismiss,
                    modifier = Modifier.weight(1f),
                )
                ThreadButton(
                    text = stringResource(R.string.gate_picker_save),
                    onClick = {
                        val byPackage = (installed ?: emptyList()).associateBy { it.packageName }
                        val chosen = checked.value.mapNotNull { packageName ->
                            byPackage[packageName]?.let { BlockedApp(packageName, it.label) }
                        }
                        onSave(chosen)
                    },
                    modifier = Modifier.weight(1f),
                )
            }

            Spacer(Modifier.height(24.dp))
        }
    }
}

@Composable
private fun AppPickerRow(
    app: InstalledApp,
    checked: Boolean,
    onToggle: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
                onClick = onToggle,
            )
            .padding(vertical = 6.dp, horizontal = 2.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        BlockedAppIcon(
            app = BlockedApp(app.packageName, app.label),
            size = 40.dp,
            curatedIconRes = app.curatedIconRes,
        )
        Spacer(Modifier.width(14.dp))
        Text(
            text = app.label,
            fontSize = 15.sp,
            color = LazurePigments.ankyInk,
            modifier = Modifier.weight(1f),
        )
        Checkbox(
            checked = checked,
            onCheckedChange = { onToggle() },
            colors = CheckboxDefaults.colors(
                checkedColor = LazurePigments.ankyGold,
                checkmarkColor = LazurePigments.ankyInk,
                uncheckedColor = LazurePigments.ankyInkSoft.copy(alpha = 0.5f),
            ),
        )
    }
}

/** Curated `blocked_*` art when we have it; the app's real icon otherwise. */
@Composable
private fun BlockedAppIcon(
    app: BlockedApp,
    size: androidx.compose.ui.unit.Dp,
    curatedIconRes: Int? = BlockedAppIconCatalog.iconResFor(app.packageName, app.label),
) {
    val shape = RoundedCornerShape(12.dp)
    val modifier = Modifier
        .size(size)
        .clip(shape)
        .border(0.5.dp, LazurePigments.ankyInk.copy(alpha = 0.08f), shape)
    if (curatedIconRes != null) {
        Image(
            painter = painterResource(curatedIconRes),
            contentDescription = app.label,
            modifier = modifier,
        )
    } else {
        val context = LocalContext.current
        val icon = remember(app.packageName) {
            runCatching {
                context.packageManager.getApplicationIcon(app.packageName)
                    .toBitmap(width = 96, height = 96)
                    .asImageBitmap()
            }.getOrNull()
        }
        if (icon != null) {
            Image(bitmap = icon, contentDescription = app.label, modifier = modifier)
        } else {
            Box(
                modifier = modifier.background(LazurePigments.ankyPaperDeep),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    text = app.label.take(1).uppercase(),
                    color = LazurePigments.ankyInkSoft,
                    fontWeight = FontWeight.SemiBold,
                )
            }
        }
    }
}

// MARK: - Platform helpers

private suspend fun loadInstalledApps(context: Context): List<InstalledApp> =
    withContext(Dispatchers.IO) {
        val packageManager = context.packageManager
        val launcherIntent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        packageManager.queryIntentActivities(launcherIntent, 0)
            .asSequence()
            .distinctBy { it.activityInfo.packageName }
            .filter { it.activityInfo.packageName != context.packageName }
            .map { resolveInfo ->
                val packageName = resolveInfo.activityInfo.packageName
                val label = resolveInfo.loadLabel(packageManager).toString()
                InstalledApp(
                    packageName = packageName,
                    label = label,
                    curatedIconRes = BlockedAppIconCatalog.iconResFor(packageName, label),
                )
            }
            .sortedWith(
                compareByDescending<InstalledApp> { it.curatedIconRes != null }
                    .thenBy { it.label.lowercase() },
            )
            .toList()
    }

private fun hasNotificationPermission(context: Context): Boolean =
    Build.VERSION.SDK_INT < 33 ||
        ContextCompat.checkSelfPermission(
            context,
            android.Manifest.permission.POST_NOTIFICATIONS,
        ) == android.content.pm.PackageManager.PERMISSION_GRANTED

private fun isIgnoringBatteryOptimizations(context: Context): Boolean =
    (context.getSystemService(Context.POWER_SERVICE) as PowerManager)
        .isIgnoringBatteryOptimizations(context.packageName)

private fun openUsageAccessSettings(context: Context) {
    runCatching {
        context.startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS))
    }
}

private fun openOverlaySettings(context: Context) {
    runCatching {
        context.startActivity(
            Intent(
                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                Uri.parse("package:${context.packageName}"),
            ),
        )
    }
}

@SuppressLint("BatteryLife") // The "OEM reality": the watcher dies without it on aggressive battery managers.
private fun requestBatteryExemption(context: Context) {
    runCatching {
        context.startActivity(
            Intent(
                Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                Uri.parse("package:${context.packageName}"),
            ),
        )
    }
}

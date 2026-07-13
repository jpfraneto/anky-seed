package inc.anky.android.feature.settings

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ChevronLeft
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Slider
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import inc.anky.android.R
import inc.anky.android.core.copy.AnkyCopyRegistry
import inc.anky.android.core.gate.DailyTargetStore
import inc.anky.android.core.gate.GateStateStore
import inc.anky.android.core.gate.GateStorage
import inc.anky.android.core.gate.WriteBeforeScrollEventLogStore
import inc.anky.android.core.gate.WriteBeforeScrollEventName
import inc.anky.android.core.gate.WriteBeforeScrollGateSwitchStore
import inc.anky.android.core.gate.WritingAnchorStore
import inc.anky.android.core.storage.AnkyWritingFontChoice
import inc.anky.android.core.storage.AnkyWritingTextSize
import inc.anky.android.core.storage.WritingPreferences
import inc.anky.android.core.storage.WritingPreferencesStore
import inc.anky.android.feature.you.PrivacyPage
import inc.anky.android.feature.you.TermsPage
import inc.anky.android.ui.lazure.AnkySunGlyph
import inc.anky.android.ui.lazure.LazureDivider
import inc.anky.android.ui.lazure.LazureMood
import inc.anky.android.ui.lazure.LazurePigments
import inc.anky.android.ui.lazure.LazureType
import inc.anky.android.ui.lazure.LazureWall
import inc.anky.android.ui.lazure.VeilCard
import inc.anky.android.ui.lazure.fontFamilyFor
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale

/**
 * "Customize your Anky experience" — port of iOS `AnkySettingsView.swift`:
 * one lazure scroll of translucent veils holding everything the writer can
 * tune, with the ritual as the clear default.
 *
 * Self-contained: writing preferences, the daily target, the writer's name,
 * and the gate off-switch read/write their own context-backed stores; every
 * state that belongs to the wider app (app lock, encrypted backup, mirror
 * URL, subscription truth) arrives as parameters with callbacks.
 */
@Composable
fun AnkySettingsScreen(
    appLockEnabled: Boolean,
    canUseAppLock: Boolean,
    onAppLockChange: (Boolean) -> Unit,
    isEncryptedBackupEnabled: Boolean,
    encryptedBackupLastDate: Instant?,
    onEncryptedBackupToggle: (Boolean) -> Unit,
    mirrorBaseUrl: String,
    onMirrorBaseUrlSave: (String) -> Unit,
    subscriptionTitle: String,
    subscriptionDetail: String,
    isSubscriptionEntitled: Boolean,
    isRestoringSubscription: Boolean,
    restoreStatusLine: String?,
    onRestoreSubscription: () -> Unit,
    onManageSubscription: () -> Unit,
    onGateSetupRequested: () -> Unit,
    onFounderChat: () -> Unit,
    onContactSupport: () -> Unit,
    onClearLocalData: () -> Unit,
    appVersion: String,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val gatePreferences = remember(context) { GateStorage.preferences(context) }
    val writingPreferencesStore = remember(context) { WritingPreferencesStore(context) }
    val dailyTargetStore = remember(gatePreferences) { DailyTargetStore(gatePreferences) }
    val anchorStore = remember(gatePreferences) { WritingAnchorStore(gatePreferences) }
    val gateSwitchStore = remember(gatePreferences) { WriteBeforeScrollGateSwitchStore(gatePreferences) }
    val gateStateStore = remember(gatePreferences) { GateStateStore(gatePreferences) }
    val eventLog = remember(gatePreferences) { WriteBeforeScrollEventLogStore(gatePreferences) }

    var writingPreferences by remember { mutableStateOf(writingPreferencesStore.load()) }
    var writerName by remember { mutableStateOf(anchorStore.writerName.orEmpty()) }
    var effectiveTargetMinutes by remember { mutableIntStateOf(DailyTargetStore.DefaultMinutes) }
    var pendingTargetMinutes by remember { mutableStateOf<Int?>(null) }
    var sliderMinutes by remember { mutableStateOf(DailyTargetStore.DefaultMinutes.toFloat()) }
    var isGateOff by remember { mutableStateOf(gateSwitchStore.isGateOff) }
    var blockedAppCount by remember { mutableIntStateOf(0) }
    var mirrorUrlInput by remember(mirrorBaseUrl) { mutableStateOf(mirrorBaseUrl) }
    var showsPrivacy by remember { mutableStateOf(false) }
    var showsTerms by remember { mutableStateOf(false) }

    fun refreshGateSection() {
        effectiveTargetMinutes = dailyTargetStore.effectiveTargetMinutes()
        pendingTargetMinutes = dailyTargetStore.pendingTargetMinutes()
        sliderMinutes = (pendingTargetMinutes ?: effectiveTargetMinutes).toFloat()
        isGateOff = gateSwitchStore.isGateOff
        blockedAppCount = gateStateStore.load().selectedApplicationCount
    }
    LaunchedEffect(Unit) {
        writingPreferences = writingPreferencesStore.load()
        writerName = anchorStore.writerName.orEmpty()
        refreshGateSection()
    }

    fun saveWritingPreferences(updated: WritingPreferences) {
        writingPreferences = updated
        writingPreferencesStore.save(updated)
    }

    fun commitDailyTarget() {
        val change = dailyTargetStore.requestTargetChange(sliderMinutes.toInt())
        eventLog.append(
            WriteBeforeScrollEventName.TargetChanged,
            metadata = mapOf(
                "oldMinutes" to "${change.oldMinutes}",
                "newMinutes" to "${change.newMinutes}",
            ),
        )
        refreshGateSection()
    }

    Box(modifier.fillMaxSize().testTag("anky-settings")) {
        LazureWall(mood = LazureMood.Dawn, modifier = Modifier.fillMaxSize())

        if (showsPrivacy || showsTerms) {
            SettingsArticleOverlay(onBack = {
                showsPrivacy = false
                showsTerms = false
            }) {
                if (showsPrivacy) PrivacyPage() else TermsPage()
            }
            return@Box
        }

        Column(Modifier.fillMaxSize()) {
            Row(
                Modifier.fillMaxWidth().padding(horizontal = 18.dp).padding(top = 56.dp, bottom = 6.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                SettingsBackButton(onBack)
                Spacer(Modifier.weight(1f))
            }
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = 20.dp)
                    .padding(bottom = 120.dp),
                verticalArrangement = Arrangement.spacedBy(26.dp),
            ) {
                Text(
                    stringResource(R.string.you_customize_row_title),
                    style = LazureType.ankyTitle.copy(fontSize = 30.sp, color = SettingsInk.text),
                    modifier = Modifier.padding(top = 8.dp, start = 4.dp, end = 4.dp),
                )

                SettingsSection(title = stringResource(R.string.you_subscription)) {
                    VeilCard {
                        Row(verticalAlignment = Alignment.Top) {
                            AnkySunGlyph(
                                size = 24.dp,
                                color = if (isSubscriptionEntitled) LazurePigments.ankyGold else LazurePigments.ankyInkSoft,
                            )
                            Column(Modifier.weight(1f).padding(start = 14.dp), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                                Text(subscriptionTitle, style = LazureType.ankyLabel.copy(color = SettingsInk.text))
                                Text(subscriptionDetail, style = LazureType.ankyCaption.copy(color = SettingsInk.textMuted))
                            }
                            Icon(
                                imageVector = Icons.Filled.ChevronRight,
                                contentDescription = null,
                                tint = SettingsInk.textMuted.copy(alpha = 0.75f),
                                modifier = Modifier.size(16.dp).clickable(onClick = onManageSubscription),
                            )
                        }
                        LazureDivider(Modifier.padding(vertical = 12.dp))
                        Text(
                            if (isRestoringSubscription) {
                                stringResource(R.string.restoring_purchases)
                            } else {
                                stringResource(R.string.restore_purchases)
                            },
                            style = LazureType.ankyCaption.copy(fontSize = 13.sp, color = LazurePigments.ankySlate),
                            modifier = Modifier.clickable(enabled = !isRestoringSubscription, onClick = onRestoreSubscription),
                        )
                        restoreStatusLine?.let { line ->
                            Text(
                                line,
                                style = LazureType.ankyCaption.copy(color = SettingsInk.textMuted),
                                modifier = Modifier.padding(top = 6.dp),
                            )
                        }
                        Text(
                            stringResource(R.string.you_subscription_manage_note),
                            style = LazureType.ankyCaption.copy(color = SettingsInk.textMuted),
                            modifier = Modifier.padding(top = 6.dp),
                        )
                    }
                }

                SettingsSection(title = stringResource(R.string.settings_daily_writing_section)) {
                    VeilCard {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(
                                dailyTargetHeadline(
                                    minutes = sliderMinutes.toInt(),
                                    oneMinuteFormat = stringResource(R.string.settings_minutes_a_day_one),
                                    minutesFormat = stringResource(R.string.settings_minutes_a_day_other),
                                ),
                                style = LazureType.ankyHeading.copy(color = SettingsInk.text),
                                modifier = Modifier.weight(1f),
                            )
                            AnkySunGlyph(size = 22.dp, color = LazurePigments.ankyGold)
                        }
                        Slider(
                            value = sliderMinutes,
                            onValueChange = { sliderMinutes = it },
                            onValueChangeFinished = { commitDailyTarget() },
                            valueRange = DailyTargetStore.MinutesRange.first.toFloat()..DailyTargetStore.MinutesRange.last.toFloat(),
                            steps = DailyTargetStore.MinutesRange.last - DailyTargetStore.MinutesRange.first - 1,
                        )
                        Text(
                            dailyTargetFootnote(
                                effectiveMinutes = effectiveTargetMinutes,
                                pendingMinutes = pendingTargetMinutes,
                                defaultFootnote = stringResource(R.string.settings_daily_target_footnote_default),
                                pendingFootnoteFormat = stringResource(R.string.settings_daily_target_footnote_pending),
                            ),
                            style = LazureType.ankyCaption.copy(color = SettingsInk.textMuted),
                        )
                    }
                }

                SettingsSection(title = stringResource(R.string.settings_name_section)) {
                    VeilCard {
                        OutlinedTextField(
                            value = writerName,
                            onValueChange = { updated ->
                                writerName = updated
                                anchorStore.save(writerName = updated, anchorSentence = anchorStore.anchorSentence)
                            },
                            textStyle = LazureType.ankyProse.copy(color = SettingsInk.text),
                            placeholder = { Text(stringResource(R.string.settings_name_placeholder), style = LazureType.ankyProse.copy(color = SettingsInk.textMuted)) },
                            singleLine = true,
                            modifier = Modifier.fillMaxWidth(),
                        )
                    }
                }

                SettingsSection(title = stringResource(R.string.settings_writing_section)) {
                    VeilCard(padding = 0.dp) {
                        SettingsToggleRow(
                            title = stringResource(R.string.settings_backspace_title),
                            subtitle = stringResource(R.string.settings_backspace_subtitle),
                            checked = writingPreferences.backspaceAllowed,
                            onChecked = { saveWritingPreferences(writingPreferences.copy(backspaceAllowed = it)) },
                        )
                        LazureDivider(Modifier.padding(horizontal = 18.dp))
                        SettingsToggleRow(
                            title = stringResource(R.string.settings_autocorrect_title),
                            subtitle = stringResource(R.string.settings_autocorrect_subtitle),
                            checked = writingPreferences.autocorrectEnabled,
                            onChecked = { saveWritingPreferences(writingPreferences.copy(autocorrectEnabled = it)) },
                        )
                    }
                }

                SettingsSection(title = stringResource(R.string.settings_typeface_section)) {
                    VeilCard {
                        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                            AnkyWritingFontChoice.entries.forEach { choice ->
                                FontChip(
                                    choice = choice,
                                    isSelected = writingPreferences.fontChoice == choice,
                                    modifier = Modifier.weight(1f),
                                ) { saveWritingPreferences(writingPreferences.copy(fontChoice = choice)) }
                            }
                        }
                        Spacer(Modifier.size(14.dp))
                        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                            AnkyWritingTextSize.entries.forEach { textSize ->
                                SizeChip(
                                    textSize = textSize,
                                    isSelected = writingPreferences.textSize == textSize,
                                    modifier = Modifier.weight(1f),
                                ) { saveWritingPreferences(writingPreferences.copy(textSize = textSize)) }
                            }
                        }
                        LazureDivider(Modifier.padding(vertical = 14.dp))
                        Text(
                            stringResource(R.string.settings_typeface_preview),
                            style = LazureType.ankyProse.copy(
                                fontFamily = fontFamilyFor(writingPreferences.fontChoice.rawValue),
                                fontSize = writingPreferences.textSize.pointSize.sp,
                                lineHeight = (writingPreferences.textSize.pointSize * 1.42).sp,
                                color = SettingsInk.text,
                            ),
                            modifier = Modifier.fillMaxWidth(),
                        )
                    }
                }

                SettingsSection(title = stringResource(R.string.settings_protection_section)) {
                    VeilCard(padding = 0.dp) {
                        SettingsToggleRow(
                            title = stringResource(R.string.settings_backup_title),
                            subtitle = encryptedBackupSubtitle(
                                isEnabled = isEncryptedBackupEnabled,
                                lastBackupDate = encryptedBackupLastDate,
                                onLine = stringResource(R.string.settings_backup_subtitle_on),
                                offLine = stringResource(R.string.settings_backup_subtitle_off),
                                lastFormat = stringResource(R.string.settings_backup_last_format),
                            ),
                            checked = isEncryptedBackupEnabled,
                            onChecked = onEncryptedBackupToggle,
                        )
                        if (canUseAppLock) {
                            LazureDivider(Modifier.padding(horizontal = 18.dp))
                            SettingsToggleRow(
                                title = stringResource(R.string.settings_app_lock_title),
                                subtitle = stringResource(R.string.settings_app_lock_subtitle),
                                checked = appLockEnabled,
                                onChecked = onAppLockChange,
                            )
                        }
                        LazureDivider(Modifier.padding(horizontal = 18.dp))
                        SettingsNavigationRow(
                            title = stringResource(R.string.settings_blocked_apps_title),
                            subtitle = stringResource(R.string.settings_blocked_apps_subtitle),
                            onClick = onGateSetupRequested,
                        )
                        LazureDivider(Modifier.padding(horizontal = 18.dp))
                        Text(
                            gateStateLine(
                                isGateOff = isGateOff,
                                blockedAppCount = blockedAppCount,
                                offLine = stringResource(R.string.settings_gate_off_state),
                                noSelectionLine = stringResource(R.string.settings_gate_no_selection),
                                oneAppLine = stringResource(R.string.settings_gate_on_state_one),
                                manyAppsFormat = stringResource(R.string.settings_gate_on_state_other),
                            ),
                            style = LazureType.ankyCaption.copy(color = SettingsInk.textMuted),
                            modifier = Modifier.padding(18.dp),
                        )
                    }
                }

                SettingsSection(title = stringResource(R.string.settings_paintings_section)) {
                    VeilCard {
                        Text(
                            AnkyCopyRegistry.paintingDisclosure,
                            style = LazureType.ankyCaption.copy(fontSize = 13.sp, color = SettingsInk.textMuted, lineHeight = 18.sp),
                            modifier = Modifier.fillMaxWidth(),
                        )
                    }
                }

                SettingsSection(title = stringResource(R.string.settings_mirror_section)) {
                    VeilCard {
                        OutlinedTextField(
                            value = mirrorUrlInput,
                            onValueChange = { mirrorUrlInput = it },
                            textStyle = LazureType.ankyCaption.copy(fontSize = 13.sp, color = SettingsInk.text),
                            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri),
                            label = { Text(stringResource(R.string.mirror_base_url)) },
                            modifier = Modifier.fillMaxWidth(),
                        )
                        Text(
                            stringResource(R.string.mirror_base_url_help),
                            style = LazureType.ankyCaption.copy(color = SettingsInk.textMuted),
                            modifier = Modifier.padding(top = 8.dp),
                        )
                        Text(
                            stringResource(R.string.save_mirror_url),
                            style = LazureType.ankyLabel.copy(color = LazurePigments.ankySlate),
                            modifier = Modifier
                                .padding(top = 10.dp)
                                .clickable { onMirrorBaseUrlSave(mirrorUrlInput) },
                        )
                    }
                }

                SettingsSection(title = stringResource(R.string.settings_support_section)) {
                    VeilCard(padding = 0.dp) {
                        SettingsNavigationRow(
                            title = stringResource(R.string.you_founder_chat),
                            subtitle = stringResource(R.string.you_founder_chat_subtitle),
                            onClick = onFounderChat,
                        )
                        LazureDivider(Modifier.padding(horizontal = 18.dp))
                        SettingsNavigationRow(
                            title = stringResource(R.string.settings_contact_email_title),
                            subtitle = stringResource(R.string.settings_contact_email_subtitle),
                            onClick = onContactSupport,
                        )
                    }
                }

                SettingsSection(title = stringResource(R.string.settings_legal_section)) {
                    VeilCard(padding = 0.dp) {
                        SettingsNavigationRow(
                            title = stringResource(R.string.you_privacy_policy),
                            subtitle = stringResource(R.string.settings_privacy_subtitle),
                            onClick = { showsPrivacy = true },
                        )
                        LazureDivider(Modifier.padding(horizontal = 18.dp))
                        SettingsNavigationRow(
                            title = stringResource(R.string.you_terms_conditions),
                            subtitle = stringResource(R.string.settings_terms_subtitle),
                            onClick = { showsTerms = true },
                        )
                    }
                }

                SettingsSection(title = stringResource(R.string.danger_zone)) {
                    VeilCard {
                        Text(
                            stringResource(R.string.you_delete_local_data_body),
                            style = LazureType.ankyCaption.copy(color = SettingsInk.textMuted),
                        )
                        Text(
                            stringResource(R.string.delete_local_data),
                            style = LazureType.ankyLabel.copy(color = LazurePigments.ankyMadder),
                            modifier = Modifier
                                .padding(top = 10.dp)
                                .clickable(onClick = onClearLocalData),
                        )
                    }
                }

                SettingsSection(title = stringResource(R.string.settings_about_section)) {
                    VeilCard {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            AnkySunGlyph(size = 24.dp, color = LazurePigments.ankyViolet)
                            Column(Modifier.weight(1f).padding(start = 14.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                                Text(stringResource(R.string.app_name_anky), style = LazureType.ankyLabel.copy(color = SettingsInk.text))
                                Text(
                                    stringResource(R.string.you_app_version_format, appVersion),
                                    style = LazureType.ankyCaption.copy(color = SettingsInk.textMuted),
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

/** Ink roles on the paper wall. */
private object SettingsInk {
    val text = LazurePigments.ankyInk
    val textMuted = LazurePigments.ankyInkSoft
}

@Composable
private fun SettingsBackButton(onBack: () -> Unit) {
    val backLabel = stringResource(R.string.back)
    Box(
        modifier = Modifier
            .size(44.dp)
            .background(LazurePigments.ankyPaper.copy(alpha = 0.72f), CircleShape)
            .border(0.5.dp, LazurePigments.hairline, CircleShape)
            .clickable(onClick = onBack),
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            imageVector = Icons.Filled.ChevronLeft,
            contentDescription = backLabel,
            tint = SettingsInk.text,
            modifier = Modifier.size(24.dp),
        )
    }
}

@Composable
private fun SettingsArticleOverlay(onBack: () -> Unit, content: @Composable () -> Unit) {
    Column(Modifier.fillMaxSize()) {
        Row(
            Modifier.fillMaxWidth().padding(horizontal = 18.dp).padding(top = 56.dp, bottom = 6.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            SettingsBackButton(onBack)
            Spacer(Modifier.weight(1f))
        }
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp)
                .padding(bottom = 120.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            content()
        }
    }
}

@Composable
private fun SettingsSection(title: String, content: @Composable () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(
            title,
            style = LazureType.ankyHeading.copy(color = SettingsInk.text.copy(alpha = 0.85f)),
            modifier = Modifier.padding(horizontal = 4.dp),
        )
        content()
    }
}

@Composable
private fun SettingsToggleRow(
    title: String,
    subtitle: String,
    checked: Boolean,
    onChecked: (Boolean) -> Unit,
) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(18.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, style = LazureType.ankyLabel.copy(color = SettingsInk.text))
            Text(subtitle, style = LazureType.ankyCaption.copy(color = SettingsInk.textMuted), maxLines = 2, overflow = TextOverflow.Ellipsis)
        }
        Switch(checked = checked, onCheckedChange = onChecked)
    }
}

@Composable
private fun SettingsNavigationRow(
    title: String,
    subtitle: String,
    onClick: () -> Unit,
) {
    Row(
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick).padding(18.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, style = LazureType.ankyLabel.copy(color = SettingsInk.text))
            Text(subtitle, style = LazureType.ankyCaption.copy(color = SettingsInk.textMuted), maxLines = 2, overflow = TextOverflow.Ellipsis)
        }
        Icon(
            imageVector = Icons.Filled.ChevronRight,
            contentDescription = null,
            tint = SettingsInk.textMuted.copy(alpha = 0.7f),
            modifier = Modifier.size(16.dp),
        )
    }
}

@Composable
private fun FontChip(
    choice: AnkyWritingFontChoice,
    isSelected: Boolean,
    modifier: Modifier = Modifier,
    onSelect: () -> Unit,
) {
    Column(
        modifier = modifier
            .background(
                if (isSelected) LazurePigments.ankyGoldLight.copy(alpha = 0.6f) else LazurePigments.ankyPaper.copy(alpha = 0.4f),
                RoundedCornerShape(14.dp),
            )
            .border(
                0.5.dp,
                LazurePigments.ankyInk.copy(alpha = if (isSelected) 0.16f else 0.08f),
                RoundedCornerShape(14.dp),
            )
            .clickable(onClick = onSelect)
            .padding(vertical = 10.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(5.dp),
    ) {
        Text(
            "Aa",
            style = LazureType.ankyProse.copy(
                fontFamily = fontFamilyFor(choice.rawValue),
                fontSize = 21.sp,
                color = SettingsInk.text,
            ),
        )
        Text(
            choice.displayName,
            style = LazureType.ankyCaption.copy(fontSize = 10.sp, fontWeight = FontWeight.Medium, color = SettingsInk.textMuted),
            maxLines = 1,
        )
    }
}

@Composable
private fun SizeChip(
    textSize: AnkyWritingTextSize,
    isSelected: Boolean,
    modifier: Modifier = Modifier,
    onSelect: () -> Unit,
) {
    Box(
        modifier = modifier
            .background(
                if (isSelected) LazurePigments.ankyGoldLight.copy(alpha = 0.6f) else LazurePigments.ankyPaper.copy(alpha = 0.4f),
                RoundedCornerShape(999.dp),
            )
            .border(
                0.5.dp,
                LazurePigments.ankyInk.copy(alpha = if (isSelected) 0.16f else 0.08f),
                RoundedCornerShape(999.dp),
            )
            .clickable(onClick = onSelect)
            .padding(vertical = 9.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            textSize.displayName,
            style = LazureType.ankyCaption.copy(
                fontSize = 13.sp,
                fontWeight = FontWeight.Medium,
                color = SettingsInk.text.copy(alpha = if (isSelected) 0.95f else 0.65f),
            ),
            maxLines = 1,
        )
    }
}

// region Pure presentation helpers (unit-tested)

internal fun dailyTargetHeadline(
    minutes: Int,
    oneMinuteFormat: String,
    minutesFormat: String,
): String =
    if (minutes == 1) oneMinuteFormat.format(minutes) else minutesFormat.format(minutes)

/**
 * iOS parity: edits apply from the next local day, and the footnote says so
 * while a change is pending.
 */
internal fun dailyTargetFootnote(
    effectiveMinutes: Int,
    pendingMinutes: Int?,
    defaultFootnote: String,
    pendingFootnoteFormat: String,
): String =
    if (pendingMinutes != null && pendingMinutes != effectiveMinutes) {
        pendingFootnoteFormat.format(effectiveMinutes, pendingMinutes)
    } else {
        defaultFootnote
    }

internal fun encryptedBackupSubtitle(
    isEnabled: Boolean,
    lastBackupDate: Instant?,
    onLine: String,
    offLine: String,
    lastFormat: String,
): String =
    when {
        !isEnabled -> offLine
        lastBackupDate == null -> onLine
        else -> lastFormat.format(
            DateTimeFormatter
                .ofLocalizedDateTime(FormatStyle.MEDIUM, FormatStyle.SHORT)
                .withLocale(Locale.getDefault())
                .withZone(ZoneId.systemDefault())
                .format(lastBackupDate),
        )
    }

/** The gate off-switch is explicit: once off, nothing re-arms it (2026-07-06). */
internal fun gateStateLine(
    isGateOff: Boolean,
    blockedAppCount: Int,
    offLine: String,
    noSelectionLine: String,
    oneAppLine: String,
    manyAppsFormat: String,
): String =
    when {
        isGateOff -> offLine
        blockedAppCount <= 0 -> noSelectionLine
        blockedAppCount == 1 -> oneAppLine
        else -> manyAppsFormat.format(blockedAppCount)
    }

// endregion

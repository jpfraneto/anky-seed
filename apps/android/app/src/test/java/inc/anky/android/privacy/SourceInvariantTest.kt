package inc.anky.android.privacy

import java.io.File
import java.nio.file.Files
import java.nio.file.Path
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class SourceInvariantTest {
    @Test
    fun writeFeatureOnlyUsesMirrorForExplicitAnkyNudge() {
        val writeSources = sourceFiles("apps/android/app/src/main/java/inc/anky/android/feature/write")
        val forbidden = listOf(
            "OkHttp",
            "RequestBody",
            "RevenueCat",
            "Purchases",
            "http://",
            "https://",
        )

        val violations = writeSources.flatMap { file ->
            val text = file.readText()
            forbidden.filter { token -> text.contains(token) }.map { token -> "${file.relativeTo(repoRoot())}: $token" }
        }

        assertEquals(emptyList<String>(), violations)

        val writeViewModel = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/feature/write/WriteViewModel.kt")
            .readText()
        assertTrue(writeViewModel.contains("fun startAnkyNudgeIfPossible()"))
        assertTrue(writeViewModel.contains("MirrorIntent.Nudge"))
    }

    @Test
    fun revealCopySurfaceUsesExplicitSectionAwareCopy() {
        val androidReveal = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/feature/reveal/RevealScreen.kt")
            .readText()
        val androidRevealViewModel = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/feature/reveal/RevealViewModel.kt")
            .readText()
        val androidStrings = repoRoot()
            .resolve("apps/android/app/src/main/res/values")
            .listFiles { file -> file.extension == "xml" }
            .orEmpty()
            .joinToString("\n") { it.readText() }
        val androidArticles = repoRoot()
            .resolve("apps/android/app/src/main/res/values/article_strings.xml")
            .readText()
        val androidArticleStrings = repoRoot()
            .resolve("apps/android/app/src/main/res/values/article_strings.xml")
            .readText()

        assertTrue(androidReveal.contains("copyWriting = stringResource(R.string.copy_writing)"))
        assertTrue(androidReveal.contains("copyReflectionPromptHint = stringResource(R.string.copy_reflection_prompt_hint)"))
        assertTrue(androidReveal.contains("reflectionPromptCopied = stringResource(R.string.reflection_prompt_copied)"))
        assertTrue(androidReveal.contains("reflectionPromptClipboardGuidance = stringResource(R.string.reflection_prompt_clipboard_guidance)"))
        assertTrue(androidReveal.contains("RevealCopySection.ReflectionPrompt"))
        assertTrue(androidReveal.contains("onLongPress = {"))
        assertTrue(androidReveal.contains("copySection(RevealCopySection.ReflectionPrompt)"))
        assertTrue(androidReveal.contains("reflectionPromptGuidanceVisible = true"))
        assertTrue(androidReveal.contains("delay(1_500)"))
        assertTrue(androidStrings.contains("Copy writing"))
        assertTrue(androidStrings.contains("Long press to copy the reflection prompt for your own AI tool."))
        assertTrue(androidStrings.contains("The reflection prompt is on your clipboard. Take it to your favorite AI tool and get a reflection from it."))
        assertTrue(!androidReveal.contains("RevealCopyButton("))
        assertTrue(!androidReveal.contains("label = labels.copyReflection.lowercase()"))
        assertTrue(androidStrings.contains("Copy Reflection"))
        assertTrue(androidRevealViewModel.contains("enum class RevealCopySection"))
        assertTrue(androidRevealViewModel.contains("fun textForCopy(section: RevealCopySection)"))
        assertTrue(androidRevealViewModel.contains("AnkyReflectionPrompt.build(it.reconstructedText)"))
        assertTrue(!androidReveal.contains("""copyText("Anky mirror""""))
    }

    @Test
    fun hiddenWritingInputCapturesForwardOnlyImeGlyphs() {
        val hiddenInput = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/feature/write/HiddenTextInput.kt")
            .readText()

        assertTrue(hiddenInput.contains("ForwardOnlyInputView"))
        assertTrue(hiddenInput.contains("onCreateInputConnection"))
        assertTrue(hiddenInput.contains("commitText(text: CharSequence?"))
        assertTrue(hiddenInput.contains("setComposingText(text: CharSequence?"))
        assertTrue(hiddenInput.contains("next.startsWith(composingText)"))
        assertTrue(hiddenInput.contains("onGlyphs(glyphs)"))
        assertTrue(hiddenInput.contains("protocolGlyphsOrNull(maxGlyphs = 1)"))
        assertTrue(hiddenInput.contains("onRejectedMutation()"))
        assertTrue(hiddenInput.contains("InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD"))
        assertTrue(hiddenInput.contains("EditorInfo.IME_FLAG_NO_PERSONALIZED_LEARNING"))
        assertTrue(!hiddenInput.contains("BasicTextField"))
    }

    @Test
    fun decorativeBackgroundHorizontalLinesStayRemoved() {
        val reveal = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/feature/reveal/RevealScreen.kt")
            .readText()
        val tagSessions = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/feature/reveal/TagSessionsScreen.kt")
            .readText()
        val map = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/feature/map/MapScreen.kt")
            .readText()
        val you = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/feature/you/YouScreen.kt")
            .readText()

        assertTrue(!reveal.contains("listOf(0.19f, 0.47f, 0.78f)"))
        assertTrue(!tagSessions.contains("listOf(0.19f, 0.47f, 0.78f)"))
        assertTrue(!map.contains("listOf(0.18f, 0.54f, 0.82f)"))
        assertTrue(!you.contains("listOf(0.18f, 0.54f, 0.82f)"))
    }

    @Test
    fun mainSourcesDoNotLogDirectlyOutsideSafeLog() {
        val mainSources = sourceFiles("apps/android/app/src/main/java")
            .filterNot { it.name == "SafeLog.kt" }
        val forbiddenLogging = Regex("""\b(Log\.[a-zA-Z]+|println\(|printStackTrace\(|System\.(out|err))""")

        val violations = mainSources.mapNotNull { file ->
            val match = forbiddenLogging.find(file.readText())
            match?.let { "${file.relativeTo(repoRoot())}: ${it.value}" }
        }

        assertEquals(emptyList<String>(), violations)
    }

    @Test
    fun androidManifestKeepsAutomaticBackupDisabled() {
        val manifest = repoRoot()
            .resolve("apps/android/app/src/main/AndroidManifest.xml")
            .readText()
        val backupRules = repoRoot()
            .resolve("apps/android/app/src/main/res/xml/backup_rules.xml")
            .readText()
        val dataExtractionRules = repoRoot()
            .resolve("apps/android/app/src/main/res/xml/data_extraction_rules.xml")
            .readText()

        assertTrue(manifest.contains("""android:allowBackup="false""""))
        assertTrue(manifest.contains("""android:fullBackupContent="@xml/backup_rules""""))
        assertTrue(manifest.contains("""android:dataExtractionRules="@xml/data_extraction_rules""""))
        assertTrue(manifest.contains("""android:screenOrientation="portrait""""))
        listOf("root", "file", "database", "sharedpref", "external").forEach { domain ->
            assertTrue(backupRules.contains("""<exclude domain="$domain" path="." />"""))
            assertTrue(dataExtractionRules.contains("""<exclude domain="$domain" path="." />"""))
        }
        listOf("device_root", "device_file", "device_database", "device_sharedpref").forEach { domain ->
            assertTrue(dataExtractionRules.contains("""<exclude domain="$domain" path="." />"""))
        }
    }

    @Test
    fun googlePlayApplicationIdsStayFixed() {
        val buildScript = repoRoot()
            .resolve("apps/android/app/build.gradle.kts")
            .readText()

        assertTrue(buildScript.contains("""applicationId = "app.anky.mobile""""))
        assertTrue(buildScript.contains("""applicationIdSuffix = releaseProperty("ANKY_ANDROID_DEBUG_APPLICATION_ID_SUFFIX")?.takeIf { it.isNotBlank() }"""))
        assertTrue(buildScript.contains("""println("releaseApplicationId=app.anky.mobile")"""))
        assertTrue(buildScript.contains("""println("debugApplicationId=app.anky.mobile${'$'}{releaseProperty("ANKY_ANDROID_DEBUG_APPLICATION_ID_SUFFIX")?.takeIf { it.isNotBlank() }.orEmpty()}")"""))
    }

    @Test
    fun fileProviderOnlyExposesExplicitExportCacheDirectory() {
        val manifest = repoRoot()
            .resolve("apps/android/app/src/main/AndroidManifest.xml")
            .readText()
        val filePaths = repoRoot()
            .resolve("apps/android/app/src/main/res/xml/file_paths.xml")
            .readText()

        assertTrue(manifest.contains("""android:name="androidx.core.content.FileProvider""""))
        assertTrue(manifest.contains("""android:exported="false""""))
        assertTrue(manifest.contains("""android:grantUriPermissions="true""""))
        assertTrue(filePaths.contains("""<cache-path name="exports" path="exports/" />"""))
        listOf("root-path", "files-path", "external-path", "external-files-path", "external-cache-path")
            .forEach { forbiddenPath ->
                assertTrue("FileProvider must not expose $forbiddenPath", !filePaths.contains(forbiddenPath))
            }
    }

    @Test
    fun androidAppInputsDoNotConfigureAnalyticsCrashReportersOrServerSecrets() {
        val buildScript = repoRoot()
            .resolve("apps/android/app/build.gradle.kts")
            .readText()
        val mainSourceText = sourceFiles("apps/android/app/src/main/java")
            .joinToString("\n") { it.readText() }
        val scannedText = "$buildScript\n$mainSourceText"
        val forbiddenTokens = listOf(
            "REVENUECAT_SECRET",
            "REVENUECAT_SECRET_KEY",
            "GOOGLE_SERVICE_ACCOUNT",
            "SERVICE_ACCOUNT_JSON",
            "service-account",
            "service_account",
            "credentials.json",
            "firebase-crashlytics",
            "crashlytics",
            "sentry",
            "amplitude",
            "mixpanel",
            "segment-analytics",
        )

        val violations = forbiddenTokens.filter { token -> scannedText.contains(token, ignoreCase = true) }

        assertEquals(emptyList<String>(), violations)
        assertTrue(buildScript.contains("ANKY_REVENUECAT_ANDROID_PUBLIC_KEY"))
    }

    @Test
    fun androidAppDoesNotIntroduceCrossPlatformShells() {
        val scannedFiles = sourceFiles("apps/android/app/src/main/java") +
            listOf(
                repoRoot().resolve("apps/android/app/build.gradle.kts"),
                repoRoot().resolve("apps/android/build.gradle.kts"),
                repoRoot().resolve("apps/android/settings.gradle.kts"),
                repoRoot().resolve("apps/android/app/src/main/AndroidManifest.xml"),
            )
        val forbiddenTokens = listOf(
            "android.webkit",
            "WebView",
            "react-native",
            "ReactNative",
            "com.facebook.react",
            "io.flutter",
            "FlutterActivity",
            "expo.modules",
            "CordovaActivity",
            "org.apache.cordova",
            "com.getcapacitor",
        )
        val violations = scannedFiles.flatMap { file ->
            val text = file.readText()
            forbiddenTokens
                .filter { token -> text.contains(token, ignoreCase = true) }
                .map { token -> "${file.relativeTo(repoRoot())}: $token" }
        }

        assertEquals(emptyList<String>(), violations)
    }

    @Test
    fun forbiddenSecretLikeFilesAreNotPresentInAndroidTree() {
        val forbiddenNames = Regex(
            """(^local\.properties$|.*\.(jks|keystore)$|.*service-account.*\.json$|.*credentials.*\.json$|^\.env$)""",
            RegexOption.IGNORE_CASE,
        )
        val violations = Files.walk(repoRoot().resolve("apps/android").toPath()).use { paths ->
            paths
                .filter { Files.isRegularFile(it) }
                .map { it.toFile().relativeTo(repoRoot()).path }
                .filter { path: String ->
                    path != "apps/android/local.properties" && forbiddenNames.matches(File(path).name)
                }
                .toList()
        }

        assertEquals(emptyList<String>(), violations)
    }

    @Test
    fun networkAndPurchaseClientsStayInExplicitPaths() {
        val allowedByToken = mapOf(
            // YouViewModel entries cover the legacy $ANKY Stripe onramp; delete them with the
            // Token page in the credits-removal cleanup (PARITY.md WS4/WS10).
            "OkHttpClient" to setOf(
                "apps/android/app/src/main/java/inc/anky/android/core/mirror/MirrorClient.kt",
                "apps/android/app/src/main/java/inc/anky/android/core/level/LevelSyncClient.kt",
                "apps/android/app/src/main/java/inc/anky/android/feature/you/YouViewModel.kt",
            ),
            "Request.Builder" to setOf(
                "apps/android/app/src/main/java/inc/anky/android/core/mirror/MirrorClient.kt",
                "apps/android/app/src/main/java/inc/anky/android/core/level/LevelSyncClient.kt",
                "apps/android/app/src/main/java/inc/anky/android/core/level/SignedLevelRequests.kt",
                "apps/android/app/src/main/java/inc/anky/android/feature/you/YouViewModel.kt",
            ),
            "newCall(" to setOf(
                "apps/android/app/src/main/java/inc/anky/android/core/mirror/MirrorClient.kt",
                "apps/android/app/src/main/java/inc/anky/android/core/level/LevelSyncClient.kt",
                "apps/android/app/src/main/java/inc/anky/android/feature/you/YouViewModel.kt",
            ),
            "Purchases" to setOf(
                "apps/android/app/src/main/java/inc/anky/android/core/credits/RevenueCatCreditsClient.kt",
                "apps/android/app/src/main/java/inc/anky/android/feature/you/YouScreen.kt",
                "apps/android/app/src/main/java/inc/anky/android/feature/you/YouViewModel.kt",
                "apps/android/app/src/main/java/inc/anky/android/core/subscription/AnkyPurchasesConfig.kt",
                "apps/android/app/src/main/java/inc/anky/android/core/subscription/EntitlementStore.kt",
                "apps/android/app/src/main/java/inc/anky/android/core/subscription/RevenueCatSubscriptionGateway.kt",
                "apps/android/app/src/main/java/inc/anky/android/core/subscription/SubscriptionModels.kt",
                "apps/android/app/src/main/java/inc/anky/android/core/subscription/PurchaseConstants.kt",
                "apps/android/app/src/main/java/inc/anky/android/core/subscription/TrialReminder.kt",
                "apps/android/app/src/main/java/inc/anky/android/feature/paywall/PaywallContext.kt",
                "apps/android/app/src/main/java/inc/anky/android/feature/paywall/PaywallModels.kt",
                "apps/android/app/src/main/java/inc/anky/android/feature/paywall/PaywallScreen.kt",
                "apps/android/app/src/main/java/inc/anky/android/feature/paywall/PaywallSheet.kt",
            ),
            "PurchasesConfiguration" to setOf(
                "apps/android/app/src/main/java/inc/anky/android/core/credits/RevenueCatCreditsClient.kt",
                "apps/android/app/src/main/java/inc/anky/android/core/subscription/AnkyPurchasesConfig.kt",
            ),
            "PurchaseParams" to setOf(
                "apps/android/app/src/main/java/inc/anky/android/core/credits/RevenueCatCreditsClient.kt",
                "apps/android/app/src/main/java/inc/anky/android/core/subscription/RevenueCatSubscriptionGateway.kt",
            ),
            "RevenueCatCreditsClient" to setOf(
                "apps/android/app/src/main/java/inc/anky/android/app/AppContainer.kt",
                "apps/android/app/src/main/java/inc/anky/android/core/credits/RevenueCatCreditsClient.kt",
            ),
        )
        val violations = sourceFiles("apps/android/app/src/main/java")
            .flatMap { file ->
                val relativePath = file.relativeTo(repoRoot()).path
                val text = file.readText()
                allowedByToken
                    .filter { (token, allowedPaths) -> text.contains(token) && relativePath !in allowedPaths }
                    .map { (token, _) -> "$relativePath: $token" }
            }

        assertEquals(emptyList<String>(), violations)
    }

    @Test
    fun revenueCatRestoreIsUserTriggeredAndDoesNotProgrammaticallySyncPurchases() {
        val creditsClient = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/core/credits/RevenueCatCreditsClient.kt")
            .readText()
        val youScreen = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/feature/you/YouScreen.kt")
            .readText()
        val youViewModel = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/feature/you/YouViewModel.kt")
            .readText()
        val appRoot = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/app/AnkyApp.kt")
            .readText()

        assertTrue(creditsClient.contains("override suspend fun restorePurchases()"))
        assertTrue(creditsClient.contains("purchases.awaitRestorePurchases()"))
        assertTrue(youScreen.contains("onRestorePurchases = viewModel::restorePurchases"))
        assertTrue(!creditsClient.contains("syncPurchases"))
        assertTrue(!youViewModel.substringBefore("fun restorePurchases()").contains("restorePurchases()"))
        assertTrue(!appRoot.contains("restorePurchases"))
    }

    @Test
    fun revenueCatAndroidUsesSubscriptionProductsAndNoDirectCreditProducts() {
        val subscriptionGateway = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/core/subscription/RevenueCatSubscriptionGateway.kt")
            .readText()
        val purchaseConfig = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/core/subscription/AnkyPurchasesConfig.kt")
            .readText()

        assertTrue(purchaseConfig.contains("const val ENTITLEMENT_ID = \"pro\""))
        assertTrue(purchaseConfig.contains("const val OFFERING_ID = \"default\""))
        assertTrue(purchaseConfig.contains("const val YEARLY_PRODUCT_ID = \"anky.yearly\""))
        assertTrue(purchaseConfig.contains("const val MONTHLY_PRODUCT_ID = \"anky.monthly\""))
        assertTrue(subscriptionGateway.contains("awaitOfferings()"))
        assertTrue(subscriptionGateway.contains("PurchaseParams.Builder(activity, rcPackage).build()"))
        assertTrue(!subscriptionGateway.contains("ProductType.INAPP"))
        assertTrue(!subscriptionGateway.contains("CreditCatalog"))
    }

    @Test
    fun mirrorUploadCodeOnlyLivesBehindExplicitRevealOrWriteNudgePaths() {
        val allowedRelativePaths = setOf(
            "apps/android/app/src/main/java/inc/anky/android/app/AppContainer.kt",
            "apps/android/app/src/main/java/inc/anky/android/core/mirror/MirrorClient.kt",
            "apps/android/app/src/main/java/inc/anky/android/feature/reveal/RevealScreen.kt",
            "apps/android/app/src/main/java/inc/anky/android/feature/reveal/RevealViewModel.kt",
            "apps/android/app/src/main/java/inc/anky/android/feature/write/WriteViewModel.kt",
        )
        val uploadTokens = listOf(
            "import inc.anky.android.core.mirror.MirrorClient",
            "MirrorClient(",
            ".askAnky(",
            "fun askAnky(",
        )
        val violations = sourceFiles("apps/android/app/src/main/java")
            .flatMap { file ->
                val relativePath = file.relativeTo(repoRoot()).path
                if (relativePath in allowedRelativePaths) {
                    emptyList()
                } else {
                    val text = file.readText()
                    uploadTokens
                        .filter { token -> text.contains(token) }
                        .map { token -> "$relativePath: $token" }
                }
            }

        assertEquals(emptyList<String>(), violations)
    }

    @Test
    fun backupRestorePickerDoesNotUseWildcardFileTypes() {
        val youScreen = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/feature/you/YouScreen.kt")
            .readText()

        assertTrue(youScreen.contains("application/zip"))
        assertTrue(youScreen.contains("application/x-zip-compressed"))
        assertTrue(youScreen.contains("application/octet-stream"))
        assertTrue(youScreen.contains("application/json"))
        assertTrue(youScreen.contains("text/plain"))
        assertTrue(!youScreen.contains("\"*/*\""))
        assertTrue(!youScreen.contains("\"text/*\""))
    }

    @Test
    fun youExportPromptMatchesCurrentIosReadableExportActions() {
        val androidYou = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/feature/you/YouScreen.kt")
            .readText()
        val androidModel = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/feature/you/YouViewModel.kt")
            .readText()
        val androidStore = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/core/storage/AndroidEncryptedBackupStore.kt")
            .readText()
        val androidApp = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/app/AnkyApp.kt")
            .readText()
        val androidHiddenInput = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/feature/write/HiddenTextInput.kt")
            .readText()
        val androidArticles = repoRoot()
            .resolve("apps/android/app/src/main/res/values/article_strings.xml")
            .readText()
        val iosYou = repoRoot()
            .resolve("apps/ios/Anky/Features/You/YouView.swift")
            .readText()
        val iosModel = repoRoot()
            .resolve("apps/ios/Anky/Features/You/YouViewModel.swift")
            .readText()
        val iosBackupStore = repoRoot()
            .resolve("apps/ios/Anky/Core/Storage/ICloudBackupStore.swift")
            .readText()

        assertTrue(iosYou.contains("""AnkyChatAction(AnkyLocalization.ui(viewModel.isICloudBackupWorking ? "Backing up" : "Back up now"), isPrimary: true)"""))
        assertTrue(iosYou.contains("""AnkyChatAction(AnkyLocalization.ui("Export writings"))"""))
        assertTrue(iosYou.contains("viewModel.prepareFormattedWritingExport()"))
        assertTrue(iosYou.contains("if let exportURL = viewModel.formattedWritingExportURL"))
        assertTrue(iosYou.contains("viewModel.isICloudBackupEnabled"))
        assertTrue(iosModel.contains("func enableICloudBackup() async"))
        assertTrue(iosModel.contains("func backUpToICloudNow() async"))
        assertTrue(iosBackupStore.contains("AES-GCM-HKDF-SHA256"))
        assertTrue(iosBackupStore.contains("backUpIfEnabled()"))
        assertTrue(!iosYou.contains("""AnkyChatAction("prepare backup""""))

        assertTrue(androidYou.contains("backingUp = stringResource(R.string.backing_up)"))
        assertTrue(androidYou.contains("backUpNow = stringResource(R.string.back_up_now)"))
        assertTrue(androidYou.contains("exportWritings = stringResource(R.string.export_writings)"))
        assertTrue(androidYou.contains("AnkyChatAction(if (state.isEncryptedBackupWorking) labels.backingUp else labels.backUpNow, isPrimary = true)"))
        assertTrue(androidYou.contains("AnkyChatAction(labels.exportWritings)"))
        assertTrue(androidYou.contains("viewModel.prepareFormattedWritingExport()"))
        assertTrue(androidYou.contains("state.formattedWritingExportFile?.let"))
        assertTrue(androidYou.contains("state.isEncryptedBackupEnabled"))
        assertTrue(androidYou.contains("stringResource(R.string.you_status_encrypted_backup_on_after_next_writing)"))
        assertTrue(androidYou.contains("stringResource(R.string.you_encrypted_backup_last_updated"))
        assertTrue(androidModel.contains("fun enableEncryptedBackup("))
        assertTrue(androidModel.contains("fun backUpEncryptedNow()"))
        assertTrue(androidModel.contains("fun restoreEncryptedBackup("))
        assertTrue(androidStore.contains("AES-GCM-HKDF-SHA256"))
        assertTrue(androidStore.contains("fun backUpIfEnabled()"))
        assertTrue(androidStore.contains("backupImporter.importBackupBytes(zipBytes, \"anky-backup.zip\")"))
        assertTrue(androidApp.contains("container.encryptedBackupStore.backUpIfEnabled()"))
        assertTrue(!androidYou.contains("""AnkyChatAction("prepare backup""""))
    }

    @Test
    fun youStatsOpenCurrentIosAllAnkysHistory() {
        val iosYou = repoRoot()
            .resolve("apps/ios/Anky/Features/You/YouView.swift")
            .readText()
        val iosYouModel = repoRoot()
            .resolve("apps/ios/Anky/Features/You/YouViewModel.swift")
            .readText()
        val androidYou = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/feature/you/YouScreen.kt")
            .readText()
        val androidYouModel = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/feature/you/YouViewModel.kt")
            .readText()
        val androidStrings = repoRoot()
            .resolve("apps/android/app/src/main/res/values")
            .listFiles { file -> file.extension == "xml" }
            .orEmpty()
            .joinToString("\n") { it.readText() }
        val androidSpanishStrings = repoRoot()
            .resolve("apps/android/app/src/main/res/values-es/strings.xml")
            .readText()
        val androidApp = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/app/AnkyApp.kt")
            .readText()

        assertTrue(iosYou.contains("case .allAnkys:"))
        assertTrue(iosYou.contains("YouAllAnkysHistoryView("))
        assertTrue(iosYou.contains("viewModel.completeAnkySessions"))
        assertTrue(iosYou.contains(".accessibilityLabel(AnkyLocalization.ui(\"Open all ankys\"))"))
        assertTrue(iosYou.contains("NavigationLink(value: session)"))
        assertTrue(iosYou.contains("Text(AnkyLocalization.ui(\"0 ankys\"))"))
        assertTrue(iosYou.contains("Text(AnkyLocalization.ui(\"WRITE %d MINUTES\", AnkyDuration.completeRitualMinutes))"))
        assertTrue(iosYouModel.contains("@Published private(set) var completeAnkySessions: [SessionSummary] = []"))

        assertTrue(androidYou.contains("YouPage.History"))
        assertTrue(androidYou.contains("YouHistoryPage("))
        assertTrue(androidYou.contains("state.completeAnkySessions"))
        assertTrue(androidYou.contains("val openAllAnkysLabel = stringResource(R.string.open_all_ankys)"))
        assertTrue(androidYou.contains("contentDescription = openAllAnkysLabel"))
        assertTrue(androidYou.contains("stringResource(R.string.you_stat_ankys)"))
        assertTrue(androidYou.contains("stringResource(R.string.you_stat_minutes)"))
        assertTrue(androidYou.contains("stringResource(R.string.you_stat_streak)"))
        assertTrue(androidYou.contains("onOpenReveal(session.hash)"))
        assertTrue(androidYou.contains("contentDescription = backLabel"))
        assertTrue(!androidYou.contains("contentDescription = \"Back\""))
        assertTrue(androidYou.contains("historyTitle(sessions.size, oneAnkyFormat, ankysFormat)"))
        assertTrue(androidYou.contains("stringResource(R.string.zero_ankys)"))
        assertTrue(androidYou.contains("stringResource(R.string.write_minutes_caps, AnkyDuration.CompleteRitualMinutes)"))
        assertTrue(androidYou.contains("stringResource(R.string.one_anky_count_format)"))
        assertTrue(androidYou.contains("stringResource(R.string.ankys_count_format)"))
        assertTrue(androidYou.contains("stringResource(R.string.word)"))
        assertTrue(androidYou.contains("stringResource(R.string.words)"))
        assertTrue(androidStrings.contains("""name="open_all_ankys">Open all ankys</string>"""))
        assertTrue(androidStrings.contains("""name="you_stat_ankys">ankys</string>"""))
        assertTrue(androidStrings.contains("""name="you_stat_minutes">minutes</string>"""))
        assertTrue(androidStrings.contains("""name="you_stat_streak">streak</string>"""))
        assertTrue(androidStrings.contains("""name="back">Back</string>"""))
        assertTrue(androidStrings.contains("""name="zero_ankys">0 ankys</string>"""))
        assertTrue(androidStrings.contains("""name="write_minutes_caps">WRITE %1${'$'}d MINUTES</string>"""))
        assertTrue(androidStrings.contains("""name="one_anky_count_format">%1${'$'}d anky</string>"""))
        assertTrue(androidStrings.contains("""name="ankys_count_format">%1${'$'}d ankys</string>"""))
        assertTrue(androidStrings.contains("""name="word">word</string>"""))
        assertTrue(androidStrings.contains("""name="words">words</string>"""))
        assertTrue(androidSpanishStrings.contains("""name="open_all_ankys">Abrir todos los ankys</string>"""))
        assertTrue(androidSpanishStrings.contains("""name="back">Atrás</string>"""))
        assertTrue(androidSpanishStrings.contains("""name="zero_ankys">0 ankys</string>"""))
        assertTrue(!androidYou.contains("YouStats(state, onClick"))
        assertTrue(androidYouModel.contains("val completeAnkySessions: List<SessionSummary> = emptyList()"))
        assertTrue(androidYouModel.contains("completeSessions(sessions)"))
        assertTrue(androidApp.contains("onOpenReveal = { hash -> navController.navigate(AnkyRoute.Reveal.route(hash, from = RevealSource.Day)) }"))
        assertTrue(androidApp.contains("onWriteRequested = { beginRetryWriting() }"))
    }

    @Test
    fun youDeleteAccountAndDataMatchesCurrentIosDestructiveFlow() {
        val iosYou = repoRoot()
            .resolve("apps/ios/Anky/Features/You/YouView.swift")
            .readText()
        val iosYouModel = repoRoot()
            .resolve("apps/ios/Anky/Features/You/YouViewModel.swift")
            .readText()
        val androidYou = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/feature/you/YouScreen.kt")
            .readText()
        val androidYouModel = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/feature/you/YouViewModel.kt")
            .readText()
        val androidStrings = repoRoot()
            .resolve("apps/android/app/src/main/res/values/strings.xml")
            .readText()
        val androidApp = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/app/AnkyApp.kt")
            .readText()
        val androidWriteModel = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/feature/write/WriteViewModel.kt")
            .readText()
        val androidSettingsStore = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/app/UserSettingsStore.kt")
            .readText()
        val androidAppOpenStore = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/core/storage/AppOpenStore.kt")
            .readText()
        val androidRequestStore = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/core/storage/ReflectionRequestStore.kt")
            .readText()
        val androidCreditsClient = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/core/credits/RevenueCatCreditsClient.kt")
            .readText()

        // Current iOS destructive flow: hidden panel behind the "!" toolbar
        // toggle, one confirm alert, then a full local + iCloud wipe. No
        // credits anywhere — the credit economy is gone from iOS.
        assertTrue(iosYou.contains("@State private var confirmDeleteAccountAndData"))
        assertTrue(iosYou.contains("@State private var showsAccountDeletion"))
        assertTrue(iosYou.contains("showsAccountDeletion.toggle()"))
        assertTrue(iosYou.contains("Image(systemName: \"exclamationmark\")"))
        assertTrue(iosYou.contains("\"Hide delete account action\" : \"Show delete account action\""))
        assertTrue(iosYou.contains("YouDestructiveMenuRow(title: \"DELETE ACCOUNT AND DATA\")"))
        assertTrue(iosYou.contains(".alert(AnkyLocalization.ui(\"Delete Account and Data?\""))
        assertTrue(iosYou.contains("Text(AnkyLocalization.ui(\"This deletes your Anky data from this device and iCloud. This cannot be undone.\"))"))
        assertTrue(iosYou.contains("await viewModel.deleteAccountAndDataEverywhere()"))
        assertTrue(iosYouModel.contains("func deleteAccountAndDataEverywhere() async"))
        assertTrue(iosYouModel.contains("try archive.clear()"))
        assertTrue(iosYouModel.contains("try reflectionStore.clear()"))
        assertTrue(iosYouModel.contains("try? sessionIndexStore.clear()"))
        assertTrue(iosYouModel.contains("ActiveDraftStore().clear()"))
        assertTrue(iosYouModel.contains("notifications.cancelDailyReminder()"))
        assertTrue(iosYouModel.contains("appOpenStore.clear()"))
        assertTrue(iosYouModel.contains("try? iCloudBackupStore.deleteRemoteBackupAndDisable()"))
        assertTrue(iosYouModel.contains("try identityStore.resetForDevelopment(includeICloudBackup: true)"))
        assertTrue(iosYouModel.contains("clearDevelopmentDefaults()"))
        assertTrue(iosYouModel.contains("Account and data deleted from this device and Anky iCloud backup."))
        assertTrue(!iosYouModel.contains("creditsClient"))
        assertTrue(!iosYouModel.contains("ReflectionCreditCache"))

        assertTrue(androidYou.contains("confirmDeleteAccountAndData"))
        assertTrue(androidYou.contains("val showsAccountDeletion = remember { mutableStateOf(false) }"))
        assertTrue(androidYou.contains("onToggleAccountDeletion = { showsAccountDeletion.value = !showsAccountDeletion.value }"))
        assertTrue(androidYou.contains("Icons.Filled.PriorityHigh"))
        assertTrue(androidYou.contains("stringResource(R.string.hide_delete_account_action)"))
        assertTrue(androidYou.contains("stringResource(R.string.show_delete_account_action)"))
        assertTrue(!androidYou.contains("\"Hide delete account action\""))
        assertTrue(!androidYou.contains("\"Show delete account action\""))
        assertTrue(androidYou.contains("DestructiveMenuRow(stringResource(R.string.you_delete_account_data_caps), onClick = onDeleteAccountAndData)"))
        assertTrue(androidYou.contains("Text(stringResource(R.string.you_delete_account_data_question)"))
        assertTrue(androidYou.contains("stringResource(R.string.you_delete_account_data_body)"))
        assertTrue(androidYou.contains("stringResource(R.string.you_delete_account_data_caps)"))
        assertTrue(androidStrings.contains("Delete Account and Data?"))
        assertTrue(androidStrings.contains("This deletes your Anky data from this device. This cannot be undone."))
        assertTrue(androidStrings.contains("DELETE ACCOUNT AND DATA"))
        assertTrue(androidStrings.contains("Hide delete account action"))
        assertTrue(androidStrings.contains("Show delete account action"))
        assertTrue(androidYou.contains("viewModel.deleteAccountAndDataEverywhere(onDeleted = onAccountDeleted)"))
        assertTrue(androidYouModel.contains("fun deleteAccountAndDataEverywhere(onDeleted: () -> Unit = {})"))
        assertTrue(androidYouModel.contains("archive.clear()"))
        assertTrue(androidYouModel.contains("reflectionStore.clear()"))
        assertTrue(androidYouModel.contains("requestStore.clear()"))
        assertTrue(androidYouModel.contains("indexStore.clear()"))
        assertTrue(androidYouModel.contains("activeDraftStore.clear()"))
        assertTrue(androidYouModel.contains("settingsStore.resetToDefaults()"))
        assertTrue(androidYouModel.contains("appOpenStore.clear()"))
        assertTrue(androidYouModel.contains("encryptedBackupStore.deleteBackupAndDisable()"))
        assertTrue(androidYouModel.contains("identityStore.resetForDevelopment()"))
        // Android additionally logs the RevenueCat customer out (the Play-side
        // analogue of the identity reset); the credits client is only the
        // carrier until the cleanup phase deletes it.
        assertTrue(androidYouModel.contains("creditsClient.logOutIfConfigured()"))
        assertTrue(androidYouModel.contains("reflectionCreditCache.clear()"))
        assertTrue(androidYouModel.contains("YouStatusCopy.AccountAndDataDeleted"))
        assertTrue(androidYouModel.contains("YouStatusCopy.CouldNotDeleteAllAccountData"))
        assertTrue(androidApp.contains("writeViewModelWithCurrentMirror.resetAfterAccountDeletion()"))
        assertTrue(androidApp.contains("mapViewModel.refresh()"))
        assertTrue(!androidApp.contains("rootCreditBalance.value = null"))
        assertTrue(androidWriteModel.contains("fun resetAfterAccountDeletion()"))
        assertTrue(androidSettingsStore.contains("suspend fun resetToDefaults()"))
        assertTrue(androidAppOpenStore.contains("fun clear()"))
        assertTrue(androidRequestStore.contains("fun clear()"))
        assertTrue(androidCreditsClient.contains("suspend fun logOutIfConfigured()"))
        assertTrue(androidCreditsClient.contains("Purchases.sharedInstance.awaitLogOut()"))
    }

    @Test
    fun ankyChatActionSupportsIosSubtitleBadgeAndPackageActions() {
        // Repurposed (WS8): the credit-package chat actions this test used to
        // guard are deleted with the credits economy. It now guards the chat
        // action component shape (subtitle/badge stay supported — iOS still
        // renders them in AnkyWitnessView) and that no credit-package actions
        // return to the You surfaces.
        val androidPrompt = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/ui/components/AnkyCompanionPrompt.kt")
            .readText()
        val androidYou = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/feature/you/YouScreen.kt")
            .readText()
        val androidStrings = repoRoot()
            .resolve("apps/android/app/src/main/res/values/strings.xml")
            .readText()
        val iosWitness = repoRoot()
            .resolve("apps/ios/Anky/Support/AnkyWitnessView.swift")
            .readText()
        val iosYou = repoRoot()
            .resolve("apps/ios/Anky/Features/You/YouView.swift")
            .readText()

        assertTrue(iosWitness.contains("let subtitle: String?"))
        assertTrue(iosWitness.contains("let badge: String?"))
        assertTrue(iosWitness.contains("Array(actions.prefix(4))"))
        assertTrue(iosWitness.contains("Image(systemName: \"xmark\")"))
        assertTrue(iosWitness.contains("accessibilityLabel(AnkyLocalization.ui(\"Close Anky message\"))"))
        assertTrue(!iosYou.contains("creditPackage"))
        assertTrue(iosYou.contains("""AnkyChatAction(AnkyLocalization.ui("Open email"), isPrimary: true)"""))
        assertTrue(iosYou.contains("""AnkyChatAction(AnkyLocalization.ui("Export writings"))"""))

        assertTrue(androidPrompt.contains("val subtitle: String? = null"))
        assertTrue(androidPrompt.contains("val badge: String? = null"))
        assertTrue(androidPrompt.contains("actions.take(4)"))
        assertTrue(androidPrompt.contains("Icons.Filled.Close"))
        assertTrue(androidPrompt.contains("val closeAnkyMessageLabel = stringResource(R.string.close_anky_message)"))
        assertTrue(androidPrompt.contains("contentDescription = closeAnkyMessageLabel"))
        assertTrue(!androidPrompt.contains("""Text("x""""))
        assertTrue(androidStrings.contains("""name="close_anky_message">Close Anky message</string>"""))
        listOf("values-es", "values-fr", "values-de", "values-hi", "values-zh-rCN").forEach { localeDir ->
            val localizedStrings = repoRoot()
                .resolve("apps/android/app/src/main/res/$localeDir/strings.xml")
                .readText()
            assertTrue(localizedStrings.contains("close_anky_message"))
        }
        assertTrue(!androidYou.contains("creditPackage"))
        assertTrue(!androidYou.contains("subtitle = creditPackage.price"))
        assertTrue(!androidYou.contains("badge = if (isRecommended) labels.bestValue else null"))
        assertTrue(androidYou.contains("AnkyChatAction(labels.openEmail, isPrimary = true)"))
        assertTrue(androidYou.contains("AnkyChatAction(labels.exportWritings)"))
    }

    @Test
    fun postWriteCompletionRoutesDirectlyIntoRevealForSmoothAndroidTransition() {
        // Updated truth (2026-07): sealing no longer routes into Reveal.
        // iOS ends every session in PostSessionSealingView (seal -> mirror ->
        // gate); Android mirrors it with PostSessionSealingScreen hosted by
        // WriteScreen, while imports keep the old Reveal path in AnkyApp.
        val androidApp = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/app/AnkyApp.kt")
            .readText()
        val androidWrite = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/feature/write/WriteScreen.kt")
            .readText()
        val androidWriteModel = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/feature/write/WriteViewModel.kt")
            .readText()
        val androidSealing = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/feature/write/PostSessionSealingScreen.kt")
            .readText()
        val iosApp = repoRoot()
            .resolve("apps/ios/Anky/AppRoot.swift")
            .readText()

        // iOS: sealing is its own write surface with the 3-beat view.
        assertTrue(iosApp.contains("case sealing"))
        assertTrue(iosApp.contains("writeSurface = .sealing"))
        assertTrue(iosApp.contains("PostSessionSealingView("))
        assertTrue(iosApp.contains("private func finishSealingToMainScreen(requestingReview: Bool = true)"))
        assertTrue(iosApp.contains("onStay: stayAfterSealing"))

        // Android: the seal holds a SealedWritingSession for the sealing
        // screen instead of emitting completedHash toward Reveal.
        assertTrue(androidWriteModel.contains("sealedSession = makeSealedSession(artifact, sealedAt)"))
        assertTrue(!androidWriteModel.contains("completedHash = artifact.hash"))
        assertTrue(androidWriteModel.contains("fun finishSealing()"))
        assertTrue(androidWriteModel.contains("fun stayAfterSealing(): Boolean"))
        assertTrue(androidWriteModel.contains("fun beginSealedSessionReflection()"))
        assertTrue(androidWrite.contains("PostSessionSealingScreen("))
        assertTrue(androidWrite.contains("onStartReflection = viewModel::beginSealedSessionReflection"))
        assertTrue(androidWrite.contains("viewModel.stayAfterSealing()"))
        assertTrue(androidWrite.contains("viewModel.sealIfLeftInMotion()"))
        assertTrue(androidSealing.contains("\"Sealed · \$prefix...\$suffix\""))
        assertTrue(androidSealing.contains("kotlinx.coroutines.delay(3_000)"))
        assertTrue(androidSealing.contains("VeiledFeature("))
        assertTrue(androidSealing.contains("AnkyCopyRegistry.veilReflection"))

        // Imports still surface through AnkyApp's Reveal plumbing.
        assertTrue(androidApp.contains("val importedCompletedHash = remember { mutableStateOf<String?>(null) }"))
        assertTrue(androidApp.contains("fun openPostWriteReveal(hash: String)"))
        assertTrue(androidApp.contains("onImported = { hash ->"))
        assertTrue(androidWrite.contains("onImported: (String) -> Unit"))
        assertTrue(androidWrite.contains("onImported(saved.hash)"))
        assertTrue(androidWrite.contains("fun importAndOfferReflection"))
    }

    @Test
    fun androidWritingSurfaceStaysWhiteOnBlackWithoutInnerRingGlow() {
        val androidWrite = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/feature/write/WriteScreen.kt")
            .readText()

        assertTrue(androidWrite.contains(".background(Color.Black)"))
        assertTrue(androidWrite.contains("SpanStyle(color = AnkyColors.Paper.copy(alpha = alpha))"))
        assertTrue(androidWrite.contains("color = Color.White.copy(alpha = 0.94f)"))
        assertTrue(!androidWrite.contains("private fun rhythmColor"))
        assertTrue(!androidWrite.contains("drawCircle(Color.White.copy(alpha = 0.10f + pulse * 0.04f)"))
    }

    @Test
    fun writeLaunchPromptIsNotPresentedOnAndroid() {
        val androidApp = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/app/AnkyApp.kt")
            .readText()
        val androidStrings = repoRoot()
            .resolve("apps/android/app/src/main/res/values/strings.xml")
            .readText()
        val iosApp = repoRoot()
            .resolve("apps/ios/Anky/AppRoot.swift")
            .readText()
        val iosLocalization = repoRoot()
            .resolve("apps/ios/Anky/Support/AnkyLocalization.swift")
            .readText()

        listOf(".stepWriteOneCharacter", ".stepKeepThreadAlive", ".stepLetSilenceCloseIt").forEach { key ->
            assertTrue(iosApp.contains("AnkyBubbleStep(AnkyLocalization.text($key))"))
            assertTrue(iosLocalization.contains(key))
        }
        assertTrue(iosLocalization.contains(".launchEmpty: \"The living .anky string is the state of this session.\""))
        listOf(
            "launch_empty",
            "launch_count_format",
            "write_again",
            "write_minutes_format",
            "step_write_one_character",
            "step_keep_thread_alive",
            "step_let_silence_close_it",
        ).forEach { key ->
            assertTrue(!androidApp.contains("R.string.$key"))
            assertTrue(!androidStrings.contains("""name="$key""""))
        }
        assertTrue(!androidApp.contains("showsLaunchDialogue"))
        assertTrue(!androidApp.contains("launchMessage"))
        assertTrue(iosApp.contains("writeViewModel.openWritingPortal()"))
        assertTrue(androidApp.contains("writeViewModelWithCurrentMirror.openWritingPortal()"))
    }

    @Test
    fun writeTimerExposesIosWritingTimeAccessibilityLabel() {
        val androidWrite = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/feature/write/WriteScreen.kt")
            .readText()
        val iosWrite = repoRoot()
            .resolve("apps/ios/Anky/Features/Write/WriteView.swift")
            .readText()
        val androidStrings = repoRoot()
            .resolve("apps/android/app/src/main/res/values/strings.xml")
            .readText()

        val androidWriteStrings = repoRoot()
            .resolve("apps/android/app/src/main/res/values/strings_write.xml")
            .readText()

        // iOS now counts down to the daily target, then counts what was
        // written past it, and reads "Writing time <time> <caption>".
        assertTrue(iosWrite.contains("accessibilityLabel(AnkyLocalization.ui(\"Writing time %@\", \"\\(timeText) \\(timeCaption)\"))"))
        assertTrue(iosWrite.contains("dailyTargetMs - viewModel.elapsedMs > 0 ? \"remaining\" : \"written\""))
        assertTrue(androidWrite.contains("val remainingToTarget = state.dailyTargetMs - state.elapsedMs"))
        assertTrue(androidWrite.contains("""val writingTimeLabel = stringResource(R.string.writing_time_format, "${'$'}clockText ${'$'}timeCaption")"""))
        assertTrue(androidWrite.contains("contentDescription = writingTimeLabel"))
        assertTrue(androidStrings.contains("""name="writing_time_format""""))
        assertTrue(androidWriteStrings.contains("""name="write_timer_caption_remaining""""))
        assertTrue(androidWriteStrings.contains("""name="write_timer_caption_written""""))
        assertTrue(!androidWrite.contains("contentDescription = \"Writing time ${'$'}clockText\""))
    }

    @Test
    fun writeTopChromeUsesResourceBackedIosAccessibilityLabels() {
        val androidWrite = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/feature/write/WriteScreen.kt")
            .readText()
        val iosWrite = repoRoot()
            .resolve("apps/ios/Anky/Features/Write/WriteView.swift")
            .readText()
        val androidStrings = repoRoot()
            .resolve("apps/android/app/src/main/res/values/strings.xml")
            .readText()

        val androidWriteStrings = repoRoot()
            .resolve("apps/android/app/src/main/res/values/strings_write.xml")
            .readText()

        // The iOS top chrome's back chevron is labeled "Back"; the state
        // pill and quick-pass line are the only other chrome voices.
        assertTrue(iosWrite.contains("accessibilityLabel(AnkyLocalization.ui(\"Back\"))"))
        assertTrue(androidWrite.contains("val backLabel = stringResource(R.string.write_back)"))
        assertTrue(androidWrite.contains("contentDescription = backLabel"))
        assertTrue(androidWriteStrings.contains("""name="write_back""""))
        listOf(
            "write_pill_empty",
            "write_pill_writing",
            "write_pill_writing_daily_only",
            "write_pill_quick",
            "write_pill_daily",
        ).forEach { key ->
            assertTrue(androidWrite.contains("R.string.$key"))
            assertTrue(androidWriteStrings.contains("""name="$key""""))
        }
        assertTrue(!androidWrite.contains("contentDescription = pasteArtifactLabel"))
        assertTrue(!androidWrite.contains("onClick(pasteArtifactLabel)"))
        assertTrue(!androidWrite.contains("onLongClick(devPasteArtifactLabel)"))
        assertTrue(!androidWrite.contains("contentDescription = \"Back\""))
        assertTrue(!androidWrite.contains("contentDescription = \"Paste .anky artifact\""))
        assertTrue(!androidWrite.contains("onClick(\"Paste .anky artifact\")"))
    }

    @Test
    fun writePasteHasIosHiddenDevFixtureHold() {
        val androidWrite = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/feature/write/WriteScreen.kt")
            .readText()
        val androidWriteModel = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/feature/write/WriteViewModel.kt")
            .readText()
        val androidStrings = repoRoot()
            .resolve("apps/android/app/src/main/res/values/strings.xml")
            .readText()
        val androidFixture = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/feature/write/DevAnkyFixture.kt")
            .readText()
        val iosWrite = repoRoot()
            .resolve("apps/ios/Anky/Features/Write/WriteView.swift")
            .readText()
        val iosWriteModel = repoRoot()
            .resolve("apps/ios/Anky/Features/Write/WriteViewModel.swift")
            .readText()

        assertTrue(!iosWrite.contains("WriteToolbarPasteButton("))
        assertTrue(!iosWrite.contains("LongPressGesture(minimumDuration: 5)"))
        assertTrue(iosWriteModel.contains("func importAnkyArtifact(_ text: String) -> Bool"))

        assertTrue(!androidWrite.contains("DevPasteChromeButton("))
        assertTrue(!androidWrite.contains("R.string.hold_dev_paste_anky_artifact"))
        assertTrue(androidStrings.contains("Hold for five seconds to paste the built-in dev .anky"))
        assertTrue(androidWriteModel.contains("val devSampleAnkyArtifact: String"))
        assertTrue(androidWriteModel.contains("DevAnkyFixture.validArtifact"))
        assertTrue(androidFixture.contains("8000"))
    }

    @Test
    fun shortSessionTryAgainRoutesThroughRootRetryWritingLikeIos() {
        val androidApp = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/app/AnkyApp.kt")
            .readText()
        val androidReveal = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/feature/reveal/RevealScreen.kt")
            .readText()
        val androidRevealViewModel = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/feature/reveal/RevealViewModel.kt")
            .readText()
        val androidWriteModel = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/feature/write/WriteViewModel.kt")
            .readText()
        val androidWrite = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/feature/write/WriteScreen.kt")
            .readText()
        val androidStrings = repoRoot()
            .resolve("apps/android/app/src/main/res/values/strings.xml")
            .readText()
        val iosApp = repoRoot()
            .resolve("apps/ios/Anky/AppRoot.swift")
            .readText()
        val iosReveal = repoRoot()
            .resolve("apps/ios/Anky/Features/Reveal/RevealView.swift")
            .readText()
        assertTrue(iosApp.contains("private func beginRetryWriting()"))
        assertTrue(iosApp.contains("writeViewModel.clearCompletedSession()"))
        assertTrue(iosApp.contains("writeViewModel.openWritingPortal()"))
        assertTrue(iosReveal.contains("WRITE %d MINUTES\", AnkyDuration.completeRitualMinutes"))
        assertTrue(iosReveal.contains("onTryAgain()"))
        assertTrue(iosApp.contains("private func beginContinuingWriting(from artifact: SavedAnky)"))
        assertTrue(iosApp.contains("writeViewModel.continueSession(from: artifact)"))

        assertTrue(androidApp.contains("fun beginRetryWriting()"))
        assertTrue(androidApp.contains("fun beginContinuingWriting(artifact: SavedAnky)"))
        assertTrue(androidApp.contains("writeViewModelWithCurrentMirror.clearCompletedSession()"))
        assertTrue(androidApp.contains("writeViewModelWithCurrentMirror.continueSession(artifact)"))
        assertTrue(androidApp.contains("writeViewModelWithCurrentMirror.consumeCompletedHash()"))
        assertTrue(androidApp.contains("writeViewModelWithCurrentMirror.openWritingPortal()"))
        assertTrue(androidWriteModel.contains("val restored = AnkyWriter.fromDraft(artifact.text)"))
        assertTrue(androidWriteModel.contains("""if (restored.isClosed) error("Closed .anky artifacts cannot be continued.")"""))
        assertTrue(androidWriteModel.contains("isFrozenForContinuation = true"))
        assertTrue(androidWriteModel.contains("val isFrozenForContinuation: Boolean = false"))
        assertTrue(androidWriteModel.contains("isFrozenForContinuation = isFrozenForContinuation"))
        assertTrue(androidWriteModel.contains("continuedArtifactToReplace = artifact"))
        assertTrue(androidWriteModel.contains("writer.prepareToResume(now)"))
        assertTrue(androidWriteModel.contains("isFrozenForContinuation = false"))
        assertTrue(androidWriteModel.contains("archive.delete(replacedArtifact.hash)"))
        assertTrue(androidWriteModel.contains("indexStore.delete(replacedArtifact.hash)"))
        assertTrue(androidWrite.contains("showContinuationBack = state.isFrozenForContinuation"))
        assertTrue(androidWrite.contains("AnimatedVisibility("))
        assertTrue(androidWrite.contains("visible = !hasActiveDotAnky || showContinuationBack"))
        assertTrue(androidWrite.contains("onClick = if (showContinuationBack) onBackFromContinuation else onCloseToMap"))
        assertTrue(androidApp.contains("onBackFromContinuation = {"))
        assertTrue(androidApp.contains("navController.popBackStack()"))
        assertTrue(androidApp.contains("onTryAgain = { artifact -> beginContinuingWriting(artifact) }"))
        assertTrue(androidReveal.contains("state.canContinueWriting -> labels.continueWritingLeft(state.remainingWritingTime)"))
        assertTrue(androidRevealViewModel.contains("val remainingWritingTime: String"))
        assertTrue(androidRevealViewModel.contains("val canContinueWriting: Boolean"))
        assertTrue(androidReveal.contains("writeMinutes = stringResource(R.string.write_minutes_caps, AnkyDuration.CompleteRitualMinutes)"))
        assertTrue(androidStrings.contains("""name="continue_writing_left">Continue - %1${'$'}s left</string>"""))
        assertTrue(androidStrings.contains("""name="write_minutes_caps">WRITE %1${'$'}d MINUTES</string>"""))
        assertTrue(!androidReveal.contains("onTryAgain = onBack"))
    }

    @Test
    fun revealDeletionRefreshesRootAndMapLikeIos() {
        val androidApp = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/app/AnkyApp.kt")
            .readText()
        val androidReveal = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/feature/reveal/RevealScreen.kt")
            .readText()
        val androidMap = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/feature/map/MapScreen.kt")
            .readText()
        val iosApp = repoRoot()
            .resolve("apps/ios/Anky/AppRoot.swift")
            .readText()
        val iosMap = repoRoot()
            .resolve("apps/ios/Anky/Features/Map/MapView.swift")
            .readText()
        val iosReveal = repoRoot()
            .resolve("apps/ios/Anky/Features/Reveal/RevealView.swift")
            .readText()

        assertTrue(iosMap.contains("onDeleted: viewModel.refresh"))
        assertTrue(iosReveal.contains("onDeleted()"))
        assertTrue(iosReveal.contains("dismiss()"))

        assertTrue(androidReveal.contains("onDeleted: () -> Unit = {}"))
        assertTrue(androidReveal.contains("onDeleted()"))
        assertTrue(androidReveal.contains("onBack()"))
        assertTrue(androidApp.contains("val mapViewModel = remember"))
        assertTrue(androidApp.contains("onDeleted = {"))
        assertTrue(androidApp.contains("writeViewModelWithCurrentMirror.consumeCompletedHash()"))
        assertTrue(androidApp.contains("mapViewModel.refresh()"))
        assertTrue(androidMap.contains("val selectedDayEpoch = rememberSaveable"))
        assertTrue(androidMap.contains("state.days.firstOrNull { it.dayEpochMs == epoch }"))
        assertTrue(!androidMap.contains("mutableStateOf<SessionDay?>(null)"))
    }

    @Test
    fun revealDeleteControlLabelAndDangerStyleMatchIos() {
        val androidReveal = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/feature/reveal/RevealScreen.kt")
            .readText()
        val iosReveal = repoRoot()
            .resolve("apps/ios/Anky/Features/Reveal/RevealView.swift")
            .readText()
        val androidStrings = repoRoot()
            .resolve("apps/android/app/src/main/res/values/strings.xml")
            .readText()

        assertTrue(iosReveal.contains("accessibilityLabel(AnkyLocalization.ui(\"Delete writing session\"))") || iosReveal.contains("accessibilityLabel: \"Delete writing session\""))
        // Lazure: the one warning pigment is madder, never firetruck red.
        assertTrue(iosReveal.contains("Color.ankyMadder.opacity(0.88)"))
        assertTrue(!iosReveal.contains("Color.red.opacity(0.88)"))

        assertTrue(androidReveal.contains("RevealTopBar("))
        assertTrue(androidReveal.contains("deleteContentDescription = labels.deleteWritingSession"))
        assertTrue(androidReveal.contains("contentDescription = deleteContentDescription"))
        assertTrue(androidReveal.contains("val backLabel = stringResource(R.string.back)"))
        assertTrue(androidReveal.contains("contentDescription = backLabel"))
        assertTrue(!androidReveal.contains("contentDescription = \"Back\""))
        assertTrue(androidReveal.contains("LazurePigments.ankyMadder.copy(alpha = 0.88f)"))
        assertTrue(!androidReveal.contains("AnkyColors.Danger"))
        assertTrue(androidReveal.contains("title = { Text(labels.deleteWritingSessionQuestion) }"))
        assertTrue(androidReveal.contains("Text(labels.deleteWritingSessionBody)"))
        assertTrue(androidStrings.contains("Delete writing session?"))
        assertTrue(androidStrings.contains("This permanently deletes this writing session. This cannot be undone."))
        assertTrue(!androidReveal.contains("contentDescription = \"delete forever\""))
        assertTrue(!androidReveal.contains("Delete forever?"))
    }

    @Test
    fun revealAutoStartReflectionIsOneShotLikeIos() {
        val androidReveal = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/feature/reveal/RevealScreen.kt")
            .readText()
        val iosReveal = repoRoot()
            .resolve("apps/ios/Anky/Features/Reveal/RevealView.swift")
            .readText()

        assertTrue(iosReveal.contains("@State private var didAutoStartReflection = false"))
        assertTrue(iosReveal.contains("if startsReflectionOnAppear, !didAutoStartReflection, viewModel.reflection == nil"))
        assertTrue(iosReveal.contains("didAutoStartReflection = true"))

        assertTrue(androidReveal.contains("var inlineReflectionActive by remember { mutableStateOf(false) }"))
        assertTrue(androidReveal.contains("var didAutoStartReflection by remember { mutableStateOf(false) }"))
        assertTrue(androidReveal.contains("state.canSubmitReflectionRequest"))
        assertTrue(androidReveal.contains("state.reflectionVeiled"))
        assertTrue(androidReveal.contains("onOpenPaywall(\"reflection_veil\")"))
        assertTrue(androidReveal.contains("!didAutoStartReflection"))
        assertTrue(androidReveal.contains("state.reflection == null"))
        assertTrue(androidReveal.contains("didAutoStartReflection = true"))
        assertTrue(!androidReveal.contains("showCreditPurchaseSheet = true"))
        assertTrue(!androidReveal.contains("mutableStateOf(startsReflectionOnAppear)"))
    }

    @Test
    fun mapSessionRowsExposeIosAccessibilityMetadata() {
        val androidMap = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/feature/map/MapScreen.kt")
            .readText()
        val iosMap = repoRoot()
            .resolve("apps/ios/Anky/Features/Map/MapView.swift")
            .readText()

        assertTrue(iosMap.contains(".accessibilityLabel(accessibilityLabel)"))
        assertTrue(iosMap.contains("reflectedTitle,\n            session.preview"))
        assertTrue(iosMap.contains(".overlay(alignment: .bottom)"))
        assertTrue(iosMap.contains(".frame(height: 1.5)"))
        assertTrue(iosMap.contains("metadataHeader"))
        assertTrue(iosMap.contains("session.createdAt.formatted(date: .omitted, time: .shortened)"))
        assertTrue(iosMap.contains("displayTags"))
        assertTrue(iosMap.contains("Self.hashtag"))

        assertTrue(androidMap.contains(".semantics(mergeDescendants = true)"))
        assertTrue(androidMap.contains("contentDescription = sessionAccessibilityLabel(\n                    session = session,"))
        assertTrue(androidMap.contains("internal fun sessionAccessibilityLabel"))
        assertTrue(androidMap.contains("session.reflectedTitle(importedReflection),\n        session.localizedPreview(noReadableText)"))
        assertTrue(androidMap.contains("private fun SessionSummary.localizedPreview(noReadableText: String): String"))
        assertTrue(androidMap.contains("""noReadableText = stringResource(R.string.map_no_readable_text)"""))
        assertTrue(androidMap.contains("""importedReflection = stringResource(R.string.imported_reflection_title)"""))
        assertTrue(!androidMap.contains("sessionMetadataText(session)"))
        assertTrue(androidMap.contains("sessions = day.sessions.sortedByDescending { it.createdAt }"))
        assertTrue(androidMap.contains("items(sessions, key = { it.hash })"))
        assertTrue(androidMap.contains("session.createdAt.formattedForMapSessionTime(showsDayInHeader)"))
        assertTrue(androidMap.contains("val displayTags = session.displayTags()"))
        assertTrue(androidMap.contains("private fun SessionSummary.displayTags(): List<String>"))
        assertTrue(androidMap.contains("private fun String.asMapHashtag(): String?"))
        assertTrue(androidMap.contains(".horizontalScroll(rememberScrollState())"))
        assertTrue(androidMap.contains("MutableInteractionSource()"))
        assertTrue(androidMap.contains("indication = null"))
        assertTrue(androidMap.contains("fontSize = 16.sp,\n                        fontWeight = FontWeight.SemiBold,\n                        color = AnkyColors.Gold.copy(alpha = 0.78f)"))
        assertTrue(androidMap.contains("fontSize = 16.sp,\n                        fontWeight = FontWeight.Bold,\n                        color = AnkyColors.Gold"))
        assertTrue(androidMap.contains(".padding(top = 16.dp, bottom = 18.dp)"))
        assertTrue(!androidMap.contains("fontSize = 20.sp"))
        assertTrue(!androidMap.contains("lineHeight = 28.sp"))
        assertTrue(androidMap.contains("Spacer(Modifier.height(10.dp))"))
        assertTrue(androidMap.contains(".align(Alignment.BottomStart)"))
        assertTrue(androidMap.contains(".height(1.dp)"))
        assertTrue(iosMap.contains("let contentWidth = max(0, viewportWidth * 0.87)"))
        assertTrue(iosMap.contains("let horizontalPadding = max(0, (viewportWidth - contentWidth) / 2)"))
        assertTrue(androidMap.contains("val contentWidth = maxWidth * 0.87f"))
        assertTrue(androidMap.contains("val horizontalPadding = (maxWidth - contentWidth) / 2"))
        assertTrue(iosMap.contains(".padding(.top, 24)"))
        assertTrue(androidMap.contains(".padding(top = 34.dp, bottom = 104.dp)"))
        assertTrue(iosMap.contains(".padding(.bottom, bottomNavigationReserve)"))
        assertTrue(!androidMap.contains(".padding(horizontal = 26.dp, vertical = 24.dp)"))
        assertTrue(!iosMap.contains("Text(\"no writing saved\")"))
        assertTrue(androidMap.contains("emptyMessage = stringResource(R.string.all_ankys_empty_message)"))
        assertTrue(androidMap.contains("emptyMessage = stringResource(R.string.day_empty_message)"))
        assertTrue(androidMap.contains("Text(\n                            emptyMessage,"))
        assertTrue(!androidMap.contains("Text(\"no writing saved\", style = AnkyType.Body.copy(fontSize = 20.sp, color = AnkyColors.PaperMuted)"))
        assertTrue(!androidMap.contains("Text(\"no writing saved\", style = AnkyType.Heading.copy(fontSize = 20.sp"))
        assertTrue(!androidMap.contains("style = AnkyType.Heading.copy(fontSize = 20.sp, color = AnkyColors.PaperMuted)"))
    }

    @Test
    fun archiveChamberIsTheLiveMapSurfaceOnLazureWall() {
        // The old trail map is legacy; the iOS archive chamber (in
        // HomeDailyChamberView.swift) is the surface the map tab now shows.
        val androidMap = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/feature/map/MapScreen.kt")
            .readText()
        val androidArchive = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/feature/map/ArchiveChamberScreen.kt")
            .readText()
        val iosChamber = repoRoot()
            .resolve("apps/ios/Anky/Features/CheckIn/HomeDailyChamberView.swift")
            .readText()
        val iosRoot = repoRoot()
            .resolve("apps/ios/Anky/AppRoot.swift")
            .readText()

        assertTrue(iosChamber.contains("struct ArchiveChamberView: View"))
        assertTrue(iosRoot.contains("ArchiveChamberView("))

        // MapScreen keeps its entry name but delegates to the chamber.
        assertTrue(androidMap.contains("fun MapScreen("))
        assertTrue(androidMap.contains("ArchiveChamberScreen("))
        assertTrue(androidArchive.contains("fun ArchiveChamberScreen("))
        assertTrue(androidArchive.contains("LazureWall(mood = LazureMood.Dawn)"))
        assertTrue(!androidArchive.contains("map_background"))
        assertTrue(!androidArchive.contains("AnkyColors."))
    }

    @Test
    fun archiveChamberTitleAndDayHeadersUseIosSerifScale() {
        // "Your Writings" is a serif 36 title in ink; day buckets read
        // Today / Yesterday / dated, serif 21 in soft ink — iOS chamber.
        val androidArchive = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/feature/map/ArchiveChamberScreen.kt")
            .readText()
        val androidArchiveStrings = repoRoot()
            .resolve("apps/android/app/src/main/res/values/strings_archive.xml")
            .readText()
        val iosChamber = repoRoot()
            .resolve("apps/ios/Anky/Features/CheckIn/HomeDailyChamberView.swift")
            .readText()

        assertTrue(iosChamber.contains("""Text(AnkyLocalization.ui("Your Writings"))"""))
        assertTrue(iosChamber.contains(".font(.system(size: 36, weight: .regular, design: .serif))"))
        assertTrue(iosChamber.contains(".font(.system(size: 21, weight: .regular, design: .serif))"))
        assertTrue(iosChamber.contains("""title = "Today""""))
        assertTrue(iosChamber.contains("""title = "Yesterday""""))

        assertTrue(androidArchive.contains("R.string.archive_your_writings"))
        assertTrue(androidArchive.contains("fontSize = 36.sp"))
        assertTrue(androidArchive.contains("fontSize = 21.sp"))
        assertTrue(androidArchive.contains("fontFamily = FontFamily.Serif"))
        assertTrue(androidArchive.contains("R.string.archive_today"))
        assertTrue(androidArchive.contains("R.string.archive_yesterday"))
        assertTrue(androidArchiveStrings.contains("""name="archive_your_writings""""))
        assertTrue(androidArchiveStrings.contains(">Today<"))
        assertTrue(androidArchiveStrings.contains(">Yesterday<"))
    }

    @Test
    fun mapTrailDayNodesExposeIosAccessibilityLabel() {
        val androidMap = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/feature/map/MapScreen.kt")
            .readText()
        val iosMap = repoRoot()
            .resolve("apps/ios/Anky/Features/Map/MapView.swift")
            .readText()

        assertTrue(iosMap.contains(".accessibilityLabel(accessibilityLabel)"))
        assertTrue(iosMap.contains("let date = day.isToday ? AnkyLocalization.ui(\"Today\") : formattedUTCDate(day.date, dateFormat: nil)"))
        assertTrue(iosMap.contains("return \"\\(date), \\(AnkyLocalization.ui(day.trailActivitySummary))\""))

        assertTrue(androidMap.contains("contentDescription = dayAccessibilityLabel(\n                    day = day,"))
        assertTrue(androidMap.contains("internal fun dayAccessibilityLabel"))
        assertTrue(androidMap.contains("today = stringResource(R.string.map_today)"))
        assertTrue(androidMap.contains("noWritingLabel = labels.noWriting"))
        assertTrue(androidMap.contains("showedUpLabel = labels.showedUp"))
        assertTrue(androidMap.contains("noCompleteAnkyLabel = labels.noCompleteAnky"))
        assertTrue(androidMap.contains("private fun SessionDay.localizedTrailActivitySummary("))
        assertTrue(androidMap.contains("""noWriting = stringResource(R.string.map_no_writing)"""))
        assertTrue(androidMap.contains("""noCompleteAnky = stringResource(R.string.map_no_complete_anky)"""))
    }

    @Test
    fun mapProgressAndCompletionMarkerExposeIosAccessibilityLabels() {
        val androidMap = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/feature/map/MapScreen.kt")
            .readText()
        val iosMap = repoRoot()
            .resolve("apps/ios/Anky/Features/Map/MapView.swift")
            .readText()

        assertTrue(iosMap.contains(".accessibilityLabel(AnkyLocalization.ui(\"UTC day progress\"))"))
        assertTrue(iosMap.contains(".accessibilityLabel(AnkyLocalization.ui(\"showed up\"))"))

        assertTrue(androidMap.contains("stringResource(R.string.map_utc_day_progress)"))
        assertTrue(androidMap.contains("contentDescription = label"))
        assertTrue(androidMap.contains("DayCompletionMarker(labels.showedUp"))
        assertTrue(androidMap.contains("this.contentDescription = contentDescription"))
    }

    @Test
    fun archiveChamberSearchCacheAndRowsMatchIosCanon() {
        // Search runs over a lowercased reconstructed-text cache keyed by
        // hash, built once per load and off the main thread; rows show the
        // words, the time, and the length — never counts, never the
        // protocol status word for an unsealed session.
        val androidArchive = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/feature/map/ArchiveChamberScreen.kt")
            .readText()
        val androidSearch = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/feature/map/ArchiveSearch.kt")
            .readText()
        val iosChamber = repoRoot()
            .resolve("apps/ios/Anky/Features/CheckIn/HomeDailyChamberView.swift")
            .readText()

        assertTrue(iosChamber.contains("(${'$'}0.hash, ${'$'}0.reconstructedText.lowercased())"))
        assertTrue(iosChamber.contains("searchableText[${'$'}0.hash]?.contains(query) == true"))
        assertTrue(iosChamber.contains("AnkyDuration.clock(anky.durationMs)"))

        assertTrue(androidSearch.contains("it.hash to it.reconstructedText.lowercase()"))
        assertTrue(androidSearch.contains("cache[it.hash]?.contains(needle) == true"))
        assertTrue(androidArchive.contains("withContext(Dispatchers.Default)"))
        assertTrue(androidArchive.contains("ArchiveSearchIndex.build(entries)"))
        assertTrue(androidArchive.contains("AnkyDuration.clock(anky.durationMs)"))
        // iOS canon: never the F-word for unsealed sessions, no counts.
        assertTrue(!androidArchive.contains("Fragment"))
        assertTrue(!androidArchive.contains("wordCount"))
        assertTrue(!androidArchive.contains("completeCount"))
        assertTrue(!androidSearch.contains("Fragment"))
    }

    @Test
    fun mapTrailTimelineScrollsWithNodesLikeIosStraightTimeline() {
        val androidMap = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/feature/map/MapScreen.kt")
            .readText()
        val iosMap = repoRoot()
            .resolve("apps/ios/Anky/Features/Map/MapView.swift")
            .readText()

        assertTrue(iosMap.contains("path.move(to: CGPoint(x: x, y: rowHeight / 2))"))
        assertTrue(iosMap.contains("path.addLine(to: CGPoint(x: x, y: rowHeight * CGFloat(dayCount - 1) + rowHeight / 2))"))
        assertTrue(iosMap.contains(".frame(height: rowHeight * CGFloat(max(dayCount, 1)))"))
        assertTrue(iosMap.contains("proxy.scrollTo(todayDate, anchor: .center)"))

        assertTrue(androidMap.contains("TrailDayNode(\n                    day = day,\n                    index = index,\n                    dayCount = displayDays.size"))
        assertTrue(androidMap.contains("val centerPadding = ((maxHeight - rowHeight) / 2).coerceAtLeast(0.dp)"))
        assertTrue(androidMap.contains("contentPadding = PaddingValues("))
        assertTrue(androidMap.contains("top = centerPadding"))
        assertTrue(androidMap.contains("bottom = centerPadding + maxHeight"))
        assertTrue(!androidMap.contains("Spacer(Modifier.height(156.dp))"))
        assertTrue(androidMap.contains("Canvas(Modifier.fillMaxSize())"))
        assertTrue(androidMap.contains("if (dayCount <= 1) return@Canvas"))
        assertTrue(androidMap.contains("val centerY = size.height / 2f"))
        assertTrue(androidMap.contains("val startY = if (index == 0) centerY else 0f"))
        assertTrue(androidMap.contains("val endY = if (index == dayCount - 1) centerY else size.height"))
        assertTrue(!androidMap.contains("Canvas(Modifier.fillMaxSize()) {\n            if (displayDays.isEmpty()) return@Canvas"))
    }

    @Test
    fun mapCurrentDayButtonUsesIosLikeCircularMaterialHitTarget() {
        val androidMap = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/feature/map/MapScreen.kt")
            .readText()
        val iosMap = repoRoot()
            .resolve("apps/ios/Anky/Features/Map/MapView.swift")
            .readText()

        assertTrue(iosMap.contains(".frame(width: 48, height: 48)"))
        assertTrue(iosMap.contains(".background(.thinMaterial, in: Circle())"))
        assertTrue(iosMap.contains(".accessibilityLabel(AnkyLocalization.ui(\"Go to current day\"))"))

        assertTrue(androidMap.contains(".size(48.dp)\n                    .clip(CircleShape)"))
        assertTrue(androidMap.contains(".background(Color.White.copy(alpha = 0.12f))"))
        assertTrue(androidMap.contains("contentDescription = labels.goToCurrentDay"))
        assertTrue(androidMap.contains("contentDescription = null"))
        assertTrue(!androidMap.contains(".background(Color.Black.copy(alpha = 0.28f))"))
    }

    @Test
    fun mapVisibleLabelsUseResourceBackedIosLocalizedCopy() {
        val androidMap = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/feature/map/MapScreen.kt")
            .readText()
        val androidStrings = repoRoot()
            .resolve("apps/android/app/src/main/res/values/strings.xml")
            .readText()
        val iosMap = repoRoot()
            .resolve("apps/ios/Anky/Features/Map/MapView.swift")
            .readText()
        val iosLocalization = repoRoot()
            .resolve("apps/ios/Anky/en.lproj/Localizable.strings")
            .readText()

        assertTrue(iosMap.contains(".accessibilityLabel(AnkyLocalization.ui(\"Go to current day\"))"))
        assertTrue(iosMap.contains(".accessibilityLabel(AnkyLocalization.ui(\"UTC day progress\"))"))
        assertTrue(iosMap.contains(".accessibilityLabel(AnkyLocalization.ui(\"showed up\"))"))
        assertTrue(iosLocalization.contains("\"Go to current day\" = \"Go to current day\";"))
        assertTrue(iosLocalization.contains("\"UTC day progress\" = \"UTC day progress\";"))
        assertTrue(iosLocalization.contains("\"showed up\" = \"showed up\";"))

        listOf(
            "map_no_writing_saved",
            "map_go_to_current_day",
            "map_today",
            "map_utc_day_progress",
            "map_showed_up",
            "map_back",
            "map_could_not_load",
        ).forEach { key ->
            assertTrue(androidStrings.contains("""name="$key""""))
            assertTrue(androidMap.contains("R.string.$key"))
        }
        assertTrue(!androidMap.contains("contentDescription = \"Go to current day\""))
        assertTrue(!androidMap.contains("contentDescription = \"UTC day progress\""))
        assertTrue(!androidMap.contains("contentDescription = \"showed up\""))
        assertTrue(!androidMap.contains("contentDescription = \"Back\""))
    }

    @Test
    fun mapRefreshFallsBackToExistingIndexLikeCurrentIos() {
        val androidMapModel = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/feature/map/MapViewModel.kt")
            .readText()
        val iosMapModel = repoRoot()
            .resolve("apps/ios/Anky/Features/Map/MapViewModel.swift")
            .readText()

        assertTrue(iosMapModel.contains("let storedFirstOpenDate = appOpenStore.loadOrCreate()"))
        assertTrue(iosMapModel.contains("(try? sessionIndexStore.rebuild(archive: archive, reflectionStore: reflectionStore)) ?? sessionIndexStore.load()"))

        assertTrue(androidMapModel.contains("val storedFirstOpen = appOpenStore.loadOrCreate()"))
        assertTrue(androidMapModel.contains("indexStore.rebuild(archive, reflectionStore)"))
        assertTrue(androidMapModel.contains("}.getOrElse {"))
        assertTrue(androidMapModel.contains("indexStore.load()"))
        assertTrue(androidMapModel.contains("?: storedFirstOpen"))
    }

    @Test
    fun mapStatsOpenCurrentIosAllAnkysHistory() {
        val iosMap = repoRoot()
            .resolve("apps/ios/Anky/Features/Map/MapView.swift")
            .readText()
        val iosMapModel = repoRoot()
            .resolve("apps/ios/Anky/Features/Map/MapViewModel.swift")
            .readText()
        val androidMap = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/feature/map/MapScreen.kt")
            .readText()
        val androidMapModel = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/feature/map/MapViewModel.kt")
            .readText()
        val androidNav = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/app/AnkyNav.kt")
            .readText()
        val androidApp = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/app/AnkyApp.kt")
            .readText()

        assertTrue(iosMap.contains("openAllAnkys: {"))
        assertTrue(iosMap.contains("path.append(.allAnkys)"))
        assertTrue(iosMap.contains("case .allAnkys:"))
        assertTrue(iosMap.contains("MapAllAnkysHistoryView("))
        assertTrue(iosMap.contains("sessions: viewModel.completeAnkySessions"))
        assertTrue(iosMap.contains("showsDayInHeader: true"))
        assertTrue(iosMapModel.contains("@Published private(set) var completeAnkySessions: [SessionSummary] = []"))
        assertTrue(iosMapModel.contains("completeAnkySessions = completeSessions.sorted { ${'$'}0.createdAt > ${'$'}1.createdAt }"))

        assertTrue(androidMap.contains("fun MapAllAnkysScreen("))
        assertTrue(androidMap.contains("val sessions = state.completeAnkySessions"))
        assertTrue(androidMap.contains("stringResource(R.string.zero_ankys)"))
        assertTrue(androidMap.contains("stringResource(R.string.one_anky_count_format, sessions.size)"))
        assertTrue(androidMap.contains("stringResource(R.string.ankys_count_format, sessions.size)"))
        assertTrue(androidMap.contains("showsDayInHeader = true"))
        assertTrue(androidMap.contains("onOpenAllAnkys: () -> Unit"))
        assertTrue(androidMap.contains(".clickable(role = Role.Button, onClick = onClick)"))
        assertTrue(androidMap.contains("contentDescription = labels.openAllAnkys"))
        assertTrue(androidMapModel.contains("val completeAnkySessions: List<SessionSummary> = emptyList()"))
        assertTrue(androidMapModel.contains("completeAnkySessions = completeSessions.sortedByDescending { it.createdAt }"))
        assertTrue(androidNav.contains("data object MapAllAnkys"))
        assertTrue(androidApp.contains("onOpenAllAnkys = { navController.navigate(AnkyRoute.MapAllAnkys.route) }"))
        assertTrue(androidApp.contains("composable(AnkyRoute.MapAllAnkys.route)"))
        assertTrue(androidApp.contains("currentRoute == AnkyRoute.Map.route || currentRoute == AnkyRoute.MapAllAnkys.route"))
    }

    @Test
    fun tagSessionsRefreshOnReturnLikeIosOnAppear() {
        val androidTags = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/feature/reveal/TagSessionsScreen.kt")
            .readText()
        val androidReveal = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/feature/reveal/RevealScreen.kt")
            .readText()
        val iosTags = repoRoot()
            .resolve("apps/ios/Anky/Features/Reveal/TagSessionsListView.swift")
            .readText()
        val iosReveal = repoRoot()
            .resolve("apps/ios/Anky/Features/Reveal/RevealView.swift")
            .readText()
        val androidStrings = repoRoot()
            .resolve("apps/android/app/src/main/res/values/strings.xml")
            .readText()

        assertTrue(iosTags.contains(".onAppear {"))
        assertTrue(iosTags.contains("sessions = sessionIndexStore.sessionsWithTag(tag)"))
        // Lazure: the tag room sits on the breathing paper wall now.
        assertTrue(iosTags.contains("LazureWall(mood: .dawn)"))
        assertTrue(!iosTags.contains("RevealBackgroundTexture()"))
        assertTrue(iosTags.contains("Text(tag)"))
        assertTrue(iosTags.contains("""Text(AnkyLocalization.ui("no saved sessions with this tag."))"""))
        assertTrue(iosTags.contains("""AnkyLocalization.ui(summary.wordCount == 1 ? "word" : "words")"""))
        assertTrue(androidTags.contains("fun refreshSessions()"))
        assertTrue(androidTags.contains("sessionIndexStore.sessionsWithTag(tag)"))
        assertTrue(androidTags.contains("LazureWall(mood = LazureMood.Dawn)"))
        assertTrue(!androidTags.contains("RevealTagTexture()"))
        assertTrue(androidTags.contains("val backLabel = stringResource(R.string.back)"))
        assertTrue(androidTags.contains("contentDescription = backLabel"))
        assertTrue(!androidTags.contains("contentDescription = \"Back\""))
        assertTrue(androidStrings.contains("""name="tag_no_saved_sessions">no saved sessions with this tag.</string>"""))
        assertTrue(androidTags.contains("val emptyTagSessionsLabel = stringResource(R.string.tag_no_saved_sessions)"))
        assertTrue(androidTags.contains("emptyTagSessionsLabel,"))
        assertTrue(androidTags.contains("val wordLabel = stringResource(if (summary.wordCount == 1) R.string.word else R.string.words)"))
        assertTrue(androidTags.contains("""${'$'}{summary.wordCount} ${'$'}wordLabel"""))
        assertTrue(!androidTags.contains(""""no saved sessions with this tag.","""))
        assertTrue(!androidTags.contains("""if (summary.wordCount == 1) "word" else "words""""))
        listOf("values-es", "values-fr", "values-de", "values-hi", "values-zh-rCN").forEach { localeDir ->
            val localizedStrings = repoRoot()
                .resolve("apps/android/app/src/main/res/$localeDir/strings.xml")
                .readText()
            assertTrue(localizedStrings.contains("tag_no_saved_sessions"))
            assertTrue(localizedStrings.contains("word"))
            assertTrue(localizedStrings.contains("words"))
        }
        // Lazure remap: no dark-era violet bloom canvas, no dark ink wall —
        // the tag title reads serif violet on paper, like the iOS heading.
        assertTrue(!androidTags.contains("AnkyColors.Violet.copy(alpha = alpha)"))
        assertTrue(!androidTags.contains("Triple(1.34f, 360.dp.toPx(), 0.018f)"))
        assertTrue(androidTags.contains("Text(\n                        tag,"))
        assertTrue(iosTags.contains(".font(.system(size: 30, weight: .bold, design: .serif))"))
        assertTrue(iosTags.contains("RevealPalette.markdownHeading"))
        assertTrue(
            androidTags.contains("fontFamily = FontFamily.Serif") &&
                androidTags.contains("fontSize = 30.sp") &&
                androidTags.contains("color = LazurePigments.ankyViolet"),
        )
        assertTrue(iosTags.contains(".padding(.top, 18)"))
        assertTrue(androidTags.contains("Modifier.padding(top = 18.dp)"))
        assertTrue(iosTags.contains(".padding(.horizontal, 22)"))
        assertTrue(androidTags.contains(".padding(horizontal = 22.dp)"))
        assertTrue(iosTags.contains(".padding(.bottom, 48)"))
        assertTrue(androidTags.contains(".padding(bottom = 48.dp)"))
        assertTrue(iosTags.contains(".padding(.top, 8)"))
        assertTrue(androidTags.contains("Modifier.padding(top = 8.dp)"))
        assertTrue(!androidTags.contains("fontSize = 26.sp, color = AnkyColors.Gold"))
        assertTrue(androidReveal.contains("Text(\n                    tag,"))
        assertTrue(androidReveal.contains("Modifier.horizontalScroll(tagScrollState)"))
        assertTrue(androidTags.contains("Lifecycle.Event.ON_RESUME"))
        assertTrue(androidTags.contains("lifecycleOwner.lifecycle.addObserver(observer)"))
        assertTrue(androidTags.contains("lifecycleOwner.lifecycle.removeObserver(observer)"))
        assertTrue(iosTags.contains("summary.createdAt.formatted(date: .abbreviated, time: .shortened)"))
        assertTrue(androidTags.contains("ofLocalizedDateTime(FormatStyle.MEDIUM, FormatStyle.SHORT)"))
        assertTrue(iosTags.contains(".font(.system(size: 12, weight: .medium, design: .monospaced))"))
        assertTrue(androidTags.contains("fontSize = 12.sp, fontWeight = FontWeight.Medium, color = LazurePigments.ankyInkSoft.copy(alpha = 0.88f)"))
        assertTrue(androidTags.contains("fontSize = 12.sp, fontWeight = FontWeight.Medium, color = LazurePigments.ankyInkSoft.copy(alpha = 0.72f)"))
        assertTrue(!androidTags.contains("AnkyColors."))
        assertTrue(iosTags.contains(".font(.system(size: 13, weight: .semibold))"))
        assertTrue(androidTags.contains("modifier = Modifier.size(13.dp)"))
        assertTrue(!androidTags.contains("tag.lowercase()"))
        assertTrue(!androidReveal.contains("tag.lowercase()"))
        assertTrue(!androidReveal.contains("chunked(4)"))
        assertTrue(!androidTags.contains("MMM d, yyyy / h:mm a"))
        assertTrue(!androidTags.contains("format(summary.createdAt)\n                    .lowercase()"))
    }

    @Test
    fun writeImportFailureCopyMatchesCurrentIos() {
        val androidWrite = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/feature/write/WriteScreen.kt")
            .readText()
        val androidImporter = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/core/storage/SingleAnkyImporter.kt")
            .readText()
        val iosWriteModel = repoRoot()
            .resolve("apps/ios/Anky/Features/Write/WriteViewModel.swift")
            .readText()
        val iosArchive = repoRoot()
            .resolve("apps/ios/Anky/Core/Storage/LocalAnkyArchive.swift")
            .readText()
        val androidStrings = repoRoot()
            .resolve("apps/android/app/src/main/res/values/strings.xml")
            .readText()

        assertTrue(iosWriteModel.contains("i couldn't find a readable .anky in that."))
        assertTrue(iosWriteModel.contains("i couldn't open that .anky yet."))
        assertTrue(androidWrite.contains("val importReadableError = stringResource(R.string.write_import_readable_error)"))
        assertTrue(androidWrite.contains("val importOpenError = stringResource(R.string.write_import_open_error)"))
        assertTrue(androidWrite.contains("importError = importReadableError"))
        assertTrue(androidWrite.contains("importError = importOpenError"))
        assertTrue(androidStrings.contains("""name="write_import_readable_error""""))
        assertTrue(androidStrings.contains("""name="write_import_open_error""""))
        assertTrue(!androidWrite.contains("importError = \"i couldn't find a readable .anky in that.\""))
        assertTrue(!androidWrite.contains("importError = \"i couldn't open that .anky yet.\""))
        assertTrue(iosArchive.contains("func importArtifact(_ ankyText: String) throws -> SavedAnky"))
        assertTrue(iosArchive.contains("fencedCodeBlocks(in: prepared)"))
        assertTrue(iosArchive.contains("extractedProtocolBlock(from: prepared)"))
        assertTrue(androidImporter.contains("private fun importCandidates(text: String): List<String>"))
        assertTrue(androidImporter.contains("fencedCodeBlocks(prepared).forEach(::append)"))
        assertTrue(androidImporter.contains("extractedProtocolBlock(prepared)?.let(::append)"))
        assertTrue(androidImporter.contains("validation is AnkyValidation.Valid && validation.isComplete"))
        assertTrue(!androidWrite.contains("I could not find a .anky rhythm in that."))
        assertTrue(!androidWrite.contains("I could not open that artifact."))
    }

    @Test
    fun revealCompanionThinkingAndReflectionCopyMatchCurrentIos() {
        val androidReveal = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/feature/reveal/RevealScreen.kt")
            .readText()
        val androidRevealModel = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/feature/reveal/RevealViewModel.kt")
            .readText()
        val iosReveal = repoRoot()
            .resolve("apps/ios/Anky/Features/Reveal/RevealView.swift")
            .readText()
        val iosRevealModel = repoRoot()
            .resolve("apps/ios/Anky/Features/Reveal/RevealViewModel.swift")
            .readText()
        val androidStrings = repoRoot()
            .resolve("apps/android/app/src/main/res/values")
            .listFiles { file -> file.extension == "xml" }
            .orEmpty()
            .joinToString("\n") { it.readText() }

        listOf(
            "copy_writing",
            "read_reflection",
            "reflect_this_anky",
            "receiving_reflection",
            "write_minutes_caps",
            "copy_reflection",
            "copy_reflection_prompt_hint",
            "copied_reflection",
            "copied_writing",
            "reflection_prompt_copied",
            "reflection_prompt_clipboard_guidance",
            "reflection_left",
            "reflections_left",
            "reveal_toggle_privacy_message",
            "reveal_mirror_forming",
            "reveal_live",
            "reveal_writing_reflection_characters",
            "reveal_anky_drawing_thread",
            "reveal_anky_reading",
            "reveal_chat_staying_with_anky",
            "reveal_chat_reading_slowly",
            "reveal_chat_open_mirror",
            "reveal_chat_write_again",
            "reveal_chat_has_reflection",
            "reveal_chat_read_reflection",
            "reveal_chat_reflect_this_anky",
            "reveal_see_what_anky_saw",
            "reveal_subscription_opens_reflections",
            "reveal_sheet_mirror",
            "reveal_sheet_tags",
            "reveal_progress_complete",
            "reveal_progress_receiving",
            "reveal_progress_chars",
            "reveal_invitation_checking_mirror",
            "reveal_invitation_access_empty",
            "reveal_invitation_mirror_may_be_open",
            "reveal_invitation_ready",
            "reveal_ready_to_mirror_artifact",
            "reveal_short_keep_going",
            "reveal_short_thread_opened",
            "reveal_short_spark",
            "reveal_short_whole_ritual",
            "reveal_short_cross_mark",
        ).forEach { key ->
            assertTrue("Missing reveal string resource: $key", androidStrings.contains("""name="$key""""))
        }
        assertTrue(androidReveal.contains("seeWhatAnkySaw = stringResource(R.string.reveal_see_what_anky_saw)"))
        assertTrue(androidReveal.contains("reflectThisAnky = stringResource(R.string.reflect_this_anky)"))
        assertTrue(androidReveal.contains("receivingReflection = stringResource(R.string.receiving_reflection)"))
        assertTrue(!androidReveal.contains("reflectThisAnkyDeviceGift"))
        assertTrue(!androidReveal.contains("R.string.reflect_this_anky_device_gift"))
        assertTrue(!androidStrings.contains("""name="reflect_this_anky_device_gift""""))
        assertTrue(!androidReveal.contains("i have reflected this anky."))
        assertTrue(!androidReveal.contains("i am holding the mirror open."))
        assertTrue(androidReveal.contains("StreamingReflectionPanel("))
        assertTrue(androidReveal.contains("ReflectionProgressPanel("))
        assertTrue(androidReveal.contains("SavedReflectionPanel("))
        assertTrue(!androidReveal.contains("hide live text"))
        assertTrue(androidReveal.contains("state.canSubmitReflectionRequest"))
        assertTrue(androidReveal.contains("viewModel.askAnky()"))
        assertTrue(!androidReveal.contains("the reflection is not here yet."))
        assertTrue(androidReveal.contains("state.streamingReflectionMarkdown.isNotBlank() ->"))
        assertTrue(androidReveal.contains("state.isAsking -> {"))
        assertTrue(androidReveal.contains("(state.reflection == null || !isReflectionVisible)"))
        assertTrue(androidReveal.contains("state.isAsking -> labels.receivingReflection"))
        assertTrue(!androidReveal.contains("state.streamingReflectionMarkdown.isNotBlank() || state.isAsking"))
        assertTrue(!androidReveal.contains("state.streamingReflectionMarkdown.isBlank() &&\n        !isReflectionVisible"))
        assertTrue(androidReveal.contains("MarkdownishText(body)"))
        assertTrue(androidReveal.contains("generatedCharacters = state.streamingReflectionCharacterCount"))
        assertTrue(androidReveal.contains("labels.statusWritingReflection"))
        assertTrue(androidReveal.contains("MarkdownishText(reflection.displayBody)"))
        assertTrue(androidReveal.contains("tags.forEach { tag ->"))
        assertTrue(!androidReveal.contains("tags.take(8).forEach"))
        assertTrue(androidReveal.contains("AnkyType.Mono.copy("))
        assertTrue(androidReveal.contains("letterSpacing = 1.sp"))
        assertTrue(androidReveal.contains("RevealLazure.paperDeep.copy(alpha = 0.55f)"))
        assertTrue(androidReveal.contains("fontSize = 12.sp, fontWeight = FontWeight.Medium, color = RevealLazure.gold"))
        assertTrue(androidReveal.contains("Column(modifier = Modifier.padding(top = 2.dp), verticalArrangement = Arrangement.spacedBy(8.dp))"))
        assertTrue(!androidReveal.contains("displayBodyWithTitle"))
        assertTrue(androidReveal.contains("private fun MirrorThreadProgress("))
        assertTrue(androidReveal.contains("mirrorForming = stringResource(R.string.reveal_mirror_forming)"))
        assertTrue(androidReveal.contains("labels.progressChars(generatedCharacters)"))
        assertTrue(androidReveal.contains("labels.sheetTags"))
        assertTrue(!androidReveal.contains("\"the mirror is forming\""))
        assertTrue(!androidReveal.contains("\"copied reflection\""))
        assertTrue(!androidReveal.contains("\"copied writing\""))
        assertTrue(!androidReveal.contains("\"copy reflection\""))
        listOf(
            "\"open mirror\"",
            "\"write again\"",
            "\"this anky has a reflection.\"",
            "\"read reflection\"",
            "\"reflect this anky\"",
            "\"open credits\"",
            "\"i am staying with this .anky.\"",
            "\"i am reading slowly. not looking for a summary.\"",
            "\"mirror\"",
            "\"tags\"",
            "\"complete\"",
            "\"receiving\"",
            "\"ready to mirror this artifact\"",
        ).forEach { literal ->
            assertTrue(!androidReveal.contains(literal))
        }
        assertTrue(!androidReveal.contains("\"${'$'}generatedCharacters chars\""))
        assertTrue(androidReveal.contains("inlineReflectionActive"))
        assertTrue(!androidReveal.contains("ModalBottomSheet("))
        assertTrue(!androidReveal.contains("RevealCreditPurchaseSheet("))
        assertTrue(androidReveal.contains("state.reflectionVeiled -> labels.seeWhatAnkySaw"))
        assertTrue(androidReveal.contains("private fun RevealEdgeBackSwipe("))
        assertTrue(androidReveal.contains(".width(32.dp)"))
        assertTrue(androidReveal.contains("detectDragGestures("))
        assertTrue(androidReveal.contains("totalDrag.x > 80.dp.toPx()"))
        assertTrue(androidReveal.contains("abs(totalDrag.y) < 60.dp.toPx()"))
        assertTrue(iosReveal.contains("private func isHorizontalRule"))
        assertTrue(androidReveal.contains("internal fun isMarkdownHorizontalRule"))
        assertTrue(androidReveal.contains("isMarkdownHorizontalRule(trimmed)"))
        assertTrue(androidReveal.contains("0.12f + generatedCharacters.toFloat() / 3200f"))
        assertTrue(!androidReveal.contains("% 1400"))
        assertTrue(androidReveal.contains("private fun MirrorThreadProgress("))
        assertTrue(androidReveal.contains("RevealLazure.paperDeep.copy(alpha = 0.72f)"))
        assertTrue(androidReveal.contains("RevealLazure.gold.copy(alpha = 0.22f)"))
        assertTrue(!androidReveal.contains("LinearProgressIndicator"))
        assertTrue(iosRevealModel.contains("""case "provider_started":"""))
        assertTrue(androidRevealModel.contains(""""provider_started" -> "anky is writing...""""))
        assertTrue(iosRevealModel.contains("""case "hash_computed":"""))
        assertTrue(iosRevealModel.contains("preparing your writing..."))
        assertTrue(androidRevealModel.contains(""""hash_computed" -> "preparing your writing...""""))
        assertTrue(iosRevealModel.contains("""case "identity_verified":"""))
        assertTrue(iosRevealModel.contains("opening the way..."))
        assertTrue(androidRevealModel.contains(""""identity_verified" -> "opening the way...""""))
        assertTrue(!androidRevealModel.contains("verifying the seal..."))
        assertTrue(!androidRevealModel.contains("confirming your identity..."))
        listOf(
            "reveal_status_opening_quiet_channel",
            "reveal_status_preparing_reflection",
            "reveal_status_carrying_thread",
            "reveal_status_threading_back",
            "reveal_status_already_holding_thread",
            "reveal_status_waiting_with_mirror",
            "reveal_status_writing_reflection",
            "reveal_progress_opening_mirror",
            "reveal_progress_received_writing",
            "reveal_progress_reading_anky",
            "reveal_progress_preparing_writing",
            "reveal_progress_opening_way",
            "reveal_progress_validating_ritual",
            "reveal_progress_checking_access",
            "reveal_progress_preparing_reflection",
            "reveal_progress_anky_writing",
            "reveal_progress_bringing_back",
            "reveal_progress_settling",
            "reveal_progress_checking_payment",
            "reveal_progress_payment_verified",
            "reveal_progress_no_credit_spent",
            "reveal_progress_opening_scroll",
            "reveal_error_load_reflections",
            "reveal_error_return_reflection",
            "reveal_progress_anky_working",
            "reveal_chat_staying_with_anky",
            "reveal_chat_reading_slowly",
            "reveal_chat_open_mirror",
            "reveal_chat_write_again",
            "reveal_chat_has_reflection",
            "reveal_chat_read_reflection",
            "reveal_chat_reflect_this_anky",
            "reveal_chat_open_credits",
            "reveal_sheet_mirror",
            "reveal_sheet_tags",
            "reveal_progress_complete",
            "reveal_progress_receiving",
            "reveal_progress_chars",
            "reveal_invitation_checking_mirror",
            "reveal_invitation_access_empty",
            "reveal_invitation_mirror_may_be_open",
            "reveal_invitation_ready",
            "reveal_ready_to_mirror_artifact",
            "reveal_short_keep_going",
            "reveal_short_thread_opened",
            "reveal_short_spark",
            "reveal_short_whole_ritual",
            "reveal_short_cross_mark",
        ).forEach { key ->
            assertTrue(androidStrings.contains("""name="$key""""))
        }
        listOf("values-es", "values-fr", "values-de", "values-hi", "values-zh-rCN").forEach { localeDir ->
            val localizedStrings = repoRoot()
                .resolve("apps/android/app/src/main/res/$localeDir/strings.xml")
                .readText()
            listOf(
                "reveal_chat_open_mirror",
                "reveal_chat_write_again",
                "reveal_chat_read_reflection",
                "reveal_chat_reflect_this_anky",
                "reveal_chat_open_credits",
                "reveal_invitation_ready",
                "reveal_short_cross_mark",
            ).forEach { key ->
                assertTrue(localizedStrings.contains("""name="$key""""))
            }
        }
    }

    @Test
    fun revealSubscriptionVeilReplacesCreditPurchaseSheet() {
        // Subscription era: where the credits sheet used to open, the
        // reflection veil now stands — VeiledFeature over ReflectionGhost,
        // one tap from the paywall, and ZERO mirror calls while free.
        val androidReveal = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/feature/reveal/RevealScreen.kt")
            .readText()
        val androidRevealModel = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/feature/reveal/RevealViewModel.kt")
            .readText()
        val androidRevealStrings = repoRoot()
            .resolve("apps/android/app/src/main/res/values/strings_reveal.xml")
            .readText()
        val iosReveal = repoRoot()
            .resolve("apps/ios/Anky/Features/Reveal/RevealView.swift")
            .readText()

        // iOS truth: the credits sheet is gone from the reveal surface.
        assertTrue(!repoRoot().resolve("apps/ios/Anky/Features/Credits/AnkyReflectionCreditsSheet.swift").exists())
        assertTrue(!iosReveal.contains(".ankyReflectionCreditsSheet("))
        assertTrue(iosReveal.contains("VeiledFeature("))
        assertTrue(iosReveal.contains("AnkyCopyRegistry.veilReflection"))
        assertTrue(iosReveal.contains("ReflectionGhost()"))
        assertTrue(iosReveal.contains("SEE WHAT ANKY SAW"))
        assertTrue(iosReveal.contains("!entitlements.isEntitledForGating"))

        // Android: the veil card stands in the reflection slot and the CTA
        // routes to the paywall with the reflection_veil origin.
        assertTrue(androidReveal.contains("VeiledFeature("))
        assertTrue(androidReveal.contains("surface = \"reflection\""))
        assertTrue(androidReveal.contains("AnkyCopyRegistry.veilReflection"))
        assertTrue(androidReveal.contains("ReflectionGhost()"))
        assertTrue(androidReveal.contains("onOpenPaywall(\"reflection_veil\")"))
        assertTrue(androidReveal.contains("onOpenPaywall: (String) -> Unit = {}"))
        assertTrue(androidReveal.contains("R.string.reveal_see_what_anky_saw"))
        assertTrue(androidReveal.contains("state.reflectionVeiled -> labels.seeWhatAnkySaw"))
        assertTrue(androidRevealStrings.contains("SEE WHAT ANKY SAW"))

        // The gate lives in the view model and fails closed — the veil is
        // state, not styling.
        assertTrue(androidRevealModel.contains("val reflectionVeiled: Boolean"))
        assertTrue(androidRevealModel.contains("EntitlementGates.freeSessionSkipsLlmReflection(entitled)"))
        assertTrue(androidRevealModel.contains("entitledForGatingProvider: () -> Boolean = { false }"))
        assertTrue(androidRevealModel.contains("isEntitlementDenied"))

        // The credits surface is dead: no sheet, no packs, no balance.
        listOf(
            "RevealCreditPurchaseSheet",
            "CreditsPalette",
            "purchaseCredits",
            "refreshCredits",
            "creditBalance",
            "creditPackages",
            "needsCreditsToReflect",
            "R.string.get_more_credits",
            "R.drawable.credits_thread_background",
            "showCreditPurchaseSheet",
        ).forEach { deadToken ->
            assertTrue("credits-era token still present: $deadToken", !androidReveal.contains(deadToken))
        }
        listOf(
            "creditPromptState",
            "creditBalance",
            "CreditPackage",
            "purchaseCredits",
            "creditsDenied",
            "This device already used its first two reflections",
            "x402_settled",
        ).forEach { deadToken ->
            assertTrue("credits-era token still present: $deadToken", !androidRevealModel.contains(deadToken))
        }
    }

    @Test
    fun subscriptionEntitlementReplacesCreditBalanceInShellAndReveal() {
        val iosEntitlement = repoRoot()
            .resolve("apps/ios/Anky/Purchases/EntitlementStore.swift")
            .readText()
        val androidReveal = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/feature/reveal/RevealViewModel.kt")
            .readText()
        val androidYou = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/feature/you/YouViewModel.kt")
            .readText()
        val androidYouScreen = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/feature/you/YouScreen.kt")
            .readText()
        val androidApp = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/app/AppContainer.kt")
            .readText()
        val androidRoot = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/app/AnkyApp.kt")
            .readText()

        assertTrue(iosEntitlement.contains("isEntitledForGating"))
        assertTrue(iosEntitlement.contains("lastKnownEntitledForGating"))

        assertTrue(androidApp.contains("val entitlementStore = EntitlementStore("))
        assertTrue(androidApp.contains("RevenueCatSubscriptionGateway(appContext)"))
        assertTrue(androidRoot.contains("container.entitlementStore.start()"))
        assertTrue(androidRoot.contains("container.entitlementStore.reconcileOnForeground()"))
        assertTrue(androidRoot.contains("entitlementStore = container.entitlementStore"))
        assertTrue(androidRoot.contains("entitledForGatingProvider = { container.entitlementStore.isEntitledForGating }"))
        assertTrue(androidReveal.contains("entitledForGatingProvider: () -> Boolean = { false }"))
        assertTrue(androidReveal.contains("EntitlementGates.freeSessionSkipsLlmReflection(entitled)"))
        assertTrue(androidYou.contains("private val entitlementStore: EntitlementStore? = null"))
        assertTrue(androidYou.contains("subscription = entitlement"))
        assertTrue(androidYouScreen.contains("subscriptionStatusTitle(state.subscription)"))
        assertTrue(!androidRoot.contains("AnkyRoute.YouCredits"))
        assertTrue(!androidRoot.contains("onOpenCredits ="))
        assertTrue(!androidReveal.contains("reflectionCreditCache.storeBalance"))
        assertTrue(!androidReveal.contains("cachedCreditBalance()"))
    }

    @Test
    fun companionTapOnlyTogglesPresenceLikeIos() {
        val androidApp = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/app/AnkyApp.kt")
            .readText()
        val androidPresence = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/ui/components/AnkyPresenceOverlay.kt")
            .readText()
        val iosApp = repoRoot()
            .resolve("apps/ios/Anky/AppRoot.swift")
            .readText()
        val iosPresence = repoRoot()
            .resolve("apps/ios/Anky/Support/AnkyPresenceOverlay.swift")
            .readText()

        assertTrue(iosApp.contains("transformToSigil: selectedTab == 0 && writeViewModel.hasStarted && !writeViewModel.hasReachedRitualMark"))
        assertTrue(iosPresence.contains("if transformToSigil {"))
        assertTrue(iosPresence.contains("revealsThreadingCompanion.toggle()"))
        assertTrue(iosPresence.contains("isVisible.toggle()"))
        assertTrue(androidApp.contains("transformToSigil = currentRoute == AnkyRoute.Write.route && writeState.acceptedGlyphCount > 0 && !writeState.hasReachedRitualMark"))
        assertTrue(!androidApp.contains("fun showCompanionNote"))
        assertTrue(!androidApp.contains("companionMessages("))
        assertTrue(!androidApp.contains("writeViewModelWithCurrentMirror.replayRecentPromptIfAvailable()"))
        assertTrue(!androidApp.contains("writeViewModelWithCurrentMirror.startAnkyNudgeIfPossible()"))
        assertTrue(!androidApp.contains("you are here."))
        assertTrue(!androidPresence.contains("onTap: (() -> Boolean)?"))
        assertTrue(!androidPresence.contains("onTap?.invoke()"))
        assertTrue(androidPresence.contains("forceCompanion = false"))
        assertTrue(androidPresence.contains("if (transformToSigil) visible = true"))
        assertTrue(androidPresence.contains("if (transformToSigil && visible && !forceCompanion)"))
        assertTrue(androidPresence.contains("forceCompanion = true"))
        assertTrue(androidPresence.contains("visible = !visible"))
        assertTrue(iosPresence.contains("DragGesture(minimumDistance: 3)"))
        assertTrue(androidPresence.contains("detectDragGestures("))
        assertTrue(androidPresence.contains("onDragStart = {"))
        assertTrue(androidPresence.contains("followsHomePosition = false"))
        assertTrue(androidPresence.contains("""testTag("anky-presence")"""))
        assertTrue(iosPresence.contains(".onTapGesture"))
        assertTrue(!iosPresence.contains("contextMenu"))
        assertTrue(!iosPresence.contains("Menu("))
        assertTrue(!androidPresence.contains("DropdownMenu"))
        assertTrue(!androidPresence.contains("onLongClick"))
        assertTrue(!androidPresence.contains("HapticFeedbackType.LongPress"))
        listOf("Keep Anky here", "Hide Anky", "Show Anky", "Change motion", "Text(\"Cancel\")", "anky stays beside the writing").forEach { menuCopy ->
            assertTrue(!androidPresence.contains(menuCopy))
        }
        assertTrue(!androidPresence.contains("drag anky anywhere"))
        assertTrue(!androidPresence.contains("Move Anky home"))
    }

    @Test
    fun appLockRecoveryPhraseFallbackMatchesCurrentIos() {
        val androidApp = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/app/AnkyApp.kt")
            .readText()
        val androidHiddenInput = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/feature/write/HiddenTextInput.kt")
            .readText()
        val androidStrings = repoRoot()
            .resolve("apps/android/app/src/main/res/values/strings.xml")
            .readText()
        val iosApp = repoRoot()
            .resolve("apps/ios/Anky/AppRoot.swift")
            .readText()
        val iosStrings = repoRoot()
            .resolve("apps/ios/Anky/en.lproj/Localizable.strings")
            .readText()

        assertTrue(iosApp.contains("private struct LockFailureView"))
        assertTrue(iosApp.contains("Image(\"tellmewhoyouare\")"))
        assertTrue(iosApp.contains(".onTapGesture"))
        assertTrue(iosApp.contains("BiometricAuthClient().confirm(reason: AnkyLocalization.text(.unlockFaceIDReason))"))
        assertTrue(iosStrings.contains("\"unlockFaceIDReason\" = \"Unlock ANKY.\";"))
        assertTrue(!iosApp.contains("allowsRecoveryPhrase"))

        assertTrue(androidApp.contains("painterResource(R.drawable.tellmewhoyouare)"))
        assertTrue(androidApp.contains("contentScale = ContentScale.Fit"))
        assertTrue(androidApp.contains("unlockAttempt.intValue += 1"))
        assertTrue(androidStrings.contains("""name="unlock_device_lock_reason">Unlock ANKY.</string>"""))
        assertTrue(androidApp.contains("val unlockDeviceLockReason = stringResource(R.string.unlock_device_lock_reason)"))
        assertTrue(androidApp.contains("biometricGate.authenticate(unlockDeviceLockReason)"))
        assertTrue(!androidApp.contains("""biometricGate.authenticate("Unlock ANKY.")"""))
        assertTrue(androidApp.contains("remember(identityVersion)"))
        assertTrue(!androidApp.contains("fun recoverIdentityFromPhrase()"))
        assertTrue(!androidApp.contains("""Text("recovery phrase""""))
        assertTrue(!androidApp.contains("""Text("face id didn't work. you should not be here""""))
    }

    @Test
    fun appLockActivationPromptAfterFirstCompleteMatchesCurrentIos() {
        val androidApp = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/app/AnkyApp.kt")
            .readText()
        val androidSettings = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/app/UserSettingsStore.kt")
            .readText()
        val androidStrings = repoRoot()
            .resolve("apps/android/app/src/main/res/values/strings.xml")
            .readText()
        val iosApp = repoRoot()
            .resolve("apps/ios/Anky/AppRoot.swift")
            .readText()
        val iosLocalization = repoRoot()
            .resolve("apps/ios/Anky/Support/AnkyLocalization.swift")
            .readText()

        assertTrue(iosApp.contains("@AppStorage(\"anky.biometricPrivacyOnboardingCompleted\")"))
        assertTrue(iosApp.contains("presentFaceIDActivationPromptIfNeeded()"))
        assertTrue(iosApp.contains("SessionIndexStore().load().contains(where: { ${'$'}0.isComplete })"))
        assertTrue(iosApp.contains("enableFaceIDLockFromOnboarding()"))
        assertTrue(iosLocalization.contains("Protect your Anky with your device lock. Your writing is local, and this keeps access private on this phone."))
        assertTrue(iosLocalization.contains("Activate Device Lock"))
        assertTrue(iosLocalization.contains("Protect ANKY with your device lock."))

        assertTrue(androidSettings.contains("val deviceLockPromptCompleted: Boolean = false"))
        assertTrue(androidSettings.contains("setDeviceLockPromptCompleted(completed: Boolean)"))
        assertTrue(androidSettings.contains("booleanPreferencesKey(\"device_lock_prompt_completed\")"))
        assertTrue(androidApp.contains("val showsDeviceLockActivationPrompt = remember { mutableStateOf(false) }"))
        assertTrue(androidApp.contains("val skipNextAppLockAuthentication = remember { mutableStateOf(false) }"))
        assertTrue(androidApp.contains("settings.deviceLockPromptCompleted"))
        assertTrue(androidApp.contains("container.sessionIndexStore.load().any { it.isComplete }"))
        assertTrue(androidApp.contains("canUseDeviceLock(context)"))
        assertTrue(androidApp.contains("AlertDialog("))
        assertTrue(androidStrings.contains("Protect your Anky with your device lock. Your writing is local, and this keeps access private on this phone."))
        assertTrue(androidStrings.contains("Activate Device Lock"))
        assertTrue(androidStrings.contains("Not now"))
        assertTrue(androidStrings.contains("Protect ANKY with your device lock."))
        assertTrue(androidStrings.contains("Unlock ANKY."))
        assertTrue(androidApp.contains("stringResource(R.string.device_lock_prompt)"))
        assertTrue(androidApp.contains("stringResource(R.string.activate_device_lock)"))
        assertTrue(androidApp.contains("stringResource(R.string.not_now)"))
        assertTrue(androidApp.contains("val protectDeviceLockReason = stringResource(R.string.protect_device_lock_reason)"))
        assertTrue(androidApp.contains("biometricGate.authenticate(deviceLockReason)"))
        assertTrue(!androidApp.contains("""biometricGate.authenticate("Protect ANKY with your device lock.")"""))
        assertTrue(androidApp.contains("container.settingsStore.setAppLockEnabled(true)"))
        assertTrue(androidApp.contains("container.settingsStore.setDeviceLockPromptCompleted(true)"))
    }

    @Test
    fun youHomeDeviceLockToggleMatchesCurrentIosReachability() {
        val iosYou = repoRoot()
            .resolve("apps/ios/Anky/Features/You/YouView.swift")
            .readText()
        val androidYou = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/feature/you/YouScreen.kt")
            .readText()
        val androidStrings = repoRoot()
            .resolve("apps/android/app/src/main/res/values/strings.xml")
            .readText()
        val androidApp = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/app/AnkyApp.kt")
            .readText()

        assertTrue(iosYou.contains("if shouldShowFaceIDControl"))
        assertTrue(iosYou.contains("BiometricAuthClient().canAuthenticate()"))
        assertTrue(iosYou.contains("YouToggleRow("))
        assertTrue(iosYou.contains("title: deviceAuthenticationName"))
        assertTrue(iosYou.contains("subtitle: biometricIdentityConfirmation ? \"On\" : \"Off\""))
        assertTrue(iosYou.contains("setFaceID(isEnabled)"))
        assertTrue(iosYou.contains("BiometricAuthClient().confirm(reason: AnkyLocalization.text(.protectFaceIDReason))"))
        assertTrue(iosYou.contains("skipsNextFaceIDEnableAuthentication = true"))
        assertTrue(iosYou.contains("faceIDPrivacyOnboardingCompleted = true"))

        assertTrue(androidYou.contains("val shouldShowDeviceLockControl = remember(context) { canUseDeviceLock(context) }"))
        assertTrue(androidYou.contains("DeviceLockRow("))
        assertTrue(androidYou.contains("title = lockTitle"))
        assertTrue(androidYou.contains("checked = state.appLockEnabled"))
        assertTrue(androidYou.contains("checkedText = stringResource(R.string.on)"))
        assertTrue(androidYou.contains("uncheckedText = stringResource(R.string.off)"))
        assertTrue(androidYou.contains("onChecked = onAppLockChange"))
        assertTrue(androidYou.contains("if (checked) checkedText else uncheckedText"))
        assertTrue(androidYou.contains("private fun canUseDeviceLock(context: Context): Boolean"))
        assertTrue(androidYou.contains("BiometricManager.Authenticators.BIOMETRIC_WEAK or"))
        assertTrue(androidYou.contains("BiometricManager.Authenticators.DEVICE_CREDENTIAL"))
        assertTrue(androidYou.contains("@Composable\nprivate fun deviceLockControlTitle(context: Context): String"))
        assertTrue(androidYou.contains("private fun deviceLockControlTitle(context: Context): String"))
        assertTrue(androidYou.contains("\"fingerprint\" -> stringResource(R.string.fingerprint)"))
        assertTrue(androidYou.contains("\"face\" -> stringResource(R.string.face_unlock)"))
        assertTrue(androidYou.contains("\"iris\" -> stringResource(R.string.iris)"))
        assertTrue(androidYou.contains("\"biometric\" -> stringResource(R.string.biometric_lock)"))
        assertTrue(androidYou.contains("else -> stringResource(R.string.device_lock)"))
        assertTrue(androidStrings.contains("""name="fingerprint">Fingerprint</string>"""))
        assertTrue(androidStrings.contains("""name="face_unlock">Face unlock</string>"""))
        assertTrue(androidStrings.contains("""name="iris">Iris</string>"""))
        assertTrue(androidStrings.contains("""name="biometric_lock">Biometric lock</string>"""))
        assertTrue(androidStrings.contains("""name="device_lock">Device lock</string>"""))
        assertTrue(androidApp.contains("onAppLockChange = { enabled ->"))
        assertTrue(androidApp.contains("val protectDeviceLockReason = stringResource(R.string.protect_device_lock_reason)"))
        assertTrue(androidApp.contains("biometricGate.authenticate(protectDeviceLockReason)"))
        assertTrue(androidApp.contains("container.settingsStore.setDeviceLockPromptCompleted(true)"))
        assertTrue(androidApp.contains("skipNextAppLockAuthentication.value = true"))
        assertTrue(androidApp.contains("container.settingsStore.setAppLockEnabled(false)"))
    }

    @Test
    fun youPrivacyAndSupportPromptActionsMatchCurrentIos() {
        val androidYou = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/feature/you/YouScreen.kt")
            .readText()
        val androidModel = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/feature/you/YouViewModel.kt")
            .readText()
        val androidStrings = repoRoot()
            .resolve("apps/android/app/src/main/res/values/strings.xml")
            .readText()
        val androidArticles = repoRoot()
            .resolve("apps/android/app/src/main/res/values/article_strings.xml")
            .readText()
        val iosYou = repoRoot()
            .resolve("apps/ios/Anky/Features/You/YouView.swift")
            .readText()
        val iosModel = repoRoot()
            .resolve("apps/ios/Anky/Features/You/YouViewModel.swift")
            .readText()

        assertTrue(iosYou.contains("case .privacy:\n            return []"))
        assertTrue(iosYou.contains("""AnkyChatAction(AnkyLocalization.ui("Open email"), isPrimary: true)"""))
        assertTrue(iosYou.contains("Send us an email! We want to evolve this app based on your feedback."))
        assertTrue(iosModel.contains("supportFeedbackEmailURL"))

        assertTrue(androidYou.contains("YouPrompt.Privacy -> emptyList()"))
        assertTrue(androidYou.contains("openEmail = stringResource(R.string.open_email)"))
        assertTrue(androidYou.contains("AnkyChatAction(labels.openEmail, isPrimary = true)"))
        assertTrue(androidYou.contains("YouPrompt.Support -> stringResource(R.string.you_prompt_support)"))
        assertTrue(androidStrings.contains("""name="you_prompt_support">Send us an email! We want to evolve this app based on your feedback.</string>"""))
        assertTrue(androidYou.contains("stringResource(R.string.you_support_feedback)"))
        assertTrue(androidStrings.contains("Support / Feedback"))
        assertTrue(androidModel.contains("supportFeedbackEmailUrl"))
        assertTrue(!androidYou.contains("support messages include your account id, not your writing."))
        assertTrue(!androidYou.contains("copy privacy email"))
        assertTrue(!androidYou.contains("manual credit help"))
    }

    @Test
    fun androidPrivacyPolicyUsesCurrentSupportContactAndAndroidPlatformTerms() {
        val androidYou = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/feature/you/YouScreen.kt")
            .readText()
        val androidArticles = repoRoot()
            .resolve("apps/android/app/src/main/res/values/article_strings.xml")
            .readText()

        listOf(
            "Anky, Inc. - Effective July 6, 2026",
            "Contact: **[support@anky.app](mailto:support@anky.app)**",
            "Purchases are processed by Google Play and managed through RevenueCat.",
            "For free trials, fraud prevention, abuse prevention, and request safety, the app may ask Android platform integrity or device attestation services for a token when supported.",
            "**Google** - Google Play purchases, refunds, device services, Android backup services when enabled, notifications, device attestation, and platform services.",
            "Payments are handled by Google Play and managed with RevenueCat.",
        ).forEach { expected ->
            assertTrue(androidArticles.contains(expected))
        }

        listOf(
            "jp@anky.app",
            "last updated: 2026-05-14",
            "apps/ios/Anky/Core/Storage/LocalAnkyArchive.swift",
            "apps/ios/Anky/Core/Protocol",
            "apps/ios/Anky/Core/Identity/WriterIdentityStore.swift",
            "apps/ios/Anky/Core/Identity/KeychainClient.swift",
            "apps/ios/Anky/Core/Mirror/MirrorClient.swift",
            "apps/ios/Anky/Core/Storage/BackupImporter.swift",
            "apps/ios/Anky/Features/You/YouViewModel.swift",
        ).forEach { iosPath ->
            assertTrue(!androidYou.contains(iosPath))
        }
    }

    @Test
    fun youLocalIdentityCopyUsesCurrentIosBaseAccountAndRecoveryPhraseLanguage() {
        val androidYou = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/feature/you/YouScreen.kt")
            .readText()
        val androidModel = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/feature/you/YouViewModel.kt")
            .readText()
        val androidReminderReceiver = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/core/notifications/DailyReminderReceiver.kt")
            .readText()
        val androidStrings = repoRoot()
            .resolve("apps/android/app/src/main/res/values/strings.xml")
            .readText()
        val androidArticles = repoRoot()
            .resolve("apps/android/app/src/main/res/values/article_strings.xml")
            .readText()
        val iosYou = repoRoot()
            .resolve("apps/ios/Anky/Features/You/YouView.swift")
            .readText()
        val iosModel = repoRoot()
            .resolve("apps/ios/Anky/Features/You/YouViewModel.swift")
            .readText()
        val iosNotificationScheduler = repoRoot()
            .resolve("apps/ios/Anky/Core/Notifications/LocalNotificationScheduler.swift")
            .readText()

        listOf(
            "Anky created a private local profile for this device.",
            "These words restore your Anky access. Never share them. Anky cannot recover them for you.",
            "Your passcode or biometrics protect local access. They are not an Anky login.",
            "This stores your recovery words in your device/cloud keychain. Data export is the separate backup for writing and reflections. Anky cannot read or recover either for you.",
        ).forEach { copy ->
            assertTrue(iosYou.contains(copy))
        }
        listOf(
            "you_private_access",
            "you_private_profile",
            "you_writing_access_stays",
            "you_advanced_recovery",
            "you_recovery_words_restore",
            "you_recovery_words_gate",
            "you_passcode_biometrics_note",
            "you_reveal_recovery_words",
            "you_copy_recovery_words",
            "you_backup_recovery_words_secure_storage",
            "you_secure_storage_note",
            "you_ownership_note",
            "you_ownership_body",
            "you_export_data",
            "you_archive_yours",
            "you_readable_exports_note",
            "you_no_writing_to_export",
            "you_encrypted_backup",
            "back_up_now",
            "export_writings",
            "device_lock_app_protection",
            "anky_address",
            "copy_account",
            "daily_reminder",
            "time",
            "change_time",
            "hour",
            "minute",
            "set",
            "danger_zone",
            "you_delete_account_data_question",
            "you_delete_account_data_body",
            "you_delete_account_data_detail_body",
            "you_delete_account_data_caps",
            "you_delete_local_writing_data_question",
            "you_delete_local_data_body",
            "you_delete_local_writing_data_action",
            "you_local_files_reflections_format",
            "export_backup_zip",
            "share_backup_zip",
            "no_local_data_to_back_up_yet",
            "restore_backup",
            "delete_local_data",
        ).forEach { key ->
            assertTrue(androidStrings.contains("""name="$key""""))
            assertTrue(androidYou.contains("R.string.$key"))
        }
        assertTrue(iosNotificationScheduler.contains("content.title = \"ANKY\""))
        assertTrue(iosNotificationScheduler.contains("content.body = \"write your anky today\""))
        assertTrue(androidStrings.contains("""name="daily_reminder_notification_title" translatable="false">ANKY</string>"""))
        assertTrue(androidStrings.contains("""name="daily_reminder_notification_body">write your anky today</string>"""))
        assertTrue(androidReminderReceiver.contains("setContentTitle(context.getString(R.string.daily_reminder_notification_title))"))
        assertTrue(androidReminderReceiver.contains("setContentText(context.getString(R.string.daily_reminder_notification_body))"))
        assertTrue(!androidReminderReceiver.contains("""setContentTitle("ANKY")"""))
        assertTrue(!androidReminderReceiver.contains("""setContentText("write your anky today")"""))
        listOf("values-es", "values-fr", "values-de", "values-hi", "values-zh-rCN").forEach { localeDir ->
            val localizedStrings = repoRoot()
                .resolve("apps/android/app/src/main/res/$localeDir/strings.xml")
                .readText()
            assertTrue(localizedStrings.contains("you_private_access"))
            assertTrue(localizedStrings.contains("you_recovery_words_restore"))
            assertTrue(localizedStrings.contains("you_readable_exports_note"))
            assertTrue(localizedStrings.contains("you_delete_account_data_question"))
            assertTrue(localizedStrings.contains("export_backup_zip"))
            assertTrue(localizedStrings.contains("show_anky_recovery_words_reason"))
            assertTrue(localizedStrings.contains("backup_anky_recovery_words_secure_storage_reason"))
            assertTrue(localizedStrings.contains("recover_anky_access_reason"))
            assertTrue(localizedStrings.contains("enable_encrypted_anky_backup_reason"))
            assertTrue(localizedStrings.contains("restore_encrypted_anky_backup_reason"))
            assertTrue(localizedStrings.contains("could_not_confirm_identity"))
            assertTrue(localizedStrings.contains("daily_reminder_notification_body"))
        }
        assertTrue(iosYou.contains("""YouActionButton(AnkyLocalization.ui("Back up recovery words to iCloud Keychain"))"""))
        assertTrue(androidYou.contains("backUpRecoveryWords = stringResource(R.string.you_backup_recovery_words)"))
        assertTrue(androidYou.contains("AnkyChatAction(labels.backUpRecoveryWords, isPrimary = true)"))
        listOf(
            "you_recover_access_lower",
            "you_recovery_words_label",
            "you_recovery_replaces_access",
            "recover",
            "cancel",
            "open_email",
            "you_backup_recovery_words",
            "show_anky_recovery_words_reason",
            "backup_anky_recovery_words_secure_storage_reason",
            "recover_anky_access_reason",
            "enable_encrypted_anky_backup_reason",
            "restore_encrypted_anky_backup_reason",
            "could_not_confirm_identity",
        ).forEach { key ->
            assertTrue(androidStrings.contains("""name="$key""""))
            assertTrue(androidYou.contains("R.string.$key") || key == "you_backup_recovery_words")
        }
        assertTrue(iosYou.contains("viewModel.backUpIdentityToICloudKeychain()"))
        assertTrue(androidYou.contains("viewModel.backUpIdentityToDeviceSecureStorage("))
        assertTrue(iosModel.contains("func backUpIdentityToICloudKeychain() async"))
        assertTrue(androidModel.contains("fun backUpIdentityToDeviceSecureStorage("))
        assertTrue(androidModel.contains("identityStore.backUpRecoveryPhraseToDeviceSecureStorage()"))
        assertTrue(!androidYou.contains("""AnkyChatAction("back up identity", isPrimary = true) { viewModel.revealRecoveryPhrase() }"""))
        listOf(
            "SwitchRow(\"device lock app protection",
            "Text(\"Anky address",
            "AnkyActionButton(\"copy account",
            "SwitchRow(\"daily reminder",
            "DetailRow(\"time",
            "AnkyActionButton(\"change time",
            "Text(\"danger zone",
            "Text(\"Delete Account and Data?",
            "Text(\"This deletes your Anky data from this device. This cannot be undone.",
            "AnkyActionButton(\"export backup zip",
            "AnkyActionButton(\"share backup zip",
            "DisabledRow(\"no local data to back up yet",
            "AnkyActionButton(\"restore backup",
            "AnkyActionButton(\"delete local data",
        ).forEach { literal ->
            assertTrue(!androidYou.contains(literal))
        }
        assertTrue(iosModel.contains("Show your Anky recovery words."))
        assertTrue(androidStrings.contains("""name="show_anky_recovery_words_reason">Show your Anky recovery words.</string>"""))
        assertTrue(androidStrings.contains("""name="recover_anky_access_reason">Recover your Anky access.</string>"""))
        assertTrue(androidYou.contains("showRecoveryWordsReason = stringResource(R.string.show_anky_recovery_words_reason)"))
        assertTrue(androidYou.contains("backupRecoveryWordsSecureStorageReason = stringResource(R.string.backup_anky_recovery_words_secure_storage_reason)"))
        assertTrue(androidYou.contains("recoverAnkyAccessReason = stringResource(R.string.recover_anky_access_reason)"))
        assertTrue(androidYou.contains("enableEncryptedBackupReason = stringResource(R.string.enable_encrypted_anky_backup_reason)"))
        assertTrue(androidYou.contains("restoreEncryptedBackupReason = stringResource(R.string.restore_encrypted_anky_backup_reason)"))
        assertTrue(androidYou.contains("couldNotConfirmIdentity = stringResource(R.string.could_not_confirm_identity)"))
        assertTrue(androidModel.contains("authReason: String = YouStatusCopy.ShowRecoveryWordsReason"))
        assertTrue(androidModel.contains("authReason: String = YouStatusCopy.RecoverAnkyAccessReason"))
        assertTrue(androidModel.contains("authFailure: String = YouStatusCopy.CouldNotConfirmIdentity"))
        assertTrue(androidModel.contains("biometricGate.authenticate(authReason)"))
        assertTrue(!androidModel.contains("""biometricGate.authenticate("Show your Anky recovery words.")"""))
        assertTrue(!androidModel.contains("""biometricGate.authenticate("Recover your ANKY local identity.")"""))
        assertTrue(!androidModel.contains("""it.copy(error = "Could not confirm identity.")"""))
        assertTrue(iosModel.contains("Could not load the recovery words."))
        assertTrue(androidModel.contains("Could not load the recovery words."))
        assertTrue(iosModel.contains("identityStatus = AnkyLocalization.ui(\"Private access\")"))
        assertTrue(androidModel.contains("Could not load the local Base identity."))
        assertTrue(iosModel.contains("Recovery words must be 12 words."))
        assertTrue(androidModel.contains("Recovery words must be 12 words."))
        assertTrue(iosModel.contains("Recovery words contain an unrecognized word."))
        assertTrue(androidModel.contains("Recovery words contain an unrecognized word."))
        assertTrue(androidArticles.contains("name=\"terms_article_body\""))
        assertTrue(androidArticles.contains("Anky may create private local access for your device."))
        assertTrue(androidArticles.contains("You are responsible for protecting your recovery words, device passcode, biometric access, account backups, and exported files."))
        assertTrue(!androidYou.contains("private identity"))
        assertTrue(!androidYou.contains("recovery phrase"))
        assertTrue(!androidYou.contains("recovery key"))
        assertTrue(!androidModel.contains("Recovery key"))
        assertTrue(!androidModel.contains("Could not load the local identity."))
        assertTrue(!androidModel.contains("recovery key"))
    }

    @Test
    fun youResetIdentityWarningMatchesCurrentIosCreditAccountCopy() {
        val androidYou = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/feature/you/YouScreen.kt")
            .readText()
        val androidStrings = repoRoot()
            .resolve("apps/android/app/src/main/res/values/strings.xml")
            .readText()
        val iosYou = repoRoot()
            .resolve("apps/ios/Anky/Features/You/YouView.swift")
            .readText()
        val resetWarning = "Resetting identity creates a new Anky Base account. Credits are tied to your current account. Save your recovery words before resetting."

        assertTrue(!iosYou.contains(".confirmationDialog(\"reset local identity?\""))
        assertTrue(!iosYou.contains("Button(\"reset identity\", role: .destructive)"))

        assertTrue(androidStrings.contains("""name="reset_local_identity_question">reset local identity?</string>"""))
        assertTrue(androidStrings.contains("""name="reset_identity_action">reset identity</string>"""))
        assertTrue(androidStrings.contains("""name="reset_identity_warning">$resetWarning</string>"""))
        assertTrue(androidYou.contains("title = stringResource(R.string.reset_local_identity_question)"))
        assertTrue(androidYou.contains("action = stringResource(R.string.reset_identity_action)"))
        assertTrue(androidYou.contains("message = stringResource(R.string.reset_identity_warning)"))
        assertTrue(androidYou.contains("text = message?.let"))
        assertTrue(androidYou.contains("YouPage.Developer -> if (BuildConfig.DEBUG)"))
        assertTrue(androidYou.contains("AnkyActionButton(stringResource(R.string.reset_identity_action), destructive = true"))
    }

    @Test
    fun youConversationPromptStartsHiddenLikeCurrentIos() {
        val androidYou = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/feature/you/YouScreen.kt")
            .readText()
        val androidStrings = repoRoot()
            .resolve("apps/android/app/src/main/res/values/strings.xml")
            .readText()
        val iosYou = repoRoot()
            .resolve("apps/ios/Anky/Features/You/YouView.swift")
            .readText()

        assertTrue(iosYou.contains("@State private var activePrompt: YouPrompt?"))
        assertTrue(iosYou.contains("guard isShowingSystemPrompt || activePrompt != nil else"))

        assertTrue(androidYou.contains("val activePrompt = remember { mutableStateOf<YouPrompt?>(null) }"))
        assertTrue(androidYou.contains("val isPromptVisible = remember { mutableStateOf(false) }"))
        assertTrue(androidYou.contains("private fun YouHome("))
        assertTrue(androidYou.contains("activePrompt: YouPrompt?"))
        assertTrue(androidYou.contains("activePrompt?.let { localizedYouPromptMessage(it) }.orEmpty()"))
        assertTrue(!androidYou.contains("val activePrompt = remember { mutableStateOf(YouPrompt.Identity) }"))
        assertTrue(!androidYou.contains("val isPromptVisible = remember { mutableStateOf(true) }"))
    }

    @Test
    fun youExperienceCodeIsRetainedButNotVisibleOnCurrentHome() {
        val androidApp = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/app/AnkyApp.kt")
            .readText()
        val androidYou = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/feature/you/YouScreen.kt")
            .readText()
        val androidStrings = repoRoot()
            .resolve("apps/android/app/src/main/res/values/strings.xml")
            .readText()
        val iosYou = repoRoot()
            .resolve("apps/ios/Anky/Features/You/YouView.swift")
            .readText()

        assertTrue(iosYou.contains("private struct AnkyExperienceView: View"))
        assertTrue(!iosYou.contains("AnkyExperienceView("))
        assertTrue(iosYou.contains("private struct YouStatsPanel: View"))
        assertTrue(!iosYou.contains("YouStatsPanel("))

        assertTrue(androidYou.contains("val isShowingAnkyExperience = remember { mutableStateOf(false) }"))
        assertTrue(androidYou.contains("onExperienceVisibilityChanged: (Boolean) -> Unit = {}"))
        assertTrue(androidYou.contains("onExperienceVisibilityChanged(isShowingAnkyExperience.value)"))
        assertTrue(!androidYou.contains("onOpenExperience"))
        assertTrue(!androidYou.contains("YouStats(state, onClick"))
        assertTrue(!androidYou.contains("""Text(
                "you","""))
        assertTrue(androidYou.contains("AnkyExperienceOverlay("))
        assertTrue(androidYou.contains("AnkyExperienceSystemBarsHidden()"))
        assertTrue(androidYou.contains("WindowCompat.setDecorFitsSystemWindows(window, false)"))
        assertTrue(androidYou.contains("controller.hide(WindowInsetsCompat.Type.systemBars())"))
        assertTrue(androidYou.contains("private const val AnkyExperienceTotalSeconds = 88 * 60"))
        assertTrue(androidYou.contains("HiddenTextInput("))
        assertTrue(androidYou.contains("AnkyWriter()"))
        assertTrue(androidYou.contains("writer.value.closeWithTerminalSilence()"))
        listOf(
            "anky_experience_artifact_label",
            "anky_experience_writing_label",
            "anky_experience_open",
            "anky_experience_complete",
            "anky_experience_time_format",
            "anky_experience_ring_accessibility",
            "close_anky_experience",
            "anky_companion",
            "copy_your_anky_or_writing",
            "copy_your_anky",
            "copy_your_writing",
        ).forEach { key ->
            assertTrue(androidStrings.contains("""name="$key""""))
            assertTrue(androidYou.contains("R.string.$key"))
        }
        listOf("values-es", "values-fr", "values-de", "values-hi", "values-zh-rCN").forEach { localeDir ->
            val localizedStrings = repoRoot()
                .resolve("apps/android/app/src/main/res/$localeDir/strings.xml")
                .readText()
            assertTrue(localizedStrings.contains("anky_experience_time_format"))
            assertTrue(localizedStrings.contains("copy_your_anky_or_writing"))
            assertTrue(localizedStrings.contains("close_anky_experience"))
        }
        assertTrue(iosYou.contains("accessibilityLabel(AnkyLocalization.ui(\"Anky experience time %@\", viewModel.elapsedClockText))"))
        assertTrue(iosYou.contains("accessibilityLabel(AnkyLocalization.ui(\"Close The Anky Experience\"))"))
        assertTrue(iosYou.contains("accessibilityLabel(AnkyLocalization.ui(\"Anky companion\"))"))
        assertTrue(iosYou.contains("message: AnkyLocalization.ui(\"copy your .anky or copy your writing.\")"))
        assertTrue(iosYou.contains("AnkyChatAction(AnkyLocalization.ui(\"copy your .anky\"), isPrimary: true)"))
        assertTrue(iosYou.contains("AnkyChatAction(AnkyLocalization.ui(\"copy your writing\"))"))
        assertTrue(!androidYou.contains("copyText(\"Anky experience .anky\""))
        assertTrue(!androidYou.contains("copyText(\"Anky experience writing\""))
        assertTrue(!androidYou.contains("val subtitle = if (isFinished) \"the experience is complete\" else \"the experience is open\""))
        assertTrue(!androidYou.contains("contentDescription = \"Anky experience time ${'$'}elapsedClock\""))
        assertTrue(!androidYou.contains("contentDescription = \"Close The Anky Experience\""))
        assertTrue(!androidYou.contains("contentDescription = \"Anky companion\""))
        assertTrue(!androidYou.contains("message = \"copy your .anky or copy your writing.\""))
        assertTrue(!androidYou.contains("AnkyChatAction(\"copy your .anky\", isPrimary = true)"))
        assertTrue(!androidYou.contains("AnkyChatAction(\"copy your writing\")"))

        assertTrue(androidApp.contains("val isShowingYouExperience = remember { mutableStateOf(false) }"))
        assertTrue(androidApp.contains("onExperienceVisibilityChanged = { isShowingYouExperience.value = it }"))
        assertTrue(androidApp.contains("!isShowingYouExperience.value"))
        assertTrue(androidApp.contains("if (!isShowingYouExperience.value && !shouldShowOnboarding)"))
    }

    @Test
    fun firstLaunchOnboardingMatchesCurrentIosPages() {
        val iosOnboarding = repoRoot()
            .resolve("apps/ios/Anky/Features/Onboarding/OnboardingView.swift")
            .readText()
        val iosApp = repoRoot()
            .resolve("apps/ios/Anky/AppRoot.swift")
            .readText()
        val androidOnboarding = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/feature/onboarding/OnboardingScreen.kt")
            .readText()
        val androidFlowState = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/feature/onboarding/OnboardingFlowState.kt")
            .readText()
        val androidOnboardingStrings = repoRoot()
            .resolve("apps/android/app/src/main/res/values/strings_onboarding.xml")
            .readText()

        // iOS truth: the 13-screen flow (1–11 in-view, 12 gate setup, 13 the
        // Day 1 threshold), aubergine-to-dawn, one painting per early screen.
        listOf(
            "onboarding-1",
            "onboarding-2",
            "onboarding-3",
            "onboarding-4",
            "onboarding-5",
            "The world is thinking for you.",
            "Anky puts a door before the noise.",
            "Write before you scroll.",
            "How many hours a day are you on your phone?",
            "of your waking life.",
            "This is Anky.",
            "What should I call you?",
            "Choose a daily writing target.",
            "Your first 8 days.",
            "When your apps knock, I'll answer.",
            "Day 1.",
            "Write whatever is in your mind.",
            "Start writing",
            "anky.dailyPhoneHours",
            "anky.onboardingLastScreen",
            "private static let dawnStartScreen = 6",
            "private static let targetScreenIndex = 8",
            "private static let paywallScreenIndex = 10",
            "private static let screenCount = 11",
            "hours * 40 / 16",
            ".onboardingTargetSet",
            "struct DayOneThresholdOverlay: View",
        ).forEach { expected ->
            assertTrue("iOS onboarding lost anchor: $expected", iosOnboarding.contains(expected))
        }
        assertTrue(iosApp.contains("@AppStorage(\"anky.onboardingCompleted\")"))
        assertTrue(iosApp.contains("OnboardingFlowProgress.mark(12)"))
        assertTrue(iosApp.contains("DayOneThresholdOverlay {"))
        assertTrue(iosApp.contains("completeOnboarding()"))
        assertTrue(iosApp.contains("onboardingCompleted = true"))
        assertTrue(iosApp.contains("OnboardingFlowProgress.markFinished()"))

        // Android port: same screens, same paintings, same slots and markers.
        listOf(
            "fun AnkyOnboardingFlow(",
            "paywall: @Composable (onDone: () -> Unit) -> Unit",
            "gateSetup: @Composable (onDone: () -> Unit) -> Unit",
            "onGateSetupRequested: () -> Unit",
            "onCompleted: () -> Unit",
            "fun AnkyDayOneThresholdOverlay(",
            "HorizontalPager(",
            "userScrollEnabled = false",
            "R.drawable.onboarding_1",
            "R.drawable.onboarding_2",
            "R.drawable.onboarding_3",
            "R.drawable.onboarding_4",
            "R.drawable.onboarding_5",
            "R.string.onboarding_problem_title",
            "R.string.onboarding_solution_title",
            "R.string.onboarding_mechanism_title",
            "R.string.onboarding_hours_title",
            "R.string.onboarding_math_years_format",
            "R.string.onboarding_meet_title",
            "R.string.onboarding_name_title",
            "R.string.onboarding_target_title",
            "R.string.onboarding_journey_title",
            "R.string.onboarding_notifications_title",
            "R.string.onboarding_day_one_title",
            "LazureMood.Dusk",
            "LazureMood.Dawn",
            "TakePicturePreview",
            "Bitmap.CompressFormat.JPEG, 85",
            "Manifest.permission.POST_NOTIFICATIONS",
            "setInitialTarget(targetMinutes)",
            "WriteBeforeScrollEventName.OnboardingTargetSet",
            "progress.markFinished()",
            "fun AnkyOnboardingScreen(",
        ).forEach { expected ->
            assertTrue("Android onboarding lost anchor: $expected", androidOnboarding.contains(expected))
        }
        listOf(
            "const val Key = \"anky.onboardingLastScreen\"",
            "const val PreferenceKey = \"anky.dailyPhoneHours\"",
            "const val DawnStartScreen = 6",
            "const val TargetScreen = 8",
            "const val PaywallScreen = 10",
            "const val ScreenCount = 11",
            "const val GateSetupScreen = 12",
            "const val DayOneThresholdScreen = 13",
            "hoursPerDay * 40.0 / 16.0",
        ).forEach { expected ->
            assertTrue("Android flow state lost anchor: $expected", androidFlowState.contains(expected))
        }
        // The English copy is verbatim iOS.
        listOf(
            """name="onboarding_problem_title">The world is thinking for you.</string>""",
            """name="onboarding_solution_title">Anky puts a door before the noise.</string>""",
            """name="onboarding_mechanism_title">Write before you scroll.</string>""",
            """name="onboarding_mechanism_body_quick">One sentence opens your apps for 15 minutes.</string>""",
            """name="onboarding_hours_title">How many hours a day are you on your phone?</string>""",
            """name="onboarding_hours_bracket_1_2">1–2 hours</string>""",
            """name="onboarding_math_waking_life">of your waking life.</string>""",
            """name="onboarding_meet_title">This is Anky.</string>""",
            """name="onboarding_name_title">What should I call you?</string>""",
            """name="onboarding_target_title">Choose a daily writing target.</string>""",
            """name="onboarding_journey_title">Your first 8 days.</string>""",
            "The gate becomes yours. Anky was only holding it until you could feel the choice.",
            """name="onboarding_notifications_cta">Allow notifications</string>""",
            """name="onboarding_day_one_title">Day 1.</string>""",
            """name="onboarding_day_one_body">Write whatever is in your mind.</string>""",
            """name="onboarding_day_one_cta">Start writing</string>""",
        ).forEach { expected ->
            assertTrue("strings_onboarding.xml lost copy: $expected", androidOnboardingStrings.contains(expected))
        }
        // The legacy 3-image flow shape must not come back.
        assertTrue(!androidOnboarding.contains("R.string.onboarding_line_1"))
        assertTrue(!androidOnboarding.contains("R.string.onboarding_cta_1"))
    }

    @Test
    fun youHomeRowsMatchCurrentIosPromptAndLegalShape() {
        val androidYou = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/feature/you/YouScreen.kt")
            .readText()
        val androidYouModel = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/feature/you/YouViewModel.kt")
            .readText()
        val androidSettings = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/feature/settings/AnkySettingsScreen.kt")
            .readText()
        val iosYou = repoRoot()
            .resolve("apps/ios/Anky/Features/You/YouView.swift")
            .readText()
        val iosSettings = repoRoot()
            .resolve("apps/ios/Anky/Features/Settings/AnkySettingsView.swift")
            .readText()
        val androidStrings = repoRoot()
            .resolve("apps/android/app/src/main/res/values/strings.xml")
            .readText()
        val androidYouStrings = repoRoot()
            .resolve("apps/android/app/src/main/res/values/strings_you.xml")
            .readText()
        val androidSettingsStrings = repoRoot()
            .resolve("apps/android/app/src/main/res/values/strings_settings.xml")
            .readText()
        val androidArticleStrings = repoRoot()
            .resolve("apps/android/app/src/main/res/values/article_strings.xml")
            .readText()

        // Current iOS home: settings entry, data toggle, gate setup, daily
        // target stepper, support prompt, privacy/terms sheets, device-lock
        // toggle. Credits, token, and the WhatsApp gift flow are gone.
        assertTrue(iosYou.contains("""legalButton(icon: "you-icon-settings", title: "Customize your Anky experience", subtitle: "Daily target, name, writing, font, protection.")"""))
        assertTrue(iosYou.contains("path.append(YouRoute.settings)"))
        assertTrue(iosYou.contains("""legalButton(icon: "you-icon-settings", title: "Write Before You Scroll", subtitle: "Choose the apps Anky gates.")"""))
        assertTrue(iosYou.contains("onGateSetupRequested()"))
        assertTrue(iosYou.contains("private var dailyTargetRow: some View"))
        assertTrue(iosYou.contains("DailyTargetStore().requestTargetChange(to: minutes)"))
        assertTrue(iosYou.contains("""promptButton(.support, icon: "you-icon-support", title: "Support / Feedback", subtitle: "Email support@anky.app")"""))
        assertTrue(iosYou.contains("""promptButton(.privacy, icon: "you-icon-privacy", title: "Privacy Policy", subtitle: "How your data is handled.")"""))
        assertTrue(iosYou.contains("""legalButton(icon: "you-icon-terms", title: "Terms & Conditions", subtitle: "The agreement for using Anky")"""))
        assertTrue(iosYou.contains("PrivacyPolicyReflectionSheet()"))
        assertTrue(iosYou.contains("TermsAndConditionsReflectionSheet()"))
        assertTrue(iosYou.contains(".navigationTitle(AnkyLocalization.ui(\"You\"))"))
        assertTrue(!iosYou.contains("you-icon-credits"))
        assertTrue(!iosYou.contains("you-icon-anky-token"))
        assertTrue(!iosYou.contains("ankyContractDisplayAddress"))
        assertTrue(iosSettings.contains("private var subscriptionSection: some View"))
        assertTrue(iosSettings.contains("await entitlements.restore()"))
        assertTrue(iosSettings.contains("""URL(string: "https://t.me/ankytheapp")"""))

        // Android home mirrors the shape: settings entry, data toggle opening
        // the export surface, gate row, daily target stepper, account row,
        // support/privacy/terms rows, subscription truth, founder chat,
        // device lock, version.
        assertTrue(androidYou.contains("stringResource(R.string.you_title)"))
        assertTrue(androidYou.contains(".align(Alignment.TopCenter)"))
        assertTrue(androidYou.contains("stringResource(R.string.you_customize_row_title)"))
        assertTrue(androidYou.contains("onOpenPage(YouPage.Settings)"))
        assertTrue(androidYou.contains("AnkySettingsScreen("))
        assertTrue(androidYou.contains("val dataSubtitle = if (state.isEncryptedBackupEnabled)"))
        assertTrue(androidYou.contains("R.string.you_encrypted_backup_on"))
        assertTrue(androidYou.contains("R.string.you_export_writings_or_enable_backup"))
        assertTrue(androidYou.contains("DataToggleRow("))
        assertTrue(androidYou.contains("checked = state.isEncryptedBackupEnabled"))
        assertTrue(androidYou.contains("onToggle = onEncryptedBackupToggle"))
        assertTrue(androidYou.contains("stringResource(R.string.you_wbs_row_title)"))
        assertTrue(androidYou.contains("{ onGateSetupRequested() }"))
        assertTrue(androidYou.contains("DailyTargetRow("))
        assertTrue(androidYou.contains("dailyTargetStore.requestTargetChange(minutes)"))
        assertTrue(androidYou.contains("WriteBeforeScrollEventName.TargetChanged"))
        assertTrue(androidYou.contains("""PromptRow(R.drawable.you_icon_support, stringResource(R.string.you_support_feedback), stringResource(R.string.you_email_support)"""))
        assertTrue(androidYou.contains("""PromptRow(R.drawable.you_icon_privacy, stringResource(R.string.you_privacy_policy), stringResource(R.string.you_privacy_subtitle)"""))
        assertTrue(androidYou.contains("""PromptRow(R.drawable.you_icon_terms, stringResource(R.string.you_terms_conditions), stringResource(R.string.you_terms_subtitle)"""))
        assertTrue(androidYou.contains("stringResource(R.string.you_subscription)"))
        assertTrue(androidYou.contains("subscriptionStatusTitle(state.subscription)"))
        assertTrue(androidYou.contains("onOpenPage(YouPage.Subscription)"))
        assertTrue(androidYou.contains("onRestorePurchases = viewModel::restorePurchases"))
        assertTrue(androidYou.contains("context.openUrl(PlayManageSubscriptionsUrl)"))
        assertTrue(androidYou.contains("context.openUrl(FounderChatUrl)"))
        assertTrue(androidYouModel.contains("""internal const val PlayManageSubscriptionsUrl = "https://play.google.com/store/account/subscriptions""""))
        assertTrue(androidYouModel.contains("""internal const val FounderChatUrl = "https://t.me/ankytheapp""""))
        assertTrue(androidYou.contains("DeviceLockRow("))
        assertTrue(androidYou.contains("VersionRow(appVersion = state.appVersion)"))
        assertTrue(androidSettings.contains("fun AnkySettingsScreen("))
        assertTrue(androidSettings.contains("onGateSetupRequested: () -> Unit"))
        assertTrue(androidYouModel.contains("entitlementStore: EntitlementStore? = null"))
        assertTrue(androidYouModel.contains("entitlementStore.restore()") || androidYouModel.contains("store.restore()"))

        // The credits and token surfaces are deleted from the You UI. The
        // route id and YouInitialPage.Credits stay only for AnkyNav/AnkyApp
        // source compatibility until the integrator removes them.
        listOf(
            "CreditsPage(",
            "TokenPage(",
            "YouReflectionCreditsSheet",
            "YouCreditBalancePanel",
            "R.drawable.you_ankycoin",
            "R.string.token_article_body",
            "refreshCredits",
            "purchaseCredits",
        ).forEach { literal ->
            assertTrue("YouScreen.kt still contains $literal", !androidYou.contains(literal))
        }
        listOf(
            "StripeOnrampClient",
            "createAnkyOnrampUrl",
            "freeCreditWhatsAppUrl",
            "wa.me",
            "OkHttpClient",
        ).forEach { literal ->
            assertTrue("YouViewModel.kt still contains $literal", !androidYouModel.contains(literal))
        }

        // Strings live in strings.xml (pre-existing keys) or the new
        // strings_you.xml / strings_settings.xml files.
        listOf(
            "you_title",
            "you_data",
            "you_support_feedback",
            "you_privacy_policy",
            "you_terms_conditions",
            "you_encrypted_backup_on",
            "you_export_writings_or_enable_backup",
            "privacy_page_heading",
            "privacy_article_body",
            "terms_reflection_agreement",
            "terms_article_body",
            "restore_purchases",
            "restoring_purchases",
            "you_customize_row_title",
            "you_wbs_row_title",
            "you_daily_target",
            "you_subscription",
            "you_founder_chat",
            "you_app_version_format",
        ).forEach { key ->
            val defined = androidStrings.contains("""name="$key"""") ||
                androidYouStrings.contains("""name="$key"""") ||
                androidSettingsStrings.contains("""name="$key"""") ||
                androidArticleStrings.contains("""name="$key"""")
            assertTrue("missing string resource $key", defined)
            assertTrue("YouScreen.kt does not reference R.string.$key", androidYou.contains("R.string.$key"))
        }

        // Legal docs: subscription-reality text (July 6, 2026) adapted to
        // Google Play, present in all six locales; the token article is gone.
        assertTrue(androidArticleStrings.contains("Anky, Inc. - Effective July 6, 2026"))
        assertTrue(androidArticleStrings.contains("## 15. Google Play Terms"))
        assertTrue(androidArticleStrings.contains("auto-renewing yearly subscription (\$88/year, with a 3-day free trial for new subscribers)"))
        assertTrue(!androidArticleStrings.contains("name=\"token_article_body\""))
        assertTrue(!androidArticleStrings.contains("Apple"))
        assertTrue(!androidArticleStrings.contains("iCloud"))
        listOf("values-es", "values-fr", "values-de", "values-hi", "values-zh-rCN").forEach { localeDir ->
            val localizedStrings = repoRoot()
                .resolve("apps/android/app/src/main/res/$localeDir/strings.xml")
                .readText()
            val localizedArticleStrings = repoRoot()
                .resolve("apps/android/app/src/main/res/$localeDir/article_strings.xml")
                .readText()
            assertTrue(localizedStrings.contains("you_title"))
            assertTrue(localizedStrings.contains("you_privacy_policy"))
            assertTrue(localizedStrings.contains("you_terms_conditions"))
            assertTrue(localizedStrings.contains("privacy_page_heading"))
            assertTrue(localizedStrings.contains("terms_reflection_agreement"))
            assertTrue(localizedArticleStrings.contains("privacy_article_body"))
            assertTrue(localizedArticleStrings.contains("terms_article_body"))
            assertTrue(!localizedArticleStrings.contains("token_article_body"))
            assertTrue(!localizedArticleStrings.contains("Apple"))
            assertTrue(!localizedArticleStrings.contains("iCloud"))
            assertTrue(localizedArticleStrings.contains("Google Play"))
        }
        assertTrue(androidYou.contains("YouPage.Terms -> TermsPage()"))
        assertTrue(androidYou.contains("ArticleBodyText(stringResource(R.string.terms_article_body))"))
        assertTrue(androidYou.contains("ArticleBodyText(stringResource(R.string.privacy_article_body))"))
    }

    @Test
    fun youDeveloperToolsRemainDebugOnly() {
        val youScreen = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/feature/you/YouScreen.kt")
            .readText()

        assertTrue(youScreen.contains("YouPage.Developer -> if (BuildConfig.DEBUG)"))
        assertTrue(!youScreen.contains("""PromptRow(R.drawable.you_icon_settings, "developer", "local repair tools""""))
    }

    @Test
    fun activeDraftStoreUsesIosStylePrimaryDirectoryAndOpenLegacyFallback() {
        val androidDraftStore = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/core/storage/ActiveDraftStore.kt")
            .readText()
        val iosDraftStore = repoRoot()
            .resolve("apps/ios/Anky/Core/Storage/ActiveDraftStore.swift")
            .readText()

        assertTrue(iosDraftStore.contains("ActiveDrafts"))
        assertTrue(iosDraftStore.contains(".appendingPathComponent(\"Ankys\", isDirectory: true)"))
        assertTrue(iosDraftStore.contains("isOpenDraft(legacyDraft)"))

        assertTrue(androidDraftStore.contains("""File(File(context.filesDir, "ActiveDrafts"), LocalAnkyArchive.CanonicalFileName)"""))
        assertTrue(androidDraftStore.contains("""legacyFile = File(File(context.filesDir, "Ankys"), LocalAnkyArchive.CanonicalFileName)"""))
        assertTrue(androidDraftStore.contains("return legacyDraft.takeIf(::isOpenDraft)"))
        assertTrue(androidDraftStore.contains("AnkyParser.parse(text).terminalSilenceMs == null"))
    }

    @Test
    fun iosImageAssetsHaveAndroidDrawableResources() {
        val androidDrawables: Set<String> = listOf("drawable-nodpi", "drawable")
            .flatMap { directory ->
                Files.walk(repoRoot().resolve("apps/android/app/src/main/res/$directory").toPath()).use { paths ->
                    paths
                        .filter { Files.isRegularFile(it) }
                        .map { path: Path -> path.toFile().nameWithoutExtension }
                        .toList()
                }
            }
            .toSet()
        val missing = iosImageSetDirectories().mapNotNull { imageSet ->
            val parentName = imageSet.name.removeSuffix(".imageset").lowercase().replace("-", "_")
            val fileCandidates = imageSet.listFiles()
                .orEmpty()
                .filter { it.isFile && (it.extension.equals("png", ignoreCase = true) || it.extension.equals("svg", ignoreCase = true)) }
                .flatMap { imageFile ->
                    val assetName = imageFile.nameWithoutExtension
                        .replace(Regex("""@\d+x$"""), "")
                        .lowercase()
                        .replace("-", "_")
                    listOf(
                        assetName,
                        "${parentName}_$assetName",
                    )
                }
            val candidates = (fileCandidates + parentName).toSet()

            if (candidates.any { it in androidDrawables }) {
                null
            } else {
                "${imageSet.relativeTo(repoRoot())}: expected one of ${candidates.sorted()}"
            }
        }

        assertEquals(emptyList<String>(), missing)
    }

    @Test
    fun mainSourcesDoNotUseResourceNameReflection() {
        val violations = sourceFiles("apps/android/app/src/main/java")
            .filter { it.readText().contains("getIdentifier(") }
            .map { it.relativeTo(repoRoot()).path }

        assertEquals(emptyList<String>(), violations)
    }

    private fun sourceFiles(relativePath: String): List<File> =
        Files.walk(repoRoot().resolve(relativePath).toPath()).use { paths ->
            paths
                .filter { Files.isRegularFile(it) }
                .filter { it.toString().endsWith(".kt") }
                .map { it.toFile() }
                .toList()
        }

    private fun iosImageSetDirectories(): List<File> =
        Files.walk(repoRoot().resolve("apps/ios/Anky/Assets.xcassets").toPath()).use { paths ->
            paths
                .filter { Files.isDirectory(it) }
                .map { it.toFile() }
                .filter { it.name.endsWith(".imageset") }
                // Legacy iOS surfaces deliberately not ported to Android (see PARITY.md):
                // check-in flow is dead code on the live iOS AppRoot path.
                .filter { it.name !in setOf("check-in-background.imageset") }
                .toList()
        }

    private fun repoRoot(): File {
        var current = File(checkNotNull(System.getProperty("user.dir"))).canonicalFile
        while (current.parentFile != null) {
            if (current.resolve("protocol/fixtures").isDirectory) return current
            current = checkNotNull(current.parentFile)
        }
        error("Could not find repo root")
    }
}

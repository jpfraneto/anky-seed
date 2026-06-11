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
            .resolve("apps/android/app/src/main/res/values/strings.xml")
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
        assertTrue(androidReveal.contains("copyReflection = stringResource(R.string.copy_reflection)"))
        assertTrue(androidReveal.contains("label = labels.copyReflection.lowercase()"))
        assertTrue(androidStrings.contains("copy reflection"))
        assertTrue(androidRevealViewModel.contains("enum class RevealCopySection"))
        assertTrue(androidRevealViewModel.contains("fun textForCopy(section: RevealCopySection)"))
        assertTrue(androidRevealViewModel.contains("AnkyReflectionPrompt.build(it.reconstructedText)"))
        assertTrue(!androidReveal.contains("""copyText("Anky mirror""""))
    }

    @Test
    fun hiddenWritingInputRejectsMultiGlyphMutations() {
        val hiddenInput = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/feature/write/HiddenTextInput.kt")
            .readText()

        assertTrue(hiddenInput.contains("next.isSingleProtocolGlyph() -> onGlyph(next)"))
        assertTrue(hiddenInput.contains("else -> onRejectedMutation()"))
        assertTrue(hiddenInput.contains("autoCorrectEnabled = false"))
        assertTrue(hiddenInput.contains("keyboardType = KeyboardType.Password"))
        assertTrue(!hiddenInput.contains("keyboardType = KeyboardType.Text"))
        assertTrue(!hiddenInput.contains("protocolGlyphsOrNull"))
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
            "OkHttpClient" to setOf("apps/android/app/src/main/java/inc/anky/android/core/mirror/MirrorClient.kt"),
            "Request.Builder" to setOf("apps/android/app/src/main/java/inc/anky/android/core/mirror/MirrorClient.kt"),
            "newCall(" to setOf("apps/android/app/src/main/java/inc/anky/android/core/mirror/MirrorClient.kt"),
            "Purchases" to setOf(
                "apps/android/app/src/main/java/inc/anky/android/core/credits/RevenueCatCreditsClient.kt",
                "apps/android/app/src/main/java/inc/anky/android/feature/you/YouScreen.kt",
                "apps/android/app/src/main/java/inc/anky/android/feature/you/YouViewModel.kt",
            ),
            "PurchasesConfiguration" to setOf("apps/android/app/src/main/java/inc/anky/android/core/credits/RevenueCatCreditsClient.kt"),
            "PurchaseParams" to setOf("apps/android/app/src/main/java/inc/anky/android/core/credits/RevenueCatCreditsClient.kt"),
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
    fun revenueCatAndroidFallsBackToDirectCreditProductsLikeIos() {
        val creditsClient = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/core/credits/RevenueCatCreditsClient.kt")
            .readText()
        val iosCreditsClient = repoRoot()
            .resolve("apps/ios/Anky/Features/You/RevenueCatCreditsClient.swift")
            .readText()

        assertTrue(iosCreditsClient.contains("missingProductIds"))
        assertTrue(iosCreditsClient.contains("Purchases.shared.products(missingProductIds)"))

        assertTrue(creditsClient.contains("val missingProductIds = CreditCatalog.ProductOrder.filter { it !in packagedProductIds }"))
        assertTrue(creditsClient.contains("purchases.awaitGetProducts(missingProductIds, ProductType.INAPP)"))
        assertTrue(creditsClient.contains("PurchaseParams.Builder(activity, checkNotNull(productToPurchase)).build()"))
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
        assertTrue(androidYou.contains("Encrypted backup is on"))
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
            .resolve("apps/android/app/src/main/res/values/strings.xml")
            .readText()
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
        assertTrue(androidApp.contains("onOpenReveal = { hash -> navController.navigate(AnkyRoute.Reveal.route(hash)) }"))
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
        val androidWrite = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/feature/write/WriteScreen.kt")
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
        assertTrue(iosYouModel.contains("appOpenStore.clear()"))
        assertTrue(iosYouModel.contains("try identityStore.resetForDevelopment(includeICloudBackup: true)"))
        assertTrue(iosYouModel.contains("await creditsClient.logOutIfConfigured()"))
        assertTrue(iosYouModel.contains("ReflectionCreditCache.clear(defaults: defaults)"))
        assertTrue(iosYouModel.contains("Account and data deleted from this device and Anky iCloud backup."))

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
        assertTrue(iosYou.contains("subtitle: creditPackage.price"))
        assertTrue(iosYou.contains("""badge: isRecommended ? AnkyLocalization.ui("recommended") : nil"""))

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
        assertTrue(androidYou.contains("subtitle = creditPackage.price"))
        assertTrue(androidYou.contains("""badge = if (isRecommended) "recommended" else null"""))
    }

    @Test
    fun postWriteCompletionRoutesDirectlyIntoRevealForSmoothAndroidTransition() {
        val androidApp = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/app/AnkyApp.kt")
            .readText()
        val androidWrite = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/feature/write/WriteScreen.kt")
            .readText()
        val iosApp = repoRoot()
            .resolve("apps/ios/Anky/AppRoot.swift")
            .readText()
        val iosMap = repoRoot()
            .resolve("apps/ios/Anky/Features/Map/MapView.swift")
            .readText()
        val iosWriteModel = repoRoot()
            .resolve("apps/ios/Anky/Features/Write/WriteViewModel.swift")
            .readText()

        assertTrue(iosApp.contains("youViewModel.preloadCredits()"))
        assertTrue(iosApp.contains("private func revealOnMap(_ artifact: SavedAnky)"))
        assertTrue(iosApp.contains("revealAfterWriting = artifact"))
        assertTrue(iosApp.contains("selectedTab = 1"))
        assertTrue(iosApp.contains("backUpToICloudIfEnabled()"))
        assertTrue(iosApp.contains("onCompleted: revealOnMap"))
        assertTrue(iosMap.contains("private func openPendingRevealIfNeeded()"))
        assertTrue(iosMap.contains("path = [.reveal(artifact)]"))
        assertTrue(iosMap.contains("revealAfterWriting = nil"))
        assertTrue(iosWriteModel.contains("func importAnkyArtifact(_ text: String) -> Bool"))
        assertTrue(iosWriteModel.contains("completion?(saved)"))

        assertTrue(androidApp.contains("val importedCompletedHash = remember { mutableStateOf<String?>(null) }"))
        assertTrue(androidApp.contains("val handledPostWriteHashes = remember { mutableSetOf<String>() }"))
        assertTrue(androidApp.contains("val postWriteCompletedHash = importedCompletedHash.value ?: writeState.completedHash"))
        assertTrue(androidApp.contains("fun openPostWriteReveal(hash: String)"))
        assertTrue(androidApp.contains("windowInsets = WindowInsets(0.dp)"))
        assertTrue(androidApp.contains("modifier = Modifier.fillMaxSize()"))
        assertTrue(!androidApp.contains("modifier = Modifier.padding(padding)"))
        assertTrue(androidApp.contains("if (!handledPostWriteHashes.add(hash)) return"))
        assertTrue(androidApp.contains("LaunchedEffect(postWriteCompletedHash)"))
        assertTrue(androidApp.contains("LaunchedEffect(writeViewModelWithCurrentMirror)"))
        assertTrue(androidApp.contains(".mapNotNull { it.completedHash }"))
        assertTrue(androidApp.contains(".distinctUntilChanged()"))
        assertTrue(androidApp.contains(".collect { hash -> openPostWriteReveal(hash) }"))
        assertTrue(androidApp.contains("hash != null"))
        assertTrue(!androidApp.contains("if (lockState.value == LockState.Unlocked && hash != null)"))
        assertTrue(androidApp.contains("onImported = { hash ->"))
        assertTrue(androidApp.contains("onCompleted = { hash -> openPostWriteReveal(hash) }"))
        assertTrue(androidWrite.contains("onImported: (String) -> Unit"))
        assertTrue(androidWrite.contains("onCompleted: (String) -> Unit"))
        assertTrue(androidWrite.contains("LaunchedEffect(state.completedHash)"))
        assertTrue(androidWrite.contains("state.completedHash?.let(onCompleted)"))
        assertTrue(androidWrite.contains("onImported(saved.hash)"))
        assertTrue(androidWrite.contains("fun importAndOfferReflection"))
        assertTrue(androidApp.contains("val hash = postWriteCompletedHash"))
        assertTrue(androidApp.contains("importedCompletedHash.value = null"))
        assertTrue(androidApp.contains("writeViewModelWithCurrentMirror.consumeCompletedHash()"))
        assertTrue(androidApp.contains("mapViewModel.refresh()"))
        assertTrue(androidApp.contains("navController.navigate(AnkyRoute.Reveal.route(hash))"))
        assertTrue(androidApp.contains("popUpTo(AnkyRoute.Write.route) { inclusive = true }"))
        assertTrue(androidApp.contains("fun navigateBackFromReveal()"))
        assertTrue(androidApp.contains("if (!navController.popBackStack())"))
        assertTrue(androidApp.contains("navController.navigate(AnkyRoute.Map.route)"))
        assertTrue(androidApp.contains("onBack = { navigateBackFromReveal() }"))
        assertTrue(androidApp.contains("enterTransition = { fadeIn(animationSpec = tween(160)) }"))
        assertTrue(androidApp.contains("exitTransition = { fadeOut(animationSpec = tween(100)) }"))
        assertTrue(!androidApp.contains("val pendingPostWriteRevealHash = remember { mutableStateOf<String?>(null) }"))
        assertTrue(!androidApp.contains("pendingPostWriteRevealHash.value = hash"))
        assertTrue(!androidApp.contains("LaunchedEffect(currentRoute, pendingPostWriteRevealHash.value)"))
        assertTrue(!androidApp.contains("you wrote an anky."))
        assertTrue(!androidApp.contains("""AnkyChatAction("reflect (1 credit)"""))
        assertTrue(!androidApp.contains("""AnkyChatAction("not now")"""))
        assertTrue(!androidApp.contains("rootCreditBalance"))
        assertTrue(!androidApp.contains("onReveal = { hash ->"))
        assertTrue(!androidWrite.contains("fun importAndReveal"))
    }

    @Test
    fun androidWritingSurfaceStaysWhiteOnBlackWithoutInnerRingGlow() {
        val androidWrite = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/feature/write/WriteScreen.kt")
            .readText()

        assertTrue(androidWrite.contains(".background(Color.Black)"))
        assertTrue(androidWrite.contains("SpanStyle(color = Color.White.copy(alpha = alpha))"))
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

        assertTrue(iosWrite.contains("accessibilityLabel(AnkyLocalization.ui(\"Writing time %@\", AnkyDuration.clock(viewModel.elapsedMs)))"))
        assertTrue(androidWrite.contains("val clockText = AnkyDuration.clock(state.elapsedMs)"))
        assertTrue(androidWrite.contains("val writingTimeLabel = stringResource(R.string.writing_time_format, clockText)"))
        assertTrue(androidWrite.contains("contentDescription = writingTimeLabel"))
        assertTrue(androidStrings.contains("""name="writing_time_format""""))
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

        assertTrue(iosWrite.contains("accessibilityLabel(AnkyLocalization.ui(\"Open Map\"))"))
        listOf("open_map").forEach { key ->
            assertTrue(androidWrite.contains("R.string.$key"))
            assertTrue(androidStrings.contains("""name="$key""""))
        }
        assertTrue(androidWrite.contains("contentDescription = openMapLabel"))
        assertTrue(!androidWrite.contains("contentDescription = pasteArtifactLabel"))
        assertTrue(!androidWrite.contains("onClick(pasteArtifactLabel)"))
        assertTrue(!androidWrite.contains("onLongClick(devPasteArtifactLabel)"))
        assertTrue(!androidWrite.contains("contentDescription = \"Open Map\""))
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
        assertTrue(androidStrings.contains("""name="continue_writing_left">CONTINUE - %1${'$'}s LEFT</string>"""))
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
        assertTrue(iosReveal.contains("Color.red.opacity(0.88)"))
        assertTrue(iosReveal.contains("Color.red.opacity(0.22)"))

        assertTrue(androidReveal.contains("RevealTopBar("))
        assertTrue(androidReveal.contains("deleteContentDescription = labels.deleteWritingSession"))
        assertTrue(androidReveal.contains("contentDescription = deleteContentDescription"))
        assertTrue(androidReveal.contains("val backLabel = stringResource(R.string.back)"))
        assertTrue(androidReveal.contains("contentDescription = backLabel"))
        assertTrue(!androidReveal.contains("contentDescription = \"Back\""))
        assertTrue(androidReveal.contains("AnkyColors.Danger.copy(alpha = 0.88f)"))
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
        assertTrue(androidReveal.contains("LaunchedEffect(startsReflectionOnAppear, state.reflection)"))
        assertTrue(androidReveal.contains("!didAutoStartReflection"))
        assertTrue(androidReveal.contains("state.reflection == null"))
        assertTrue(androidReveal.contains("didAutoStartReflection = true"))
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
        assertTrue(androidMap.contains("contentDescription = sessionAccessibilityLabel(session)"))
        assertTrue(androidMap.contains("internal fun sessionAccessibilityLabel"))
        assertTrue(androidMap.contains("session.reflectedTitle(),\n        session.preview"))
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
        assertTrue(androidMap.contains("fontSize = 18.sp,\n                        fontWeight = FontWeight.SemiBold,\n                        color = AnkyColors.Gold.copy(alpha = 0.78f)"))
        assertTrue(androidMap.contains("fontSize = 29.sp,\n                        fontWeight = FontWeight.Bold,\n                        color = AnkyColors.Gold"))
        assertTrue(androidMap.contains(".padding(top = 16.dp, bottom = 18.dp)"))
        assertTrue(androidMap.contains("fontSize = 20.sp"))
        assertTrue(androidMap.contains("lineHeight = 28.sp"))
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
        assertTrue(androidMap.contains("Spacer(Modifier.fillMaxWidth().height(180.dp))"))
        assertTrue(androidMap.contains("labels.noWritingSaved"))
        assertTrue(!androidMap.contains("Text(\"no writing saved\", style = AnkyType.Body.copy(fontSize = 20.sp, color = AnkyColors.PaperMuted)"))
        assertTrue(!androidMap.contains("Text(\"no writing saved\", style = AnkyType.Heading.copy(fontSize = 20.sp"))
        assertTrue(!androidMap.contains("style = AnkyType.Heading.copy(fontSize = 20.sp, color = AnkyColors.PaperMuted)"))
    }

    @Test
    fun mapDayDetailOwnsIosStyleTexturedBackground() {
        val androidMap = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/feature/map/MapScreen.kt")
            .readText()
        val iosMap = repoRoot()
            .resolve("apps/ios/Anky/Features/Map/MapView.swift")
            .readText()

        assertTrue(iosMap.contains("MapDayBackground()"))
        assertTrue(iosMap.contains("Image(\"map-background\")"))
        assertTrue(iosMap.contains("MapDayPalette.ink"))
        assertTrue(iosMap.contains(".opacity(0.76)"))

        assertTrue(androidMap.contains("private fun DayDetail("))
        assertTrue(androidMap.contains("painterResource(R.drawable.map_background)"))
        assertTrue(androidMap.contains("contentScale = ContentScale.Crop"))
        assertTrue(androidMap.contains("AnkyColors.Ink.copy(alpha = 0.76f)"))
    }

    @Test
    fun mapDayDetailTitleUsesIosInlineNavigationScale() {
        val androidMap = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/feature/map/MapScreen.kt")
            .readText()
        val iosMap = repoRoot()
            .resolve("apps/ios/Anky/Features/Map/MapView.swift")
            .readText()

        assertTrue(iosMap.contains(".navigationTitle(title)"))
        assertTrue(iosMap.contains(".navigationBarTitleDisplayMode(.inline)"))
        assertTrue(iosMap.contains(".toolbarBackground(MapDayPalette.ink.opacity(0.96), for: .navigationBar)"))

        assertTrue(androidMap.contains("private fun MapSessionTopBar("))
        assertTrue(androidMap.contains("Column(Modifier.fillMaxWidth().background(AnkyColors.Ink.copy(alpha = 0.96f)))"))
        assertTrue(androidMap.contains(".height(58.dp)"))
        assertTrue(androidMap.contains(".padding(horizontal = 12.dp)"))
        assertTrue(androidMap.contains("fontSize = 16.sp,\n                    fontWeight = FontWeight.SemiBold,\n                    color = AnkyColors.Paper"))
        assertTrue(androidMap.contains("textAlign = TextAlign.Center"))
        assertTrue(androidMap.contains("modifier = Modifier.weight(1f).padding(horizontal = 8.dp)"))
        assertTrue(androidMap.contains("Box(Modifier.fillMaxWidth().height(1.dp).background(AnkyColors.Gold.copy(alpha = 0.13f)))"))
        assertTrue(!androidMap.contains("DateTimeFormatter.ofPattern(\"MMMM d, yyyy\").withZone(ZoneOffset.UTC).format(Instant.ofEpochMilli(day.dayEpochMs)).lowercase(),\n                    style = AnkyType.Heading"))
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
        assertTrue(iosMap.contains("let date = day.isToday ? \"Today\" : formattedUTCDate(day.date, dateFormat: nil)"))
        assertTrue(iosMap.contains("return \"\\(date), \\(day.trailActivitySummary)\""))

        assertTrue(androidMap.contains("contentDescription = dayAccessibilityLabel(day, labels.today)"))
        assertTrue(androidMap.contains("internal fun dayAccessibilityLabel"))
        assertTrue(androidMap.contains("today = stringResource(R.string.map_today)"))
        assertTrue(androidMap.contains("""return "${'$'}date, ${'$'}{day.trailActivitySummary}""""))
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
    fun mapTrailNodeTextureUsesIosBlackFillAndColoredStroke() {
        val androidMap = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/feature/map/MapScreen.kt")
            .readText()
        val iosMap = repoRoot()
            .resolve("apps/ios/Anky/Features/Map/MapView.swift")
            .readText()

        assertTrue(iosMap.contains("Circle()\n                .fill(Color.black.opacity(day.hasAnky ? 0.76 : 0.58))"))
        assertTrue(iosMap.contains(".fill(nodeTexture)"))
        assertTrue(iosMap.contains(".stroke(nodeStroke, lineWidth: day.isToday ? 3 : 2)"))

        assertTrue(androidMap.contains("drawCircle(Color.Black.copy(alpha = if (hasAnky) 0.76f else 0.58f))"))
        assertTrue(androidMap.contains("Brush.linearGradient"))
        assertTrue(androidMap.contains("color = if (hasAnky) nodeFill.copy(alpha = 0.76f) else Color.White.copy(alpha = 0.18f)"))
        assertTrue(!androidMap.contains("drawCircle(nodeFill.copy(alpha = if (hasAnky)"))
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
        assertTrue(iosTags.contains("RevealBackgroundTexture()"))
        assertTrue(iosTags.contains("Text(tag)"))
        assertTrue(iosTags.contains("""Text(AnkyLocalization.ui("no saved sessions with this tag."))"""))
        assertTrue(iosTags.contains("""AnkyLocalization.ui(summary.wordCount == 1 ? "word" : "words")"""))
        assertTrue(androidTags.contains("fun refreshSessions()"))
        assertTrue(androidTags.contains("sessionIndexStore.sessionsWithTag(tag)"))
        assertTrue(androidTags.contains("RevealTagTexture()"))
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
        assertTrue(androidTags.contains("AnkyColors.Violet.copy(alpha = alpha)"))
        assertTrue(androidTags.contains("Triple(1.34f, 360.dp.toPx(), 0.018f)"))
        assertTrue(androidTags.contains("Triple(1.20f, bloomHeight, 0.030f)"))
        assertTrue(androidTags.contains("Triple(1.06f, 220.dp.toPx(), 0.024f)"))
        assertTrue(androidTags.contains("Text(\n                        tag,"))
        assertTrue(iosTags.contains(".font(.system(size: 30, weight: .bold))"))
        assertTrue(androidTags.contains("AnkyType.Heading.copy(fontSize = 30.sp, fontWeight = FontWeight.Bold, color = AnkyColors.Gold)"))
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
        assertTrue(androidTags.contains("fontSize = 12.sp, fontWeight = FontWeight.Medium, color = AnkyColors.Paper.copy(alpha = 0.58f)"))
        assertTrue(androidTags.contains("fontSize = 12.sp, fontWeight = FontWeight.Medium, color = AnkyColors.Paper.copy(alpha = 0.48f)"))
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
            .resolve("apps/android/app/src/main/res/values/strings.xml")
            .readText()

        listOf(
            "copy_writing",
            "read_reflection",
            "reflect_this_anky",
            "reflect_this_anky_left",
            "reflect_this_anky_device_gift",
            "receiving_reflection",
            "get_more_credits",
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
            assertTrue(androidReveal.contains("R.string.$key"))
            assertTrue(androidStrings.contains("""name="$key""""))
        }
        assertTrue(!androidReveal.contains("i have reflected this anky."))
        assertTrue(!androidReveal.contains("i am holding the mirror open."))
        assertTrue(androidReveal.contains("StreamingReflectionPanel("))
        assertTrue(androidReveal.contains("SavedReflectionPanel("))
        assertTrue(!androidReveal.contains("hide live text"))
        assertTrue(androidReveal.contains("state.canSubmitReflectionRequest"))
        assertTrue(androidReveal.contains("viewModel.askAnky()"))
        assertTrue(!androidReveal.contains("the reflection is not here yet."))
        assertTrue(androidReveal.contains("state.streamingReflectionMarkdown.isNotBlank() ->"))
        assertTrue(!androidReveal.contains("state.streamingReflectionMarkdown.isNotBlank() || state.isAsking"))
        assertTrue(androidReveal.contains("MarkdownishText(body)"))
        assertTrue(androidReveal.contains("labels.writingReflectionCharacters(state.streamingReflectionCharacterCount)"))
        assertTrue(androidReveal.contains("MarkdownishText(reflection.displayBody)"))
        assertTrue(androidReveal.contains("tags.forEach { tag ->"))
        assertTrue(!androidReveal.contains("tags.take(8).forEach"))
        assertTrue(androidReveal.contains("AnkyType.Mono.copy("))
        assertTrue(androidReveal.contains("letterSpacing = 1.sp"))
        assertTrue(androidReveal.contains("AnkyColors.Paper.copy(alpha = 0.46f)"))
        assertTrue(androidReveal.contains("fontSize = 12.sp, fontWeight = FontWeight.Medium, color = AnkyColors.Gold"))
        assertTrue(androidReveal.contains("Column(modifier = Modifier.padding(top = 2.dp), verticalArrangement = Arrangement.spacedBy(8.dp))"))
        assertTrue(!androidReveal.contains("displayBodyWithTitle"))
        assertTrue(androidReveal.contains("private fun ReflectionScrollGlyph(modifier: Modifier = Modifier)"))
        assertTrue(androidReveal.contains("mirrorForming = stringResource(R.string.reveal_mirror_forming)"))
        assertTrue(androidReveal.contains("labels.mirrorForming"))
        assertTrue(androidReveal.contains("chatStayingWithAnky = stringResource(R.string.reveal_chat_staying_with_anky)"))
        assertTrue(androidReveal.contains("chatOpenMirror = stringResource(R.string.reveal_chat_open_mirror)"))
        assertTrue(androidReveal.contains("shortSessionMessages = listOf("))
        assertTrue(androidReveal.contains("message = reflectionInvitationMessage(state, labels)"))
        assertTrue(androidReveal.contains("message = shortSessionMessage(state, labels)"))
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
        assertTrue(androidReveal.contains("ModalBottomSheet("))
        assertTrue(androidReveal.contains("RevealCreditPurchaseSheet("))
        assertTrue(androidReveal.contains("state.needsCreditsToReflect -> labels.getMoreCredits"))
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
        assertTrue(androidReveal.contains("Color.Black.copy(alpha = 0.28f)"))
        assertTrue(androidReveal.contains("AnkyColors.Gold.copy(alpha = 0.22f)"))
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
    fun revealCreditPurchaseSheetUsesCurrentIosCreditsSurface() {
        val androidReveal = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/feature/reveal/RevealScreen.kt")
            .readText()
        val iosCreditsSheet = repoRoot()
            .resolve("apps/ios/Anky/Features/Credits/AnkyReflectionCreditsSheet.swift")
            .readText()
        val iosReveal = repoRoot()
            .resolve("apps/ios/Anky/Features/Reveal/RevealView.swift")
            .readText()
        val androidStrings = repoRoot()
            .resolve("apps/android/app/src/main/res/values/strings.xml")
            .readText()

        listOf(
            "Anky reflection credits",
            "Your private space to be witnessed.",
            "available\\ncredits",
            "Writing is free. One credit = one reflection.",
            "loading credit packs",
            "no credit packs available",
            "best value",
            "credits-thread-background",
        ).forEach { copy ->
            assertTrue(iosCreditsSheet.contains(copy))
        }
        assertTrue(iosReveal.contains(".ankyReflectionCreditsSheet("))
        assertTrue(iosCreditsSheet.contains("AnkyReflectionCreditsSheet("))

        listOf(
            "credits_sheet_title",
            "credits_sheet_subtitle",
            "refresh_reflection_credits",
            "loading_credit_packs",
            "no_credit_packs_available",
            "writing_is_free_one_credit_reflection",
            "credits_sheet_prompt_copy_fallback",
            "available_credits",
            "best_value",
        ).forEach { key ->
            assertTrue(androidReveal.contains("R.string.$key"))
            assertTrue(androidStrings.contains("""name="$key""""))
        }
        listOf(
            "labels.creditsSheetTitle",
            "labels.creditsSheetSubtitle",
            "labels.refreshReflectionCredits",
            "labels.loadingCreditPacks",
            "labels.noCreditPacksAvailable",
            "labels.writingIsFreeOneCreditReflection",
            "labels.creditsSheetPromptCopyFallback",
            "labels.availableCredits",
            "bestValue",
            "R.drawable.credits_thread_background",
        ).forEach { copy ->
            assertTrue(androidReveal.contains(copy))
        }
        assertTrue(androidReveal.contains("RevealCreditPurchaseSheet("))
        assertTrue(androidReveal.contains("shape = RoundedCornerShape(topStart = 38.dp, topEnd = 38.dp)"))
        assertTrue(androidReveal.contains("containerColor = CreditsPalette.AlmostBlack"))
        assertTrue(androidReveal.contains("dragHandle = null"))
        assertTrue(androidReveal.contains("RevealCreditsSheetBackground(Modifier.matchParentSize())"))
        assertTrue(androidReveal.contains(".verticalScroll(rememberScrollState())"))
        assertTrue(androidReveal.contains("RefreshGlyph(Modifier.size(22.dp))"))
        assertTrue(androidReveal.contains("private fun RefreshGlyph"))
        assertTrue(!androidReveal.contains("Icons.Filled.Refresh"))
        assertTrue(androidReveal.contains("Icons.Filled.AutoAwesome"))
        assertTrue(androidStrings.contains("Don\\'t want to pay? Long press the copy button on a finished Anky and then send what will be copied to your favorite AI tool"))
        assertTrue(!androidReveal.contains("\"Anky reflection credits\""))
        assertTrue(!androidReveal.contains("\"Your private space to be witnessed.\""))
        assertTrue(!androidReveal.contains("\"available\\ncredits\""))
        assertTrue(!androidReveal.contains("\"Writing is free. One credit = one reflection.\""))
        assertTrue(!androidReveal.contains("\"loading credit packs\""))
        assertTrue(!androidReveal.contains("\"no credit packs available\""))
        assertTrue(!androidReveal.contains("\"best value\""))
        assertTrue(!androidReveal.contains("Text(\"↻\""))
        assertTrue(!androidReveal.contains("Text(\"✦\""))
        assertTrue(!androidReveal.contains("writing stays free. each reflection spends one credit."))
        assertTrue(!androidReveal.contains("\"recommended\""))
    }

    @Test
    fun reflectionCreditBalanceCacheMirrorsIosPerAccountPersistence() {
        val iosEligibility = repoRoot()
            .resolve("apps/ios/Anky/Core/Mirror/MirrorEligibility.swift")
            .readText()
        val iosReveal = repoRoot()
            .resolve("apps/ios/Anky/Features/Reveal/RevealViewModel.swift")
            .readText()
        val iosYou = repoRoot()
            .resolve("apps/ios/Anky/Features/You/YouViewModel.swift")
            .readText()
        val iosYouView = repoRoot()
            .resolve("apps/ios/Anky/Features/You/YouView.swift")
            .readText()
        val iosLocalization = repoRoot()
            .resolve("apps/ios/Anky/Support/AnkyLocalization.swift")
            .readText()
        val androidCache = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/core/credits/ReflectionCreditCache.kt")
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

        assertTrue(iosEligibility.contains("enum ReflectionCreditCache"))
        assertTrue(iosEligibility.contains("private static let claimedKey = \"anky.hasClaimedFreeReflections\""))
        assertTrue(iosEligibility.contains("private static let balanceKey = \"anky.reflectionCreditBalance\""))
        assertTrue(iosEligibility.contains("static func hasClaimedFreeCredits(accountId: String"))
        assertTrue(iosEligibility.contains("static func markFreeCreditsClaimed(accountId: String"))
        assertTrue(iosEligibility.contains("static func balance(accountId: String"))
        assertTrue(iosEligibility.contains("static func storeBalance(_ balance: Int?"))
        assertTrue(iosReveal.contains("hasClaimedFreeCredits = ReflectionCreditCache.hasClaimedFreeCredits(accountId: identity.accountId"))
        assertTrue(iosReveal.contains("ReflectionCreditCache.markFreeCreditsClaimed(accountId: accountId"))
        assertTrue(iosReveal.contains("creditBalance = ReflectionCreditCache.balance(accountId: identity.accountId"))
        assertTrue(iosReveal.contains("ReflectionCreditCache.storeBalance(response.creditsRemaining"))
        assertTrue(iosReveal.contains("ReflectionCreditCache.storeBalance(creditBalance, accountId: identity.accountId"))
        assertTrue(iosYou.contains("hasClaimedFreeCredits = ReflectionCreditCache.hasClaimedFreeCredits(accountId: accountId"))
        assertTrue(iosYou.contains("creditBalance = ReflectionCreditCache.balance(accountId: accountId"))
        assertTrue(iosYou.contains("ReflectionCreditCache.storeBalance(balance, accountId: accountId"))
        assertTrue(iosYouView.contains(".onAppear {\n            viewModel.refresh()"))
        assertTrue(iosYou.contains("guard canPurchaseCredits else"))
        assertTrue(iosYou.contains("statusMessage = AnkyLocalization.text(.spendGiftBeforeBuying)"))
        assertTrue(iosYou.contains("var presentedCreditBalance: Int?"))
        assertTrue(iosYou.contains("var hasUnspentGiftCredit: Bool"))
        assertTrue(iosLocalization.contains("This device has two free reflections from Anky. Use them before buying more credits."))
        assertTrue(iosLocalization.contains("Credit packs unlock after this device spends its first two reflections"))
        assertTrue(iosLocalization.contains("Use this device's first two reflections before buying more credits."))

        assertTrue(androidCache.contains("interface ReflectionCreditCache"))
        assertTrue(androidCache.contains("const val ClaimedKey = \"anky.hasClaimedFreeReflections\""))
        assertTrue(androidCache.contains("const val BalanceKey = \"anky.reflectionCreditBalance\""))
        assertTrue(androidCache.contains("fun hasClaimedFreeCredits(accountId: String): Boolean"))
        assertTrue(androidCache.contains("fun markFreeCreditsClaimed(accountId: String)"))
        assertTrue(androidCache.contains("fun balance(accountId: String): Int?"))
        assertTrue(androidCache.contains("fun storeBalance(balance: Int?, accountId: String)"))
        assertTrue(androidApp.contains("SharedPreferencesReflectionCreditCache(appContext)"))
        assertTrue(androidRoot.contains("container.reflectionCreditCache.hasClaimedFreeCredits(container.identityStore.loadOrCreate().accountId)"))
        assertTrue(androidRoot.contains("container.reflectionCreditCache.markFreeCreditsClaimed(container.identityStore.loadOrCreate().accountId)"))
        assertTrue(androidReveal.contains("hasClaimedFreeCreditsProvider() || reflectionStore.list().isNotEmpty()"))
        assertTrue(androidReveal.contains("markFreeCreditsClaimed()"))
        assertTrue(androidReveal.contains("cachedCreditBalance()"))
        assertTrue(androidReveal.contains("reflectionCreditCache.storeBalance(payload.creditsRemaining, identity.accountId)"))
        assertTrue(androidReveal.contains("reflectionCreditCache.storeBalance(creditState.balance, accountId)"))
        assertTrue(androidYou.contains("cachedCreditState(reflectionCreditCache.balance(identity.accountId))"))
        assertTrue(androidYou.contains("reflectionCreditCache.storeBalance(refreshed.balance, accountId)"))
        assertTrue(androidYou.contains("fun refresh()"))
        assertTrue(androidYouScreen.contains("viewModel.refresh()"))
        assertTrue(androidYou.contains("val presentedCreditBalance: Int?"))
        assertTrue(androidYou.contains("val hasUnspentGiftCredit: Boolean"))
        assertTrue(androidYou.contains("if (!_state.value.canPurchaseCredits)"))
        assertTrue(androidYou.contains("YouStatusCopy.SpendGiftBeforeBuying"))
        assertTrue(androidYouScreen.contains("state.hasUnspentGiftCredit"))
        assertTrue(androidYouScreen.contains("YouStatusCopy.CreditPacksLocked"))
        assertTrue(androidYouScreen.contains("YouStatusCopy.CreditGiftPrompt"))
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
        assertTrue(androidYou.contains("Send us an email! We want to evolve this app based on your feedback."))
        assertTrue(androidYou.contains("stringResource(R.string.you_support_feedback)"))
        assertTrue(androidStrings.contains("Support / Feedback"))
        assertTrue(androidModel.contains("supportFeedbackEmailUrl"))
        assertTrue(!androidYou.contains("support messages include your account id, not your writing."))
        assertTrue(!androidYou.contains("copy privacy email"))
        assertTrue(!androidYou.contains("manual credit help"))
    }

    @Test
    fun androidPrivacyPolicyLinksPointToAndroidSourceFiles() {
        val androidYou = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/feature/you/YouScreen.kt")
            .readText()

        listOf(
            "apps/android/app/src/main/java/inc/anky/android/core/storage/LocalAnkyArchive.kt",
            "apps/android/app/src/main/java/inc/anky/android/core/protocol",
            "apps/android/app/src/main/java/inc/anky/android/core/identity/WriterIdentityStore.kt",
            "apps/android/app/src/main/java/inc/anky/android/core/mirror/MirrorClient.kt",
            "apps/android/app/src/main/java/inc/anky/android/core/storage/BackupImporter.kt",
            "apps/android/app/src/main/java/inc/anky/android/feature/you/YouViewModel.kt",
        ).forEach { sourcePath ->
            assertTrue(androidYou.contains(sourcePath))
        }

        listOf(
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
        assertTrue(androidStrings.contains("""name="daily_reminder_notification_body" translatable="false">write your anky today</string>"""))
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
        assertTrue(androidYou.contains("local Base account, stores its recovery phrase in device secure storage"))
        assertTrue(!androidYou.contains("private identity"))
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
        val resetWarning = "Resetting identity creates a new Anky Base account. Credits are tied to your current account. Save your recovery phrase before resetting."

        assertTrue(!iosYou.contains(".confirmationDialog(\"reset local identity?\""))
        assertTrue(!iosYou.contains("Button(\"reset identity\", role: .destructive)"))

        assertTrue(androidYou.contains("title = \"reset local identity?\""))
        assertTrue(androidYou.contains("action = \"reset identity\""))
        assertTrue(androidYou.contains("message = \"$resetWarning\""))
        assertTrue(androidYou.contains("text = message?.let"))
        assertTrue(androidYou.contains("YouPage.Developer -> if (BuildConfig.DEBUG)"))
        assertTrue(androidYou.contains("AnkyActionButton(\"reset local identity\", destructive = true"))
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
        assertTrue(androidYou.contains("activePrompt?.message.orEmpty()"))
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
        val androidApp = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/app/AnkyApp.kt")
            .readText()
        val androidHiddenInput = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/feature/write/HiddenTextInput.kt")
            .readText()
        val androidStrings = repoRoot()
            .resolve("apps/android/app/src/main/res/values/strings.xml")
            .readText()
        val iosEnglishStrings = repoRoot()
            .resolve("apps/ios/Anky/en.lproj/Localizable.strings")
            .readText()

        listOf(
            "onboarding-1",
            "onboarding-2",
            "onboarding-3",
            "You don't need another place to perform.",
            "Anky gives you 8 minutes to let out what you're carrying.",
            "At the end, you see what was underneath.",
            "Be with what is here",
            "Let it all out",
            "Write 8 minutes",
        ).forEach { expected ->
            assertTrue(iosOnboarding.contains(expected))
        }
        assertTrue(iosApp.contains("@AppStorage(\"anky.onboardingCompleted\")"))
        assertTrue(iosApp.contains("if shouldShowOnboarding"))
        assertTrue(iosApp.contains("AnkyOnboardingView {"))
        assertTrue(iosApp.contains("completeOnboarding()"))
        assertTrue(iosApp.contains("onboardingCompleted = true"))
        assertTrue(iosApp.contains("writeViewModel.openWritingPortal()"))

        listOf(
            "R.drawable.onboarding_1",
            "R.drawable.onboarding_2",
            "R.drawable.onboarding_3",
            "R.string.onboarding_line_1",
            "R.string.onboarding_line_2",
            "R.string.onboarding_line_3",
            "R.string.onboarding_cta_1",
            "R.string.onboarding_cta_2",
            "R.string.onboarding_cta_3",
            "R.string.onboarding_accessibility_label",
            "HorizontalPager(",
            "AnkyOnboardingScreen(",
        ).forEach { expected ->
            assertTrue(androidOnboarding.contains(expected) || androidApp.contains(expected))
        }
        listOf(
            "You don\\'t need another place to perform.",
            "Anky gives you 8 minutes to let out what you\\'re carrying.",
            "At the end, you see what was underneath.",
            "Be with what is here",
            "Let it all out",
            "Write 8 minutes",
        ).forEach { expected ->
            assertTrue(androidStrings.contains(expected))
        }
        assertTrue(iosEnglishStrings.contains("\"writeEightMinutes\" = \"Write 8 minutes\";"))
        assertTrue(androidStrings.contains("""name="onboarding_cta_1">Be with what is here</string>"""))
        assertTrue(androidStrings.contains("""name="onboarding_cta_2">Let it all out</string>"""))
        assertTrue(androidStrings.contains("""name="onboarding_cta_3">Write 8 minutes</string>"""))
        assertTrue(androidStrings.contains("""name="onboarding_accessibility_label">Anky onboarding</string>"""))
        assertTrue(!androidStrings.contains("""name="onboarding_cta_1" translatable="false""""))
        assertTrue(!androidStrings.contains("""name="onboarding_cta_2" translatable="false""""))
        assertTrue(!androidStrings.contains("""name="onboarding_cta_3" translatable="false""""))
        assertTrue(androidOnboarding.contains("onboardingAccessibilityLabel = stringResource(R.string.onboarding_accessibility_label)"))
        assertTrue(androidOnboarding.contains("contentDescription = onboardingAccessibilityLabel"))
        assertTrue(!androidOnboarding.contains("""contentDescription = "Anky onboarding""""))
        listOf("values-es", "values-fr", "values-de", "values-hi", "values-zh-rCN").forEach { localeDir ->
            val localizedStrings = repoRoot()
                .resolve("apps/android/app/src/main/res/$localeDir/strings.xml")
                .readText()
            val iosLocaleDir = when (localeDir) {
                "values-zh-rCN" -> "zh-Hans"
                else -> localeDir.removePrefix("values-")
            }
            val iosLocalizedStrings = repoRoot()
                .resolve("apps/ios/Anky/$iosLocaleDir.lproj/Localizable.strings")
                .readText()
            val expectedCta = when (localeDir) {
                "values-es" -> "Escribir 8 minutos"
                "values-fr" -> "Écrire 8 minutes"
                "values-de" -> "8 Minuten schreiben"
                "values-hi" -> "8 मिनट लिखें"
                "values-zh-rCN" -> "书写 8 分钟"
                else -> error("Unhandled locale $localeDir")
            }
            val expectedFirstCta = when (localeDir) {
                "values-es" -> "Quédate con lo que está aquí"
                "values-fr" -> "Restez avec ce qui est là"
                "values-de" -> "Bleib bei dem, was hier ist"
                "values-hi" -> "जो यहाँ है उसके साथ रहें"
                "values-zh-rCN" -> "和此刻在这里的东西待在一起"
                else -> error("Unhandled locale $localeDir")
            }
            val expectedSecondCta = when (localeDir) {
                "values-es" -> "Déjalo salir todo"
                "values-fr" -> "Laissez tout sortir"
                "values-de" -> "Lass alles heraus"
                "values-hi" -> "सब बाहर आने दें"
                "values-zh-rCN" -> "把一切都释放出来"
                else -> error("Unhandled locale $localeDir")
            }
            assertTrue(localizedStrings.contains("onboarding_line_1"))
            assertTrue(localizedStrings.contains("""name="onboarding_cta_1">$expectedFirstCta</string>"""))
            assertTrue(localizedStrings.contains("""name="onboarding_cta_2">$expectedSecondCta</string>"""))
            assertTrue(localizedStrings.contains("""name="onboarding_cta_3">$expectedCta</string>"""))
            assertTrue(localizedStrings.contains("onboarding_accessibility_label"))
            assertTrue(iosLocalizedStrings.contains("\"writeEightMinutes\""))
            assertTrue(iosLocalizedStrings.contains(expectedCta))
            assertTrue(localizedStrings.contains("tab_write"))
            assertTrue(localizedStrings.contains("device_lock_prompt"))
        }
        assertTrue(androidApp.contains("val showsOnboarding = remember(settings.onboardingCompleted) { mutableStateOf(!settings.onboardingCompleted) }"))
        assertTrue(androidApp.contains("container.settingsStore.setOnboardingCompleted(true)"))
        assertTrue(androidApp.contains("val shouldShowOnboarding ="))
        assertTrue(androidApp.contains("!shouldShowOnboarding"))
        assertTrue(androidApp.contains("inputEnabled = !shouldShowOnboarding"))
        assertTrue(androidHiddenInput.contains("inputEnabled: Boolean = true"))
        assertTrue(androidHiddenInput.contains("if (!inputEnabled) return@LaunchedEffect"))
        assertTrue(androidApp.contains("showsOnboarding.value = false"))
        assertTrue(androidApp.contains("writeViewModelWithCurrentMirror.openWritingPortal()"))
    }

    @Test
    fun youHomeRowsMatchCurrentIosPromptAndLegalShape() {
        val androidYou = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/feature/you/YouScreen.kt")
            .readText()
        val iosYou = repoRoot()
            .resolve("apps/ios/Anky/Features/You/YouView.swift")
            .readText()
        val androidTokenIcon = repoRoot()
            .resolve("apps/android/app/src/main/res/drawable/you_icon_anky_token.xml")
            .readText()
        val androidStrings = repoRoot()
            .resolve("apps/android/app/src/main/res/values/strings.xml")
            .readText()

        assertTrue(iosYou.contains("""promptButton(.credits, icon: "you-icon-credits", title: "Credits", subtitle: creditsMenuSubtitle)"""))
        assertTrue(iosYou.contains("private func openCreditsSheet()"))
        assertTrue(iosYou.contains("showsReflectionCreditsSheet = true"))
        assertTrue(iosYou.contains(".ankyReflectionCreditsSheet("))
        assertTrue(iosYou.contains("""promptButton(.support, icon: "you-icon-support", title: "Support / Feedback", subtitle: "Email support@anky.app")"""))
        assertTrue(iosYou.contains("""promptButton(.privacy, icon: "you-icon-privacy", title: "Privacy Policy", subtitle: "How your data is handled.")"""))
        assertTrue(iosYou.contains("""legalButton(icon: "you-icon-terms", title: "Terms & Conditions", subtitle: "The agreement for using Anky")"""))
        assertTrue(iosYou.contains("Text(\"Writing and reflection agreement\")"))
        assertTrue(iosYou.contains("YouRuleRow(AnkyLocalization.ui(\"1 credit = reflection\"))"))
        assertTrue(iosYou.contains("YouRuleRow(AnkyLocalization.ui(\"ask anky spends one credit\"))"))
        assertTrue(iosYou.contains("YouRuleRow(AnkyLocalization.ui(\"writing is always free\"))"))
        assertTrue(iosYou.contains("YouActionButton(AnkyLocalization.ui(\"refresh credits\"))"))
        assertTrue(iosYou.contains("YouActionButton(AnkyLocalization.ui(\"support / feedback\"))"))
        assertTrue(iosYou.contains("Text(AnkyLocalization.ui(\"email support@anky.app. include only what you choose to write.\"))"))
        assertTrue(iosYou.contains("""icon: "you-icon-anky-token""""))
        assertTrue(iosYou.contains("""title: "${'$'}ANKY""""))
        assertTrue(iosYou.contains("""subtitle: didCopyAnkyContract ? "Copied to clipboard" : ankyContractDisplayAddress"""))
        assertTrue(iosYou.contains(".navigationTitle(AnkyLocalization.ui(\"You\"))"))
        assertTrue(iosYou.contains(".navigationBarTitleDisplayMode(.inline)"))

        assertTrue(androidYou.contains("stringResource(R.string.you_title)"))
        assertTrue(androidYou.contains(".align(Alignment.TopCenter)"))
        assertTrue(androidYou.contains("val dataSubtitle = if (state.isEncryptedBackupEnabled)"))
        assertTrue(androidYou.contains("R.string.you_encrypted_backup_on"))
        assertTrue(androidYou.contains("R.string.you_export_writings_or_enable_backup"))
        assertTrue(androidYou.contains("DataToggleRow("))
        assertTrue(androidYou.contains("checked = state.isEncryptedBackupEnabled"))
        assertTrue(androidYou.contains("onEncryptedBackupToggle = { enabled ->"))
        assertTrue(androidYou.contains("val showsReflectionCreditsSheet = remember { mutableStateOf(false) }"))
        assertTrue(androidYou.contains("showsReflectionCreditsSheet.value = true"))
        assertTrue(androidYou.contains("ModalBottomSheet("))
        assertTrue(androidYou.contains("YouReflectionCreditsSheet("))
        assertTrue(androidYou.contains("val creditsSubtitle = creditsMenuSubtitle("))
        assertTrue(androidYou.contains("R.string.you_loading_balance"))
        assertTrue(androidYou.contains("R.string.you_reflection_balance"))
        assertTrue(androidYou.contains("""PromptRow(R.drawable.you_icon_credits, stringResource(R.string.you_credits), creditsSubtitle, activePrompt == YouPrompt.Credits) { onOpenCreditsSheet() }"""))
        assertTrue(!androidYou.contains("""PromptRow(R.drawable.you_icon_credits, "Credits", creditsMenuSubtitle(state), activePrompt == YouPrompt.Credits) { onOpenPage(YouPage.Credits) }"""))
        assertTrue(androidYou.contains("""PromptRow(R.drawable.you_icon_support, stringResource(R.string.you_support_feedback), stringResource(R.string.you_email_support)"""))
        assertTrue(androidYou.contains("""PromptRow(R.drawable.you_icon_privacy, stringResource(R.string.you_privacy_policy), stringResource(R.string.you_privacy_subtitle)"""))
        assertTrue(androidYou.contains("""PromptRow(R.drawable.you_icon_terms, stringResource(R.string.you_terms_conditions), stringResource(R.string.you_terms_subtitle)"""))
        assertTrue(androidYou.contains("""PromptRow(R.drawable.you_icon_anky_token, "\${'$'}ANKY", if (didCopyAnkyContract) stringResource(R.string.you_copied_to_clipboard) else ankyContractDisplayAddress()"""))
        listOf(
            "you_title",
            "you_data",
            "you_credits",
            "you_support_feedback",
            "you_privacy_policy",
            "you_terms_conditions",
            "you_encrypted_backup_on",
            "you_export_writings_or_enable_backup",
            "privacy_page_heading",
            "privacy_contact_caption",
            "terms_reflection_agreement",
            "credit_rule_one_reflection",
            "credit_rule_ask_spends",
            "credit_rule_writing_free",
            "loading_credit_packs",
            "no_credit_packs_available",
            "credits_sheet_prompt_copy_fallback",
            "refresh_reflection_credits",
            "refresh_credits",
            "restoring_purchases",
            "restore_purchases",
            "support_feedback_lower",
            "support_feedback_note",
        ).forEach { key ->
            assertTrue(androidStrings.contains("""name="$key""""))
            assertTrue(androidYou.contains("R.string.$key"))
        }
        listOf("values-es", "values-fr", "values-de", "values-hi", "values-zh-rCN").forEach { localeDir ->
            val localizedStrings = repoRoot()
                .resolve("apps/android/app/src/main/res/$localeDir/strings.xml")
                .readText()
            assertTrue(localizedStrings.contains("you_title"))
            assertTrue(localizedStrings.contains("you_privacy_policy"))
            assertTrue(localizedStrings.contains("you_terms_conditions"))
            assertTrue(localizedStrings.contains("privacy_page_heading"))
            assertTrue(localizedStrings.contains("terms_reflection_agreement"))
            assertTrue(localizedStrings.contains("credit_rule_one_reflection"))
            assertTrue(localizedStrings.contains("refresh_credits"))
            assertTrue(localizedStrings.contains("support_feedback_note"))
        }
        assertTrue(androidYou.contains("painterResource(R.drawable.you_ankycoin)"))
        assertTrue(androidYou.contains("stringResource(R.string.credits_sheet_prompt_copy_fallback)"))
        assertTrue(androidYou.contains("Icons.Filled.Refresh"))
        assertTrue(androidYou.contains(".size(46.dp)"))
        assertTrue(androidYou.contains(".border(1.2.dp, AnkyColors.Gold.copy(alpha = 0.42f), CircleShape)"))
        assertTrue(androidYou.contains("contentDescription = stringResource(R.string.refresh_reflection_credits)"))
        assertTrue(!androidYou.contains("Text(stringResource(R.string.refresh_credits), style = AnkyType.Mono.copy(fontSize = 12.sp, color = AnkyColors.Gold))"))
        assertTrue(androidTokenIcon.contains("""android:viewportWidth="24""""))
        assertTrue(androidTokenIcon.contains("#D7BA73"))
        assertTrue(androidYou.contains("YouPage.Terms -> TermsPage()"))
        assertTrue(androidYou.contains("private val TermsCopy = listOf("))
        assertTrue(!androidYou.contains("""PromptRow(R.drawable.you_icon_credits, "support / feedback""""))
        listOf(
            """Text("privacy is the shape of anky, not a feature added later."""",
            """Text("questions, deletion requests, and privacy reports"""",
            """Text("Terms & Conditions"""",
            """Text("Writing and reflection agreement"""",
            """Rule("1 credit = reflection")""",
            """Rule("ask anky spends one credit")""",
            """Rule("writing is always free")""",
            """DisabledRow("loading credit packs")""",
            """DisabledRow("no credit packs available")""",
            """AnkyActionButton("refresh credits"""",
            """"restoring purchases" else "restore purchases"""",
            """AnkyActionButton("support / feedback"""",
            """Text("email support@anky.app. include only what you choose to write."""",
        ).forEach { literal ->
            assertTrue(!androidYou.contains(literal))
        }
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

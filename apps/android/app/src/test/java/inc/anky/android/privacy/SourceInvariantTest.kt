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

        assertTrue(androidReveal.contains("copy writing"))
        assertTrue(androidReveal.contains("copy reflection"))
        assertTrue(androidRevealViewModel.contains("enum class RevealCopySection"))
        assertTrue(androidRevealViewModel.contains("fun textForCopy(section: RevealCopySection)"))
        assertTrue(!androidReveal.contains("""copyText("Anky mirror""""))
    }

    @Test
    fun hiddenWritingInputRejectsMultiGlyphMutations() {
        val hiddenInput = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/feature/write/HiddenTextInput.kt")
            .readText()

        assertTrue(hiddenInput.contains("next.isSingleProtocolGlyph() -> onGlyph(next)"))
        assertTrue(hiddenInput.contains("else -> onRejectedMutation()"))
        assertTrue(!hiddenInput.contains("protocolGlyphsOrNull"))
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
        assertTrue(buildScript.contains("""applicationIdSuffix = ".debug""""))
        assertTrue(buildScript.contains("""println("releaseApplicationId=app.anky.mobile")"""))
        assertTrue(buildScript.contains("""println("debugApplicationId=app.anky.mobile.debug")"""))
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
    fun youExportPromptMatchesCurrentIosPreparedBackupActions() {
        val androidYou = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/feature/you/YouScreen.kt")
            .readText()
        val iosYou = repoRoot()
            .resolve("apps/ios/Anky/Features/You/YouView.swift")
            .readText()

        assertTrue(iosYou.contains("""AnkyChatAction("restore backup")"""))
        assertTrue(iosYou.contains("""AnkyChatAction("export backup", isPrimary: true)"""))
        assertTrue(iosYou.contains("if let backupZipURL = viewModel.backupZipURL"))
        assertTrue(!iosYou.contains("""AnkyChatAction("prepare backup""""))

        assertTrue(androidYou.contains("""AnkyChatAction("restore backup")"""))
        assertTrue(androidYou.contains("""AnkyChatAction("export backup", isPrimary = true)"""))
        assertTrue(androidYou.contains("state.exportedFile?.let"))
        assertTrue(!androidYou.contains("""AnkyChatAction("prepare backup""""))
    }

    @Test
    fun ankyChatActionSupportsIosSubtitleBadgeAndPackageActions() {
        val androidPrompt = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/ui/components/AnkyCompanionPrompt.kt")
            .readText()
        val androidYou = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/feature/you/YouScreen.kt")
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
        assertTrue(iosYou.contains("subtitle: creditPackage.price"))
        assertTrue(iosYou.contains("""badge: isRecommended ? "recommended" : nil"""))

        assertTrue(androidPrompt.contains("val subtitle: String? = null"))
        assertTrue(androidPrompt.contains("val badge: String? = null"))
        assertTrue(androidPrompt.contains("actions.take(4)"))
        assertTrue(androidYou.contains("subtitle = creditPackage.price"))
        assertTrue(androidYou.contains("""badge = if (isRecommended) "recommended" else null"""))
    }

    @Test
    fun postWriteReflectionPromptExposesIosNotNowAction() {
        val androidApp = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/app/AnkyApp.kt")
            .readText()
        val androidWrite = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/feature/write/WriteScreen.kt")
            .readText()
        val iosApp = repoRoot()
            .resolve("apps/ios/Anky/AppRoot.swift")
            .readText()
        val iosWriteModel = repoRoot()
            .resolve("apps/ios/Anky/Features/Write/WriteViewModel.swift")
            .readText()

        assertTrue(iosApp.contains("youViewModel.preloadCredits()"))
        assertTrue(iosWriteModel.contains("func importAnkyArtifact(_ text: String) -> Bool"))
        assertTrue(iosWriteModel.contains("completion?(saved)"))
        assertTrue(androidApp.contains("suspend fun refreshRootCreditBalance()"))
        assertTrue(androidApp.contains("rootCreditBalance.value = container.creditsClient.refresh().balance"))
        assertTrue(androidApp.contains("val importedCompletedHash = remember { mutableStateOf<String?>(null) }"))
        assertTrue(androidApp.contains("val postWriteCompletedHash = importedCompletedHash.value ?: writeState.completedHash"))
        assertTrue(androidApp.contains("LaunchedEffect(postWriteCompletedHash, lockState.value)"))
        assertTrue(androidApp.contains("postWriteCompletedHash != null"))
        assertTrue(androidApp.contains("refreshRootCreditBalance()"))
        assertTrue(androidApp.contains("onImported = { hash ->"))
        assertTrue(androidWrite.contains("onImported: (String) -> Unit"))
        assertTrue(androidWrite.contains("onImported(saved.hash)"))
        assertTrue(androidWrite.contains("fun importAndOfferReflection"))
        assertTrue(androidApp.contains("val postWriteCreditBadge = rootCreditBalance.value?.let(::creditBadge)"))
        assertTrue(androidApp.contains("""AnkyChatAction("reflect (1 credit)", badge = postWriteCreditBadge, isPrimary = true)"""))
        assertTrue(androidApp.contains("badge = postWriteCreditBadge"))
        assertTrue(androidApp.contains("""AnkyChatAction("not now")"""))
        assertTrue(androidApp.contains("val hash = postWriteCompletedHash ?: return@AnkyChatAction"))
        assertTrue(androidApp.contains("navController.navigate(AnkyRoute.Map.route)"))
        assertTrue(androidApp.contains("navController.navigate(AnkyRoute.Reveal.route(hash))"))
        assertTrue(!androidApp.contains("onReveal = { hash ->"))
        assertTrue(!androidWrite.contains("fun importAndReveal"))
    }

    @Test
    fun writeLaunchPromptIncludesIosRitualSteps() {
        val androidApp = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/app/AnkyApp.kt")
            .readText()
        val androidPrompt = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/ui/components/AnkyCompanionPrompt.kt")
            .readText()
        val iosApp = repoRoot()
            .resolve("apps/ios/Anky/AppRoot.swift")
            .readText()

        listOf("write one character", "keep the thread alive", "let silence close it").forEach { step ->
            assertTrue(iosApp.contains("""AnkyBubbleStep("$step")"""))
            assertTrue(androidApp.contains(""""$step""""))
        }
        assertTrue(iosApp.contains("the living .anky string is the state of this session."))
        assertTrue(androidApp.contains("the living .anky string is the state of this session."))
        assertTrue(androidPrompt.contains("steps: List<String> = emptyList()"))
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

        assertTrue(iosWrite.contains("accessibilityLabel(\"Writing time \\(AnkyDuration.clock(viewModel.elapsedMs))\")"))
        assertTrue(androidWrite.contains("val clockText = AnkyDuration.clock(state.elapsedMs)"))
        assertTrue(androidWrite.contains("contentDescription = \"Writing time ${'$'}clockText\""))
    }

    @Test
    fun writePasteHasIosHiddenDevFixtureHold() {
        val androidWrite = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/feature/write/WriteScreen.kt")
            .readText()
        val androidWriteModel = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/feature/write/WriteViewModel.kt")
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

        assertTrue(iosWrite.contains("WriteToolbarPasteButton("))
        assertTrue(iosWrite.contains("LongPressGesture(minimumDuration: 5)"))
        assertTrue(iosWrite.contains("Hold for five seconds to paste the built-in dev .anky"))
        assertTrue(iosWriteModel.contains("var devSampleAnkyArtifact: String"))

        assertTrue(androidWrite.contains("DevPasteChromeButton("))
        assertTrue(androidWrite.contains("private const val WriteDevPasteHoldMs = 5_000L"))
        assertTrue(androidWrite.contains("withTimeoutOrNull(WriteDevPasteHoldMs)"))
        assertTrue(androidWrite.contains("Hold for five seconds to paste the built-in dev .anky"))
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
        val iosApp = repoRoot()
            .resolve("apps/ios/Anky/AppRoot.swift")
            .readText()
        val iosReveal = repoRoot()
            .resolve("apps/ios/Anky/Features/Reveal/RevealView.swift")
            .readText()

        assertTrue(iosApp.contains("private func beginRetryWriting()"))
        assertTrue(iosApp.contains("writeViewModel.clearCompletedSession()"))
        assertTrue(iosApp.contains("writeViewModel.openWritingPortal()"))
        assertTrue(iosReveal.contains("WRITE \\(AnkyDuration.completeRitualMinutes) MINUTES"))
        assertTrue(iosReveal.contains("onTryAgain()"))

        assertTrue(androidApp.contains("fun beginRetryWriting()"))
        assertTrue(androidApp.contains("writeViewModelWithCurrentMirror.consumeCompletedHash()"))
        assertTrue(androidApp.contains("writeViewModelWithCurrentMirror.openWritingPortal()"))
        assertTrue(androidApp.contains("onTryAgain = { beginRetryWriting() }"))
        assertTrue(androidReveal.contains("WRITE ${'$'}{AnkyDuration.CompleteRitualMinutes} MINUTES"))
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
        assertTrue(androidMap.contains("val selectedDayEpoch = remember"))
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

        assertTrue(iosReveal.contains("accessibilityLabel(\"Delete writing session\")"))
        assertTrue(iosReveal.contains("Color.red.opacity(0.88)"))
        assertTrue(iosReveal.contains("Color.red.opacity(0.22)"))

        assertTrue(androidReveal.contains("contentDescription = \"Delete writing session\""))
        assertTrue(androidReveal.contains("AnkyColors.Danger.copy(alpha = 0.88f)"))
        assertTrue(androidReveal.contains("AnkyColors.Danger.copy(alpha = 0.22f)"))
        assertTrue(androidReveal.contains("Delete forever?"))
        assertTrue(androidReveal.contains("This permanently deletes this writing session. This cannot be undone."))
        assertTrue(!androidReveal.contains("contentDescription = \"delete forever\""))
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
        assertTrue(iosMap.contains("private var metadataText: String"))
        assertTrue(iosMap.contains("AnkyDuration.formatted(session.durationMs)"))
        assertTrue(iosMap.contains("""items.append("reflected")"""))
        assertTrue(iosMap.contains(".overlay(alignment: .bottom)"))
        assertTrue(iosMap.contains(".frame(height: 1.5)"))

        assertTrue(androidMap.contains(".semantics(mergeDescendants = true)"))
        assertTrue(androidMap.contains("contentDescription = sessionAccessibilityLabel(session)"))
        assertTrue(androidMap.contains("internal fun sessionAccessibilityLabel"))
        assertTrue(androidMap.contains("AnkyDuration.formatted(session.durationMs)"))
        assertTrue(androidMap.contains("""if (session.hasReflection) add("reflected")"""))
        assertTrue(androidMap.contains(".align(Alignment.BottomStart)"))
        assertTrue(androidMap.contains(".height(1.5.dp)"))
        assertTrue(iosMap.contains(".padding(.horizontal, 26)"))
        assertTrue(androidMap.contains(".padding(horizontal = 26.dp)"))
        assertTrue(iosMap.contains(".padding(.top, 24)"))
        assertTrue(androidMap.contains(".padding(top = 24.dp, bottom = 72.dp)"))
        assertTrue(iosMap.contains(".padding(.bottom, 72)"))
        assertTrue(!androidMap.contains(".padding(horizontal = 26.dp, vertical = 24.dp)"))
        assertTrue(iosMap.contains("Text(\"no writing saved\")"))
        assertTrue(iosMap.contains(".font(.custom(\"Georgia\", size: 20))"))
        assertTrue(androidMap.contains("Text(\"no writing saved\", style = AnkyType.Body.copy(fontSize = 20.sp, color = AnkyColors.PaperMuted)"))
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

        assertTrue(androidMap.contains("AnkyColors.Ink.copy(alpha = 0.96f)"))
        assertTrue(androidMap.contains("style = AnkyType.Body.copy(\n                        fontSize = 17.sp,\n                        fontWeight = FontWeight.SemiBold,\n                        color = AnkyColors.Paper"))
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

        assertTrue(androidMap.contains("contentDescription = dayAccessibilityLabel(day)"))
        assertTrue(androidMap.contains("internal fun dayAccessibilityLabel"))
        assertTrue(androidMap.contains("\"Today\""))
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

        assertTrue(iosMap.contains(".accessibilityLabel(\"UTC day progress\")"))
        assertTrue(iosMap.contains(".accessibilityLabel(\"showed up\")"))

        assertTrue(androidMap.contains("contentDescription = \"UTC day progress\""))
        assertTrue(androidMap.contains("contentDescription = \"showed up\""))
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

        assertTrue(androidMap.contains("TrailDayNode(\n                    day = day,\n                    index = index,\n                    dayCount = displayDays.size"))
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
        assertTrue(iosMap.contains(".accessibilityLabel(\"Go to current day\")"))

        assertTrue(androidMap.contains(".size(48.dp)\n                    .clip(CircleShape)"))
        assertTrue(androidMap.contains(".background(Color.White.copy(alpha = 0.12f))"))
        assertTrue(androidMap.contains("contentDescription = \"Go to current day\""))
        assertTrue(androidMap.contains("contentDescription = null"))
        assertTrue(!androidMap.contains(".background(Color.Black.copy(alpha = 0.28f))"))
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

        assertTrue(iosTags.contains(".onAppear {"))
        assertTrue(iosTags.contains("sessions = sessionIndexStore.sessionsWithTag(tag)"))
        assertTrue(iosTags.contains("RevealBackgroundTexture()"))
        assertTrue(iosTags.contains("Text(tag)"))
        assertTrue(androidTags.contains("fun refreshSessions()"))
        assertTrue(androidTags.contains("sessionIndexStore.sessionsWithTag(tag)"))
        assertTrue(androidTags.contains("RevealTagTexture()"))
        assertTrue(androidTags.contains("AnkyColors.Violet.copy(alpha = alpha)"))
        assertTrue(androidTags.contains("Triple(1.34f, 360.dp.toPx(), 0.018f)"))
        assertTrue(androidTags.contains("Triple(1.20f, bloomHeight, 0.030f)"))
        assertTrue(androidTags.contains("Triple(1.06f, 220.dp.toPx(), 0.024f)"))
        assertTrue(androidTags.contains("Text(\n                        tag,"))
        assertTrue(iosTags.contains(".font(.custom(\"Georgia\", size: 30).weight(.bold))"))
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

        assertTrue(iosWriteModel.contains("i couldn't find a readable .anky in that."))
        assertTrue(iosWriteModel.contains("i couldn't open that .anky yet."))
        assertTrue(androidWrite.contains("i couldn't find a readable .anky in that."))
        assertTrue(androidWrite.contains("i couldn't open that .anky yet."))
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

        listOf("copy writing", "copy reflection", "READ REFLECTION", "REFLECT THIS ANKY").forEach { copy ->
            assertTrue(androidReveal.contains(copy))
        }
        assertTrue(!androidReveal.contains("i have reflected this anky."))
        assertTrue(!androidReveal.contains("i am holding the mirror open."))
        assertTrue(androidReveal.contains("StreamingReflectionPanel("))
        assertTrue(androidReveal.contains("SavedReflectionPanel("))
        assertTrue(!androidReveal.contains("hide live text"))
        assertTrue(androidReveal.contains("state.canSubmitReflectionRequest"))
        assertTrue(androidReveal.contains("viewModel.askAnky()"))
        assertTrue(!androidReveal.contains("the reflection is not here yet."))
        assertTrue(androidReveal.contains("\"writing reflection · ${'$'}generatedCharacters characters\""))
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
        assertTrue(androidReveal.contains("the mirror is forming"))
        assertTrue(androidReveal.contains("inlineReflectionActive"))
        assertTrue(androidReveal.contains("ModalBottomSheet("))
        assertTrue(androidReveal.contains("RevealCreditPurchaseSheet("))
        assertTrue(androidReveal.contains("\"GET MORE CREDITS\""))
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
    }

    @Test
    fun companionTapMessagesMatchCurrentIosTabs() {
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

        listOf(
            "you are here. this is the writing surface: one living thread, one character at a time.",
            "you are here. deletion is blocked on purpose; keep moving forward without editing.",
            "you are here. the map is your local trail; every day exists even when it is quiet.",
            "you are here. tap a day to reopen its .ankys and saved reflections.",
            "you are here. this page is for identity, privacy, exports, and reflection credits.",
            "you are here. credits buy reflections; writing itself stays free.",
        ).forEach { message ->
            assertTrue(androidApp.contains(message))
        }
        assertTrue(androidApp.contains("fun showCompanionNote(): Boolean"))
        assertTrue(androidApp.contains("writeViewModelWithCurrentMirror.replayRecentPromptIfAvailable()"))
        assertTrue(iosPresence.contains("DragGesture(minimumDistance: 3)"))
        assertTrue(androidPresence.contains("detectDragGestures("))
        assertTrue(androidPresence.contains("onDragStart = {"))
        assertTrue(androidPresence.contains("followsHomePosition = false"))
        assertTrue(androidPresence.contains("""testTag("anky-presence")"""))
        listOf("Keep Anky here", "Hide Anky", "Show Anky", "Change motion", "Cancel").forEach { menuCopy ->
            assertTrue(androidPresence.contains(menuCopy))
        }
        assertTrue(androidPresence.contains("anky stays beside the writing"))
        assertTrue(!androidPresence.contains("drag anky anywhere"))
        assertTrue(!androidPresence.contains("Move Anky home"))
    }

    @Test
    fun appLockRecoveryPhraseFallbackMatchesCurrentIos() {
        val androidApp = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/app/AnkyApp.kt")
            .readText()
        val iosApp = repoRoot()
            .resolve("apps/ios/Anky/AppRoot.swift")
            .readText()

        assertTrue(iosApp.contains("allowsRecoveryPhrase: failedAuthAttempts >= 2"))
        assertTrue(iosApp.contains("recoverIdentity(_ phraseText: String)"))
        assertTrue(iosApp.contains("importRecoveryPhrase(phraseText)"))

        assertTrue(androidApp.contains("failedAuthAttempts.intValue >= 2"))
        assertTrue(androidApp.contains("fun recoverIdentityFromPhrase()"))
        assertTrue(androidApp.contains("container.identityStore.importRecoveryPhrase(normalized)"))
        assertTrue(androidApp.contains("identityRecoveryNonce.intValue += 1"))
        assertTrue(androidApp.contains("remember(identityVersion)"))
        assertTrue(androidApp.contains("""Text("recovery phrase""""))
        assertTrue(androidApp.contains("""Text("recover identity")"""))
    }

    @Test
    fun youPrivacyAndSupportPromptActionsMatchCurrentIos() {
        val androidYou = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/feature/you/YouScreen.kt")
            .readText()
        val androidModel = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/feature/you/YouViewModel.kt")
            .readText()
        val iosYou = repoRoot()
            .resolve("apps/ios/Anky/Features/You/YouView.swift")
            .readText()
        val iosModel = repoRoot()
            .resolve("apps/ios/Anky/Features/You/YouViewModel.swift")
            .readText()

        assertTrue(iosYou.contains("""AnkyChatAction("read privacy policy", isPrimary: true)"""))
        assertTrue(iosYou.contains("""AnkyChatAction("open email", isPrimary: true)"""))
        assertTrue(iosYou.contains("send support or feedback by email. include only what you choose to write."))
        assertTrue(iosModel.contains("supportFeedbackEmailURL"))

        assertTrue(androidYou.contains("""AnkyChatAction("read privacy policy", isPrimary = true)"""))
        assertTrue(androidYou.contains("""AnkyChatAction("open email", isPrimary = true)"""))
        assertTrue(androidYou.contains("send support or feedback by email. include only what you choose to write."))
        assertTrue(androidYou.contains("support / feedback"))
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
        val iosYou = repoRoot()
            .resolve("apps/ios/Anky/Features/You/YouView.swift")
            .readText()
        val iosModel = repoRoot()
            .resolve("apps/ios/Anky/Features/You/YouViewModel.swift")
            .readText()

        listOf(
            "anky created a Base account for this device.",
            "this phrase controls your Anky Base account. never share it. anky cannot recover it for you.",
            "Your password/biometrics protect local access. They are not an Anky login.",
            "reveal recovery phrase",
            "copy recovery phrase",
            "Back up Anky identity",
        ).forEach { copy ->
            assertTrue(iosYou.contains(copy))
            assertTrue(androidYou.contains(copy))
        }
        assertTrue(iosYou.contains("""AnkyChatAction("back up identity", isPrimary: true)"""))
        assertTrue(androidYou.contains("""AnkyChatAction("back up identity", isPrimary = true)"""))
        assertTrue(iosYou.contains("viewModel.backUpIdentityToICloudKeychain()"))
        assertTrue(androidYou.contains("viewModel.backUpIdentityToDeviceSecureStorage()"))
        assertTrue(iosModel.contains("func backUpIdentityToICloudKeychain() async"))
        assertTrue(androidModel.contains("fun backUpIdentityToDeviceSecureStorage()"))
        assertTrue(androidModel.contains("identityStore.backUpRecoveryPhraseToDeviceSecureStorage()"))
        assertTrue(!androidYou.contains("""AnkyChatAction("back up identity", isPrimary = true) { viewModel.revealRecoveryPhrase() }"""))
        assertTrue(iosModel.contains("Show your ANKY recovery phrase."))
        assertTrue(androidModel.contains("Show your ANKY recovery phrase."))
        assertTrue(iosModel.contains("Could not load the recovery phrase."))
        assertTrue(androidModel.contains("Could not load the recovery phrase."))
        assertTrue(iosModel.contains("Could not load the local Base identity."))
        assertTrue(androidModel.contains("Could not load the local Base identity."))
        assertTrue(iosModel.contains("Recovery phrase must be 12 words."))
        assertTrue(androidModel.contains("Recovery phrase must be 12 words."))
        assertTrue(iosModel.contains("Recovery phrase contains an unrecognized word."))
        assertTrue(androidModel.contains("Recovery phrase contains an unrecognized word."))
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
        val iosYou = repoRoot()
            .resolve("apps/ios/Anky/Features/You/YouView.swift")
            .readText()
        val resetWarning = "Resetting identity creates a new Anky Base account. Credits are tied to your current account. Save your recovery phrase before resetting."

        assertTrue(iosYou.contains(".confirmationDialog(\"reset local identity?\""))
        assertTrue(iosYou.contains("Button(\"reset identity\", role: .destructive)"))
        assertTrue(iosYou.contains(resetWarning))

        assertTrue(androidYou.contains("title = \"reset local identity?\""))
        assertTrue(androidYou.contains("action = \"reset identity\""))
        assertTrue(androidYou.contains("message = \"$resetWarning\""))
        assertTrue(androidYou.contains("text = message?.let"))
    }

    @Test
    fun youConversationPromptStartsHiddenLikeCurrentIos() {
        val androidYou = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/feature/you/YouScreen.kt")
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
    fun youTitleOpensAnkyExperienceLikeIos() {
        val androidApp = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/app/AnkyApp.kt")
            .readText()
        val androidYou = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/feature/you/YouScreen.kt")
            .readText()
        val iosYou = repoRoot()
            .resolve("apps/ios/Anky/Features/You/YouView.swift")
            .readText()

        assertTrue(androidYou.contains("val isShowingAnkyExperience = remember { mutableStateOf(false) }"))
        assertTrue(androidYou.contains("onExperienceVisibilityChanged: (Boolean) -> Unit = {}"))
        assertTrue(androidYou.contains("onExperienceVisibilityChanged(isShowingAnkyExperience.value)"))
        assertTrue(androidYou.contains("onOpenExperience = { isShowingAnkyExperience.value = true }"))
        assertTrue(androidYou.contains("AnkyExperienceOverlay("))
        assertTrue(androidYou.contains("AnkyExperienceSystemBarsHidden()"))
        assertTrue(androidYou.contains("WindowCompat.setDecorFitsSystemWindows(window, false)"))
        assertTrue(androidYou.contains("controller.hide(WindowInsetsCompat.Type.systemBars())"))
        assertTrue(androidYou.contains("private const val AnkyExperienceTotalSeconds = 88 * 60"))
        assertTrue(androidYou.contains("HiddenTextInput("))
        assertTrue(androidYou.contains("AnkyWriter()"))
        assertTrue(androidYou.contains("writer.value.closeWithTerminalSilence()"))
        assertTrue(androidYou.contains("copy your .anky or copy your writing."))
        assertTrue(androidYou.contains("AnkyChatAction(\"copy your .anky\", isPrimary = true)"))
        assertTrue(androidYou.contains("AnkyChatAction(\"copy your writing\")"))
        assertTrue(androidYou.contains("contentDescription = \"Anky experience time ${'$'}elapsedClock\""))
        assertTrue(androidYou.contains("contentDescription = \"Close The Anky Experience\""))
        assertTrue(androidYou.contains("contentDescription = \"Anky companion\""))

        assertTrue(androidApp.contains("val isShowingYouExperience = remember { mutableStateOf(false) }"))
        assertTrue(androidApp.contains("onExperienceVisibilityChanged = { isShowingYouExperience.value = it }"))
        assertTrue(androidApp.contains("!isShowingYouExperience.value"))
        assertTrue(androidApp.contains("if (!isShowingYouExperience.value)"))
    }

    @Test
    fun youDeveloperToolsRemainDebugOnly() {
        val youScreen = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/feature/you/YouScreen.kt")
            .readText()

        assertTrue(youScreen.contains("YouPage.Developer -> if (BuildConfig.DEBUG)"))
        assertTrue(
            Regex("""if \(BuildConfig\.DEBUG\) \{[\s\S]*PromptRow\(R\.drawable\.you_icon_settings, "developer", "local repair tools"""")
                .containsMatchIn(youScreen),
        )
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
        val androidDrawables: Set<String> = Files.walk(repoRoot().resolve("apps/android/app/src/main/res/drawable-nodpi").toPath()).use { paths ->
            paths
                .filter { Files.isRegularFile(it) }
                .map { path: Path -> path.toFile().nameWithoutExtension }
                .toList()
                .toSet()
        }
        val missing = iosImageSetDirectories().mapNotNull { imageSet ->
            val candidates = imageSet.listFiles()
                .orEmpty()
                .filter { it.isFile && it.extension.equals("png", ignoreCase = true) }
                .map { imageFile -> imageFile.nameWithoutExtension.replace(Regex("""@\d+x$"""), "") }
                .map { assetName -> assetName.lowercase().replace("-", "_") }
                .toSet()

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

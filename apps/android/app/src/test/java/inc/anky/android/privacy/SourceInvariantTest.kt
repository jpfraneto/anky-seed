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
    fun revealCopySurfaceMatchesCurrentIosWritingTapOnly() {
        val androidReveal = repoRoot()
            .resolve("apps/android/app/src/main/java/inc/anky/android/feature/reveal/RevealScreen.kt")
            .readText()
        val iosReveal = repoRoot()
            .resolve("apps/ios/Anky/Features/Reveal/RevealView.swift")
            .readText()

        assertTrue(iosReveal.contains("copyWriting(at: location)"))
        assertTrue(iosReveal.contains("private func copyReflection()"))
        assertTrue(!iosReveal.substringBefore("private func copyReflection()").contains("copyReflection()"))
        assertTrue(androidReveal.contains("""copyText("Anky writing", artifact.reconstructedText)"""))
        assertTrue(!androidReveal.contains("""copyText("Anky mirror""""))
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
                .filter { path -> forbiddenNames.matches(File(path).name) }
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

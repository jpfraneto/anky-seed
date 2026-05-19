import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

val localProperties = Properties().apply {
    val file = rootProject.file("local.properties")
    if (file.isFile) file.inputStream().use(::load)
}

fun releaseProperty(name: String): String? =
    localProperties.getProperty(name)
        ?: providers.environmentVariable(name).orNull

fun buildConfigString(value: String): String =
    "\"" + value.replace("\\", "\\\\").replace("\"", "\\\"") + "\""

fun releaseFileProperty(name: String) =
    releaseProperty(name)?.let { path ->
        val candidate = file(path)
        if (candidate.isAbsolute) candidate else rootProject.file(path)
    }

val releaseKeystoreFile = releaseFileProperty("ANKY_ANDROID_KEYSTORE_FILE")
val releaseStorePassword = releaseProperty("ANKY_ANDROID_KEYSTORE_PASSWORD")
val releaseKeyAlias = releaseProperty("ANKY_ANDROID_KEY_ALIAS")
val releaseKeyPassword = releaseProperty("ANKY_ANDROID_KEY_PASSWORD")
val hasReleaseSigning =
    releaseKeystoreFile?.isFile == true &&
        !releaseStorePassword.isNullOrBlank() &&
        !releaseKeyAlias.isNullOrBlank() &&
        !releaseKeyPassword.isNullOrBlank()

android {
    namespace = "inc.anky.android"
    compileSdk = 35

    buildFeatures {
        buildConfig = true
        compose = true
    }

    defaultConfig {
        applicationId = "app.anky.mobile"
        minSdk = 26
        targetSdk = 35
        versionCode = releaseProperty("ANKY_ANDROID_VERSION_CODE")?.toIntOrNull() ?: 1
        versionName = releaseProperty("ANKY_ANDROID_VERSION_NAME") ?: "0.1.0"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        vectorDrawables.useSupportLibrary = true
        buildConfigField("String", "DEFAULT_MIRROR_BASE_URL", "\"https://mirror-production-a23c.up.railway.app\"")
        buildConfigField(
            "String",
            "REVENUECAT_ANDROID_PUBLIC_KEY",
            buildConfigString(releaseProperty("ANKY_REVENUECAT_ANDROID_PUBLIC_KEY").orEmpty()),
        )
    }

    signingConfigs {
        create("release") {
            if (hasReleaseSigning) {
                storeFile = checkNotNull(releaseKeystoreFile)
                storePassword = checkNotNull(releaseStorePassword)
                keyAlias = checkNotNull(releaseKeyAlias)
                keyPassword = checkNotNull(releaseKeyPassword)
                enableV1Signing = false
                enableV2Signing = true
                enableV3Signing = true
                enableV4Signing = true
            }
        }
    }

    buildTypes {
        debug {
            applicationIdSuffix = releaseProperty("ANKY_ANDROID_DEBUG_APPLICATION_ID_SUFFIX") ?: ""
            versionNameSuffix = "-debug"
        }
        release {
            isMinifyEnabled = false
            if (hasReleaseSigning) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

tasks.register("printReleaseSigningStatus") {
    group = "anky"
    description = "Prints whether release signing inputs are configured without exposing secrets."
    doLast {
        println("releaseApplicationId=app.anky.mobile")
        println("debugApplicationId=app.anky.mobile.debug")
        println("releaseSigningConfigured=$hasReleaseSigning")
        println("versionCode=${android.defaultConfig.versionCode}")
        println("versionName=${android.defaultConfig.versionName}")
    }
}

tasks.matching { it.name == "bundleRelease" || it.name == "signReleaseBundle" }.configureEach {
    doFirst {
        if (!hasReleaseSigning) {
            throw GradleException(
                "Release signing is not configured. Set ANKY_ANDROID_KEYSTORE_FILE, " +
                    "ANKY_ANDROID_KEYSTORE_PASSWORD, ANKY_ANDROID_KEY_ALIAS, and " +
                    "ANKY_ANDROID_KEY_PASSWORD in apps/android/local.properties or the environment.",
            )
        }
    }
}

kotlin {
    jvmToolchain(17)
}

dependencies {
    val composeBom = platform("androidx.compose:compose-bom:2024.12.01")
    implementation(composeBom)
    androidTestImplementation(composeBom)

    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("androidx.biometric:biometric:1.1.0")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.datastore:datastore-preferences:1.1.1")
    implementation("androidx.fragment:fragment-ktx:1.8.5")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.8.7")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.7")
    implementation("androidx.navigation:navigation-compose:2.8.5")
    implementation("com.revenuecat.purchases:purchases:9.23.1")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("org.bouncycastle:bcprov-jdk18on:1.78.1")
    implementation("org.json:json:20240303")

    debugImplementation("androidx.compose.ui:ui-tooling")
    debugImplementation("androidx.compose.ui:ui-test-manifest")

    testImplementation("junit:junit:4.13.2")
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.9.0")
    testImplementation("com.squareup.okhttp3:mockwebserver:4.12.0")

    androidTestImplementation("androidx.test.ext:junit:1.2.1")
    androidTestImplementation("androidx.test.espresso:espresso-core:3.6.1")
    androidTestImplementation("androidx.compose.ui:ui-test-junit4")
}

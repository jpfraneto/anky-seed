package inc.anky.android.ui.lazure

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.staticCompositionLocalOf

/**
 * The lazure role tokens in scope. Defaults to the standard remap so the
 * tokens are readable even outside [LazureTheme]; [LazureTheme] provides
 * the same instance explicitly (a [LevelTheme]-tinted variant can be
 * provided later without touching call sites).
 */
val LocalLazureRoles = staticCompositionLocalOf { LazureRoles() }

/**
 * The lazure world as a `MaterialTheme` wrapper — purely additive; the
 * existing dark-cosmic `AnkyTheme` stays untouched until screens are
 * rethemed one by one.
 *
 * Provides:
 *  - a Material3 light color scheme resolved to the pigments (paper
 *    surfaces, violet ink text, gold primary, madder error — no pure
 *    white or black anywhere);
 *  - Material typography remapped to the lazure letterforms (serif for
 *    what is said, sans for chrome);
 *  - [LocalLazureRoles] for the iOS `AnkyTheme` token remap;
 *  - [LocalBreathClock], one shared 8-second breath every lazure
 *    component under this theme synchronizes to (one frame loop per
 *    screen instead of one per breathing view).
 */
@Composable
fun LazureTheme(
    roles: LazureRoles = LazureRoles(),
    content: @Composable () -> Unit,
) {
    val breathClock = rememberStandaloneBreathClock()
    CompositionLocalProvider(
        LocalLazureRoles provides roles,
        LocalBreathClock provides breathClock,
    ) {
        MaterialTheme(
            colorScheme = LazureColorScheme,
            typography = LazureMaterialTypography,
            content = content,
        )
    }
}

private val LazureColorScheme = lightColorScheme(
    primary = LazurePigments.ankyGold,
    onPrimary = LazurePigments.ankyInk,
    secondary = LazurePigments.ankyViolet,
    onSecondary = LazurePigments.ankyPaper,
    tertiary = LazurePigments.ankySlate,
    onTertiary = LazurePigments.ankyPaper,
    background = LazurePigments.ankyPaper,
    onBackground = LazurePigments.ankyInk,
    surface = LazurePigments.ankyPaper,
    onSurface = LazurePigments.ankyInk,
    surfaceVariant = LazurePigments.ankyPaperDeep,
    onSurfaceVariant = LazurePigments.ankyInkSoft,
    outline = LazurePigments.ankyInk.copy(alpha = 0.10f),
    outlineVariant = LazurePigments.ankyInk.copy(alpha = 0.08f),
    error = LazurePigments.ankyMadder,
    onError = LazurePigments.ankyPaper,
)

private val LazureMaterialTypography = Typography(
    displayLarge = LazureType.ankyTitle,
    displayMedium = LazureType.ankyTitle,
    displaySmall = LazureType.ankyTitle,
    headlineLarge = LazureType.ankyTitle,
    headlineMedium = LazureType.ankyHeading,
    headlineSmall = LazureType.ankyHeading,
    titleLarge = LazureType.ankyHeading,
    titleMedium = LazureType.ankyHeading,
    titleSmall = LazureType.ankyLabel,
    bodyLarge = LazureType.ankyProse,
    bodyMedium = LazureType.ankyProse,
    bodySmall = LazureType.ankyCaption,
    labelLarge = LazureType.ankyAction,
    labelMedium = LazureType.ankyLabel,
    labelSmall = LazureType.ankyCaption,
)

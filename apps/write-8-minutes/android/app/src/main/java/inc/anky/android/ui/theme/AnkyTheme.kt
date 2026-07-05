package inc.anky.android.ui.theme

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import inc.anky.android.R

object AnkyColors {
    val Background = Color(0xFF08090B)
    val Ink = Color(0xFF080713)
    val Panel = Color(0xB8140E26)
    val PanelStrong = Color(0xD0131021)
    val ButtonFill = Color(0xBD302117)
    val Accent = Color(0xFFD7BA73)
    val Gold = Color(0xFFE8C879)
    val GoldSoft = Color(0xB8E8C879)
    val GoldDim = Color(0x52E8C879)
    val Paper = Color(0xFFFFF0C9)
    val PaperMuted = Color(0xB8DBCFEB)
    val Danger = Color(0xFFF87171)
    val Success = Color(0xFF86EFAC)
    val Violet = Color(0xFF6F5DFF)
}

object AnkyType {
    val Title = TextStyle(
        fontFamily = FontFamily.Default,
        fontWeight = FontWeight.SemiBold,
        fontSize = 34.sp,
        color = AnkyColors.Gold,
    )
    val Heading = TextStyle(
        fontFamily = FontFamily.Default,
        fontWeight = FontWeight.SemiBold,
        fontSize = 22.sp,
        color = AnkyColors.Gold,
    )
    val Body = TextStyle(
        fontFamily = FontFamily.Default,
        fontSize = 16.sp,
        lineHeight = 23.sp,
        color = AnkyColors.Paper,
    )
    val Writing = TextStyle(
        fontFamily = FontFamily.Default,
        fontSize = 18.sp,
        lineHeight = 26.sp,
        color = AnkyColors.Paper,
    )
    val Caption = TextStyle(
        fontFamily = FontFamily.Default,
        fontWeight = FontWeight.SemiBold,
        fontSize = 12.sp,
        color = AnkyColors.GoldSoft,
    )
    val Mono = TextStyle(
        fontFamily = FontFamily.Default,
        fontSize = 12.sp,
        lineHeight = 18.sp,
        color = AnkyColors.PaperMuted,
    )
}

@Composable
fun AnkyTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = darkColorScheme(
            background = AnkyColors.Background,
            surface = AnkyColors.Panel,
            primary = AnkyColors.Accent,
            onPrimary = AnkyColors.Ink,
            onBackground = AnkyColors.Paper,
            onSurface = AnkyColors.Paper,
            error = AnkyColors.Danger,
        ),
        content = content,
    )
}

@Composable
fun AnkyCosmicBackground(
    modifier: Modifier = Modifier,
    content: @Composable BoxScope.() -> Unit,
) {
    Box(modifier = modifier.fillMaxSize().background(AnkyColors.Ink)) {
        Image(
            painter = painterResource(R.drawable.you_bg_cosmos),
            contentDescription = null,
            contentScale = ContentScale.Crop,
            modifier = Modifier.fillMaxSize(),
        )
        Box(Modifier.fillMaxSize().background(Color(0x5205050E)))
        content()
    }
}

@Composable
fun AnkyMapBackground(
    modifier: Modifier = Modifier,
    overlay: Color = Color(0x2E000000),
    content: @Composable BoxScope.() -> Unit,
) {
    Box(modifier = modifier.fillMaxSize().background(AnkyColors.Ink)) {
        Image(
            painter = painterResource(R.drawable.map_background),
            contentDescription = null,
            contentScale = ContentScale.Crop,
            modifier = Modifier.fillMaxSize(),
        )
        Box(Modifier.fillMaxSize().background(overlay))
        content()
    }
}

@Composable
fun AnkyPanel(
    modifier: Modifier = Modifier,
    contentPadding: PaddingValues = PaddingValues(horizontal = 16.dp, vertical = 14.dp),
    content: @Composable ColumnScope.() -> Unit,
) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(18.dp))
            .background(AnkyColors.Panel)
            .border(1.dp, AnkyColors.GoldDim, RoundedCornerShape(18.dp))
            .padding(contentPadding),
        content = content,
    )
}

@Composable
fun AnkyActionButton(
    text: String,
    modifier: Modifier = Modifier,
    destructive: Boolean = false,
    enabled: Boolean = true,
    onClick: () -> Unit,
) {
    val color = if (destructive) AnkyColors.Danger else AnkyColors.Gold
    Button(
        onClick = onClick,
        enabled = enabled,
        shape = RoundedCornerShape(14.dp),
        colors = ButtonDefaults.buttonColors(
            containerColor = AnkyColors.ButtonFill,
            contentColor = color,
            disabledContainerColor = AnkyColors.PanelStrong,
            disabledContentColor = AnkyColors.PaperMuted,
        ),
        contentPadding = PaddingValues(vertical = 12.dp, horizontal = 14.dp),
        modifier = modifier.fillMaxWidth().border(1.dp, color.copy(alpha = 0.38f), RoundedCornerShape(14.dp)),
    ) {
        Text(text, style = AnkyType.Caption.copy(fontSize = 15.sp, color = color))
    }
}

fun Modifier.ankyCircleBorder(): Modifier =
    this.clip(CircleShape).border(1.dp, AnkyColors.GoldDim, CircleShape)

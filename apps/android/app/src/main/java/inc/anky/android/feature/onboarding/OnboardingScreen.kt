package inc.anky.android.feature.onboarding

import android.view.HapticFeedbackConstants
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
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
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import inc.anky.android.R
import inc.anky.android.ui.theme.AnkyType
import kotlinx.coroutines.launch

@Composable
fun AnkyOnboardingScreen(
    startWriting: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val pagerState = rememberPagerState(pageCount = { OnboardingPages.size })
    val scope = rememberCoroutineScope()
    val view = LocalView.current
    val page = pagerState.currentPage.coerceIn(OnboardingPages.indices)

    Box(
        modifier = modifier
            .fillMaxSize()
            .background(Color.Black)
            .semantics { contentDescription = "Anky onboarding" },
    ) {
        HorizontalPager(
            state = pagerState,
            modifier = Modifier.fillMaxSize(),
        ) { index ->
            OnboardingImagePage(OnboardingPages[index])
        }

        Column(
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .fillMaxWidth()
                .padding(horizontal = 28.dp)
                .padding(bottom = 34.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            TextLine(OnboardingPages[page].line)
            Spacer(Modifier.height(28.dp))
            OnboardingCta(OnboardingPages[page].cta) {
                view.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
                if (page < OnboardingPages.lastIndex) {
                    scope.launch {
                        pagerState.animateScrollToPage(page + 1)
                    }
                } else {
                    startWriting()
                }
            }
            OnboardingDots(currentIndex = page, total = OnboardingPages.size)
        }
    }
}

@Composable
private fun OnboardingImagePage(page: OnboardingPage) {
    Box(Modifier.fillMaxSize()) {
        Image(
            painter = painterResource(page.imageRes),
            contentDescription = null,
            contentScale = ContentScale.Crop,
            modifier = Modifier.fillMaxSize(),
        )
        Box(
            Modifier
                .fillMaxSize()
                .background(
                    Brush.verticalGradient(
                        listOf(
                            Color.Black.copy(alpha = 0.18f),
                            Color.Black.copy(alpha = 0.02f),
                            Color.Black.copy(alpha = 0.34f),
                            Color.Black.copy(alpha = 0.72f),
                        ),
                    ),
                ),
        )
    }
}

@Composable
private fun TextLine(text: String) {
    androidx.compose.material3.Text(
        text = text,
        style = AnkyType.Heading.copy(
            fontSize = 27.sp,
            fontWeight = FontWeight.Medium,
            color = Color(0xFFFFE09A),
            textAlign = TextAlign.Center,
        ),
        lineHeight = 32.sp,
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 2.dp),
    )
}

@Composable
private fun OnboardingCta(title: String, onClick: () -> Unit) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(74.dp)
            .clip(RoundedCornerShape(999.dp))
            .background(
                Brush.linearGradient(
                    listOf(
                        Color(0xFF4A176A).copy(alpha = 0.95f),
                        Color(0xFF250834).copy(alpha = 0.98f),
                    ),
                    start = Offset.Zero,
                    end = Offset(1000f, 1000f),
                ),
            )
            .border(
                width = 1.8.dp,
                brush = Brush.linearGradient(
                    listOf(
                        Color(0xFFFFE7A3),
                        Color(0xFFB668FF),
                        Color(0xFFFFCA64),
                    ),
                ),
                shape = RoundedCornerShape(999.dp),
            )
            .clickable(onClick = onClick)
            .semantics { contentDescription = title },
        contentAlignment = Alignment.Center,
    ) {
        Canvas(Modifier.fillMaxSize()) {
            drawCircle(
                color = Color(0xFF9C5CFF).copy(alpha = 0.18f),
                radius = size.width * 0.38f,
                center = Offset(size.width * 0.5f, 0f),
            )
            drawRoundRect(
                color = Color.White.copy(alpha = 0.12f),
                style = Stroke(width = 0.8.dp.toPx()),
                cornerRadius = androidx.compose.ui.geometry.CornerRadius(size.height / 2, size.height / 2),
            )
        }
        androidx.compose.material3.Text(
            text = title,
            style = AnkyType.Heading.copy(
                fontSize = 24.sp,
                fontWeight = FontWeight.Medium,
                color = Color(0xFFFFE09A),
                textAlign = TextAlign.Center,
            ),
            maxLines = 1,
            modifier = Modifier.padding(horizontal = 18.dp),
        )
    }
}

@Composable
private fun OnboardingDots(currentIndex: Int, total: Int) {
    Row(
        horizontalArrangement = Arrangement.spacedBy(14.dp),
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier.padding(top = 18.dp),
    ) {
        repeat(total) { index ->
            val selected = index == currentIndex
            Box(
                Modifier
                    .size(if (selected) 10.dp else 8.dp)
                    .clip(CircleShape)
                    .background(if (selected) Color(0xFFFFD37A) else Color(0xFF7A5A9A).copy(alpha = 0.55f))
                    .shadow(if (selected) 8.dp else 0.dp, CircleShape),
            )
        }
    }
}

private data class OnboardingPage(
    val imageRes: Int,
    val line: String,
    val cta: String,
)

private val OnboardingPages = listOf(
    OnboardingPage(
        imageRes = R.drawable.onboarding_1,
        line = "You don't need another prompt.",
        cta = "Be with what is here",
    ),
    OnboardingPage(
        imageRes = R.drawable.onboarding_2,
        line = "Write forward. 8 seconds of silence ends it.",
        cta = "No backspace. Just write.",
    ),
    OnboardingPage(
        imageRes = R.drawable.onboarding_3,
        line = "Tell me who you are.",
        cta = "Write 8 minutes",
    ),
)

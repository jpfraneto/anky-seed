package inc.anky.android.ui.lazure

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.min
import kotlin.math.max
import kotlin.math.sin

/**
 * The little sun from the poster — a ring of rays with a spiral heart.
 * Drawn, not typeset: no icon font has a spiral heart.
 *
 * Exact port of the iOS `AnkySunGlyph` Canvas math: twelve rays from
 * 0.72r to 0.98r, a ring at 0.52r, and a 2.2-turn Archimedean spiral
 * out to 0.34r sampled in 60 segments. Stroke width `max(1.1, 0.09r)`
 * (the iOS 1.1pt floor becomes 1.1dp), spiral stroked at 0.9x.
 *
 * Decorative; carries no semantics (the iOS view is accessibility-hidden).
 */
@Composable
fun AnkySunGlyph(
    modifier: Modifier = Modifier,
    size: Dp = 28.dp,
    color: Color = LazurePigments.ankyGold,
) {
    Canvas(modifier.size(size)) {
        val center = Offset(this.size.width / 2f, this.size.height / 2f)
        val r = min(this.size.width, this.size.height) / 2f
        val stroke = max(1.1.dp.toPx(), r * 0.09f)

        // Rays — twelve short strokes, hand-spaced.
        for (i in 0 until 12) {
            val angle = i.toFloat() / 12f * 2f * PI.toFloat()
            drawLine(
                color = color,
                start = Offset(
                    center.x + cos(angle) * r * 0.72f,
                    center.y + sin(angle) * r * 0.72f,
                ),
                end = Offset(
                    center.x + cos(angle) * r * 0.98f,
                    center.y + sin(angle) * r * 0.98f,
                ),
                strokeWidth = stroke,
                cap = StrokeCap.Round,
            )
        }

        // Ring.
        drawCircle(
            color = color,
            radius = r * 0.52f,
            center = center,
            style = Stroke(width = stroke),
        )

        // Spiral heart.
        val spiral = Path()
        val turns = 2.2f
        val steps = 60
        for (step in 0..steps) {
            val t = step.toFloat() / steps.toFloat()
            val angle = t * turns * 2f * PI.toFloat()
            val radius = r * 0.34f * t
            val point = Offset(
                center.x + cos(angle) * radius,
                center.y + sin(angle) * radius,
            )
            if (step == 0) spiral.moveTo(point.x, point.y) else spiral.lineTo(point.x, point.y)
        }
        drawPath(
            path = spiral,
            color = color,
            style = Stroke(width = stroke * 0.9f, cap = StrokeCap.Round, join = StrokeJoin.Round),
        )
    }
}

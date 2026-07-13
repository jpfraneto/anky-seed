package inc.anky.android.core.level

/**
 * Level curve — the single source of truth for level math on Android.
 *
 * The only input is lifetime seconds written. Level 1→2 costs exactly
 * [BaseSeconds] (one full ritual); each subsequent level costs [Ratio]
 * times the previous one, rounded to whole seconds at every step so the
 * sequence is exactly reproducible in any IEEE-754 runtime (mirrored in
 * Swift `AnkyLevel.swift` and TypeScript protocol `level.ts` — keep the
 * three in lockstep).
 *
 * The per-step rounding uses `Math.round` (ties toward positive infinity),
 * which for the positive values on this curve is identical to Swift's
 * `.rounded()` (ties away from zero) and JavaScript's `Math.round`.
 */
object AnkyLevel {
    const val BaseSeconds: Int = 480
    const val Ratio: Double = 1.62
    const val MaxLevel: Int = 120

    /**
     * 2^53 − 1: the largest integer both IEEE doubles (TypeScript) and Long
     * represent exactly; curve values are clamped here on both platforms.
     */
    internal const val MaxExactSeconds: Double = 9_007_199_254_740_991.0

    data class Progress(
        val level: Int,
        val secondsIntoLevel: Long,
        val secondsRequired: Long,
        val percent: Double,
        val totalSeconds: Long,
    )

    /** Seconds needed to go from `level` to `level + 1`. Levels are 1-based. */
    fun requirementSeconds(level: Int): Long {
        require(level >= 1) { "INVALID_LEVEL" }
        var requirement = BaseSeconds.toDouble()
        var n = 1
        while (n < minOf(level, MaxLevel)) {
            requirement = Math.round(requirement * Ratio).toDouble()
            n += 1
        }
        return minOf(requirement, MaxExactSeconds).toLong()
    }

    /** Lifetime seconds required to reach `level`. `thresholdSeconds(1) == 0`. */
    fun thresholdSeconds(level: Int): Long {
        require(level >= 1) { "INVALID_LEVEL" }
        var threshold = 0.0
        var requirement = BaseSeconds.toDouble()
        var n = 1
        while (n < minOf(level, MaxLevel + 1)) {
            threshold += requirement
            requirement = Math.round(requirement * Ratio).toDouble()
            n += 1
        }
        return minOf(threshold, MaxExactSeconds).toLong()
    }

    fun level(totalSeconds: Long): Int {
        val total = maxOf(0L, totalSeconds).toDouble()
        var level = 1
        var threshold = 0.0
        var requirement = BaseSeconds.toDouble()
        while (level < MaxLevel && total >= threshold + requirement) {
            threshold += requirement
            requirement = Math.round(requirement * Ratio).toDouble()
            level += 1
        }
        return level
    }

    fun progress(totalSeconds: Long): Progress {
        val total = maxOf(0L, totalSeconds)
        val level = level(total)
        val threshold = thresholdSeconds(level)
        val required = requirementSeconds(level)
        val into = minOf(total - threshold, required)
        val percent = if (level >= MaxLevel) 1.0 else minOf(1.0, into.toDouble() / required.toDouble())
        return Progress(
            level = level,
            secondsIntoLevel = into,
            secondsRequired = required,
            percent = percent,
            totalSeconds = total,
        )
    }
}

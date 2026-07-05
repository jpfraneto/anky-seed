import Foundation

/// Level curve — the single source of truth for level math on iOS.
///
/// The only input is lifetime seconds written. Level 1→2 costs exactly
/// `baseSeconds` (one full ritual); each subsequent level costs `ratio`
/// times the previous one, rounded to whole seconds at every step so the
/// sequence is exactly reproducible in any IEEE-754 runtime (mirrored in
/// TypeScript as protocol `level.ts` — keep the two in lockstep).
public enum AnkyLevel {
    public static let baseSeconds: Int = 480
    public static let ratio: Double = 1.62
    public static let maxLevel: Int = 120

    /// 2^53 − 1: the largest integer both IEEE doubles (TypeScript) and Int64
    /// represent exactly; curve values are clamped here on both platforms.
    static let maxExactSeconds = 9_007_199_254_740_991.0

    public struct Progress: Equatable, Codable {
        public let level: Int
        public let secondsIntoLevel: Int
        public let secondsRequired: Int
        public let percent: Double
        public let totalSeconds: Int

        public init(level: Int, secondsIntoLevel: Int, secondsRequired: Int, percent: Double, totalSeconds: Int) {
            self.level = level
            self.secondsIntoLevel = secondsIntoLevel
            self.secondsRequired = secondsRequired
            self.percent = percent
            self.totalSeconds = totalSeconds
        }
    }

    /// Seconds needed to go from `level` to `level + 1`. Levels are 1-based.
    public static func requirementSeconds(forLevel level: Int) -> Int {
        precondition(level >= 1, "INVALID_LEVEL")
        var requirement = Double(baseSeconds)
        var n = 1
        while n < min(level, maxLevel) {
            requirement = (requirement * ratio).rounded()
            n += 1
        }
        return Int(min(requirement, maxExactSeconds))
    }

    /// Lifetime seconds required to reach `level`. `thresholdSeconds(forLevel: 1) == 0`.
    public static func thresholdSeconds(forLevel level: Int) -> Int {
        precondition(level >= 1, "INVALID_LEVEL")
        var threshold = 0.0
        var requirement = Double(baseSeconds)
        var n = 1
        while n < min(level, maxLevel + 1) {
            threshold += requirement
            requirement = (requirement * ratio).rounded()
            n += 1
        }
        return Int(min(threshold, maxExactSeconds))
    }

    public static func level(forTotalSeconds totalSeconds: Int) -> Int {
        let total = Double(max(0, totalSeconds))
        var level = 1
        var threshold = 0.0
        var requirement = Double(baseSeconds)
        while level < maxLevel, total >= threshold + requirement {
            threshold += requirement
            requirement = (requirement * ratio).rounded()
            level += 1
        }
        return level
    }

    public static func progress(forTotalSeconds totalSeconds: Int) -> Progress {
        let total = max(0, totalSeconds)
        let level = level(forTotalSeconds: total)
        let threshold = thresholdSeconds(forLevel: level)
        let required = requirementSeconds(forLevel: level)
        let into = min(total - threshold, required)
        let percent = level >= maxLevel ? 1.0 : min(1.0, Double(into) / Double(required))
        return Progress(
            level: level,
            secondsIntoLevel: into,
            secondsRequired: required,
            percent: percent,
            totalSeconds: total
        )
    }
}

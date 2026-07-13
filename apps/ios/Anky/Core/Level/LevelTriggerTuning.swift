import Foundation
#if SWIFT_PACKAGE
import AnkyProtocol
#endif

/// Pre-generation trigger tuning — every constant of "when does anky start
/// painting the next level" lives here.
enum LevelTriggerTuning {
    /// Trailing window for the writer's daily-output distribution.
    static let dailyOutputWindowDays = 28
    /// Trigger when seconds remaining in the level drop below this percentile
    /// of daily output — days of runway for normal writers, hours for heavy.
    static let dailyOutputPercentile = 0.95
    /// With fewer than this many writing days of history, fall back to
    /// triggering at `fallbackProgressFraction` of the level.
    static let minimumHistoryDays = 7
    static let fallbackProgressFraction = 0.9
    /// Distillation payload cap (characters). The server backstops this too.
    static let maxDistillCharacters = 60_000

    /// Should the next painting start generating now?
    static func shouldPrepareNextPainting(
        progress: AnkyLevel.Progress,
        dailySecondsHistory: [Int]
    ) -> Bool {
        let secondsRemaining = progress.secondsRequired - progress.secondsIntoLevel
        let writingDays = dailySecondsHistory.filter { $0 > 0 }
        if writingDays.count >= minimumHistoryDays {
            let sorted = writingDays.sorted()
            let rank = Int((Double(sorted.count - 1) * dailyOutputPercentile).rounded())
            let p95Daily = sorted[max(0, min(sorted.count - 1, rank))]
            return secondsRemaining < p95Daily
        }
        return progress.percent >= fallbackProgressFraction
    }

    /// Seconds written per day over the trailing window, derived from the
    /// session index (most recent day last; zero-days included).
    static func dailySecondsHistory(
        from summaries: [SessionSummary],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [Int] {
        let today = calendar.startOfDay(for: now)
        var secondsPerDay: [Date: Int] = [:]
        for summary in summaries {
            let day = calendar.startOfDay(for: summary.createdAt)
            secondsPerDay[day, default: 0] += Int(summary.durationMs / 1000)
        }
        return (0..<dailyOutputWindowDays).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else {
                return nil
            }
            return secondsPerDay[day] ?? 0
        }.reversed()
    }

    /// The distillation corpus: reconstructed text of every session sealed
    /// since the last level-up, most recent kept when the cap bites. The
    /// text leaves the device once, transiently, for the distillation call —
    /// never for anything else.
    static func distillText(
        artifacts: [SavedAnky],
        sinceMs: Int64?
    ) -> String {
        let cutoff = sinceMs.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) }
        let chapter = artifacts
            .filter { artifact in
                guard let cutoff else { return true }
                return artifact.createdAt > cutoff
            }
            .sorted { $0.createdAt > $1.createdAt } // most recent first

        var pieces: [String] = []
        var totalCharacters = 0
        for artifact in chapter {
            let text = artifact.reconstructedText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let remaining = maxDistillCharacters - totalCharacters
            guard remaining > 200 else { break }
            let clipped = text.count > remaining ? String(text.prefix(remaining)) : text
            pieces.append(clipped)
            totalCharacters += clipped.count + 8
        }
        // Chronological order reads as the chapter it was.
        return pieces.reversed().joined(separator: "\n\n---\n\n")
    }

    static func loadingExcerpts(
        artifacts: [SavedAnky],
        sinceMs: Int64?,
        limit: Int = 4
    ) -> [String] {
        let cutoff = sinceMs.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) }
        let chapter = artifacts
            .filter { artifact in
                guard let cutoff else { return true }
                return artifact.createdAt > cutoff
            }
            .sorted { $0.createdAt < $1.createdAt }

        let candidates = chapter.compactMap { excerpt(from: $0.reconstructedText) }
        guard candidates.count > limit, limit > 0 else {
            return Array(candidates.prefix(max(0, limit)))
        }

        return (0..<limit).map { index in
            let position = Double(index) / Double(max(1, limit - 1))
            let candidateIndex = Int((position * Double(candidates.count - 1)).rounded())
            return candidates[min(candidates.count - 1, max(0, candidateIndex))]
        }
    }

    private static func excerpt(from text: String, maxCharacters: Int = 180) -> String? {
        let normalized = text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count >= 24 else {
            return nil
        }
        guard normalized.count > maxCharacters else {
            return normalized
        }

        var excerpt = ""
        for word in normalized.split(separator: " ") {
            let next = excerpt.isEmpty ? String(word) : "\(excerpt) \(word)"
            guard next.count <= maxCharacters else {
                break
            }
            excerpt = next
        }
        return excerpt.isEmpty ? String(normalized.prefix(maxCharacters)) : "\(excerpt)..."
    }
}

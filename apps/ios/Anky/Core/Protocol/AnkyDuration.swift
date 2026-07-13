import Foundation

public enum AnkyDuration {
    public static let completeRitualMinutes = 8
    public static let completeRitualMs: Int64 = Int64(completeRitualMinutes) * 60 * 1000
    public static let defaultTerminalSilenceMs: Int64 = 8000
    public static let minTerminalSilenceMs: Int64 = 1000
    public static let maxTerminalSilenceMs: Int64 = 8000
    public static let terminalSilenceMs: Int64 = defaultTerminalSilenceMs

    public static func clampedTerminalSilenceMs(_ value: Int64) -> Int64 {
        min(max(value, minTerminalSilenceMs), maxTerminalSilenceMs)
    }

    public static func terminalMarkerMs(from line: String) -> Int64? {
        guard !line.isEmpty,
              line.allSatisfy(\.isNumber),
              let value = Int64(line),
              value > 0 else {
            return nil
        }
        return value
    }

    public static func writingDurationMs(_ parsed: ParsedAnky) -> Int64 {
        parsed.events.reduce(Int64(0)) { sum, event in
            sum + event.deltaMs
        }
    }

    public static func durationMs(_ parsed: ParsedAnky) -> Int64 {
        writingDurationMs(parsed)
    }

    public static func isComplete(_ parsed: ParsedAnky) -> Bool {
        writingDurationMs(parsed) >= completeRitualMs
    }

    public static func formatted(_ durationMs: Int64) -> String {
        let totalSeconds = max(0, durationMs / 1000)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return "\(minutes)m \(String(format: "%02d", seconds))s"
    }

    public static func clock(_ durationMs: Int64) -> String {
        let totalSeconds = max(0, durationMs / 1000)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return "\(minutes):\(String(format: "%02d", seconds))"
    }

    public static func ritualClock(_ durationMs: Int64) -> String {
        clock(min(durationMs, completeRitualMs))
    }

    public static func utcDayProgress(at date: Date, secondsPerDay: TimeInterval = 86_400) -> Double {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let start = calendar.startOfDay(for: date)
        let elapsed = date.timeIntervalSince(start)
        return min(1, max(0, elapsed / secondsPerDay))
    }
}

import Foundation

public enum AnkyDuration {
    public static let completeRitualMs: Int64 = 8 * 60 * 1000
    public static let terminalSilenceMs: Int64 = 8000

    public static func durationMs(_ parsed: ParsedAnky) -> Int64 {
        let writingDuration = parsed.events.reduce(Int64(0)) { sum, event in
            sum + event.deltaMs
        }
        return writingDuration + (parsed.terminalSilenceMs ?? 0)
    }

    public static func isComplete(_ parsed: ParsedAnky) -> Bool {
        durationMs(parsed) >= completeRitualMs && parsed.terminalSilenceMs == terminalSilenceMs
    }

    public static func formatted(_ durationMs: Int64) -> String {
        let totalSeconds = max(0, durationMs / 1000)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return "\(minutes)m \(String(format: "%02d", seconds))s"
    }
}

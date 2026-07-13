import Foundation

public enum AnkyParser {
    public static func parse(_ text: String) throws -> ParsedAnky {
        var lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        if lines.last == "" {
            lines.removeLast()
        }

        guard !lines.isEmpty else {
            throw AnkyParseError.emptyAnky
        }

        let first = try parseWritingLine(lines[0])
        var events = [AnkyEvent(deltaMs: 0, character: first.character)]
        var terminalSilenceMs: Int64?

        for line in lines.dropFirst() {
            if let terminalMs = AnkyDuration.terminalMarkerMs(from: line) {
                if terminalSilenceMs != nil {
                    throw AnkyParseError.duplicateTerminalSilence
                }
                terminalSilenceMs = terminalMs
                continue
            }

            if terminalSilenceMs != nil {
                throw AnkyParseError.eventAfterTerminalSilence
            }

            let event = try parseWritingLine(line)
            events.append(AnkyEvent(deltaMs: event.time, character: event.character))
        }

        return ParsedAnky(
            startEpochMs: first.time,
            events: events,
            terminalSilenceMs: terminalSilenceMs
        )
    }

    private static func parseWritingLine(_ line: String) throws -> (time: Int64, character: Character) {
        guard let separator = line.firstIndex(of: " "), separator != line.startIndex else {
            throw AnkyParseError.malformedLine
        }

        let timeText = String(line[..<separator])
        let characterText = String(line[line.index(after: separator)...])

        guard !timeText.isEmpty, timeText.allSatisfy(\.isNumber) else {
            throw AnkyParseError.invalidTime
        }

        guard !characterText.isEmpty else {
            throw AnkyParseError.missingCharacter
        }

        if characterText == "SPACE" {
            guard let time = Int64(timeText) else {
                throw AnkyParseError.unsafeTime
            }
            return (time, " ")
        }

        if characterText == " " {
            throw AnkyParseError.nonCanonicalSpace
        }

        guard characterText.count == 1, let character = characterText.first else {
            throw AnkyParseError.multiCharacterEvent
        }

        guard let time = Int64(timeText) else {
            throw AnkyParseError.unsafeTime
        }

        return (time, character)
    }
}

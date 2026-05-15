import Foundation

public struct AnkyEvent: Equatable {
    public let deltaMs: Int64
    public let character: Character

    public init(deltaMs: Int64, character: Character) {
        self.deltaMs = deltaMs
        self.character = character
    }
}

public struct ParsedAnky: Equatable {
    public let startEpochMs: Int64
    public let events: [AnkyEvent]
    public let terminalSilenceMs: Int64?

    public init(startEpochMs: Int64, events: [AnkyEvent], terminalSilenceMs: Int64?) {
        self.startEpochMs = startEpochMs
        self.events = events
        self.terminalSilenceMs = terminalSilenceMs
    }
}

public enum AnkyParseError: Error, Equatable {
    case emptyAnky
    case malformedLine
    case invalidTime
    case missingCharacter
    case multiCharacterEvent
    case unsafeTime
    case duplicateTerminalSilence
    case eventAfterTerminalSilence
}

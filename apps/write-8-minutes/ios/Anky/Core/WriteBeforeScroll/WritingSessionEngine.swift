import Foundation
#if SWIFT_PACKAGE
import AnkyProtocol
#endif

struct WritingSessionSnapshot: Equatable {
    let protocolText: String
    let reconstructedText: String
    let elapsedMs: Int64
    let lastAcceptedMs: Int64?
    let isStarted: Bool
    let isClosed: Bool

    var hasCompletedSentence: Bool {
        UnlockPolicy.hasCompletedQuickSentence(in: reconstructedText)
    }

    var hasUnlockableWriting: Bool {
        reconstructedText.contains { !$0.isWhitespace && !$0.isNewline }
    }
}

struct WritingSessionEngine {
    private(set) var writer: AnkyWriter
    private(set) var reconstructedText: String

    init() {
        self.writer = AnkyWriter()
        self.reconstructedText = ""
    }

    init(draftText: String) throws {
        let writer = try AnkyWriter(draftText: draftText)
        let parsed = try AnkyParser.parse(draftText)
        self.writer = writer
        self.reconstructedText = AnkyReconstructor.reconstructText(parsed)
    }

    var protocolText: String {
        writer.text
    }

    var elapsedMs: Int64 {
        writer.writingElapsedMs
    }

    var isStarted: Bool {
        writer.isStarted
    }

    var isClosed: Bool {
        writer.isClosed
    }

    var lastAcceptedMs: Int64? {
        writer.lastAcceptedMs
    }

    var hasReachedFullAnky: Bool {
        elapsedMs >= AnkyDuration.completeRitualMs
    }

    var snapshot: WritingSessionSnapshot {
        WritingSessionSnapshot(
            protocolText: protocolText,
            reconstructedText: reconstructedText,
            elapsedMs: elapsedMs,
            lastAcceptedMs: lastAcceptedMs,
            isStarted: isStarted,
            isClosed: isClosed
        )
    }

    @discardableResult
    mutating func accept(_ text: String, at epochMs: Int64) -> [Character] {
        let characters = text.filter(isForwardWritingCharacter)
        guard !characters.isEmpty else {
            return []
        }

        if characters.count == 1 {
            guard let character = characters.first,
                  writer.accept(character, at: epochMs) else {
                return []
            }
            reconstructedText.append(character)
            return [character]
        }

        let eventTimes = syntheticEventTimes(
            characterCount: characters.count,
            insertionEpochMs: epochMs
        )

        var accepted = [Character]()
        for (index, character) in characters.enumerated() {
            guard writer.accept(character, at: eventTimes[index]) else {
                continue
            }
            reconstructedText.append(character)
            accepted.append(character)
        }
        return accepted
    }

    mutating func prepareToResume(at epochMs: Int64) {
        writer.prepareToResume(at: epochMs)
    }

    @discardableResult
    mutating func replaceSuffix(
        keepingPrefixCharacterCount prefixCount: Int,
        with replacementText: String,
        at epochMs: Int64
    ) -> [Character] {
        let accepted = writer.replaceSuffix(
            keepingPrefixCharacterCount: prefixCount,
            with: replacementText,
            at: epochMs
        )
        guard !accepted.isEmpty else {
            return []
        }

        let clampedPrefixCount = min(max(0, prefixCount), reconstructedText.count)
        let prefix = reconstructedText.prefix(clampedPrefixCount)
        reconstructedText = String(prefix) + String(accepted)
        return accepted
    }

    mutating func closeWithTerminalSilence() {
        writer.closeWithTerminalSilence()
    }

    mutating func reset() {
        writer = AnkyWriter()
        reconstructedText = ""
    }

    func silenceElapsedMs(at epochMs: Int64) -> Int64 {
        guard let lastAcceptedMs else {
            return 0
        }
        return max(0, epochMs - lastAcceptedMs)
    }

    private func isForwardWritingCharacter(_ character: Character) -> Bool {
        character != "\n" && character != "\r"
    }

    private func syntheticEventTimes(characterCount: Int, insertionEpochMs: Int64) -> [Int64] {
        guard characterCount > 1,
              let previousAppendMs = writer.lastAcceptedMs else {
            return Array(repeating: insertionEpochMs, count: characterCount)
        }

        let elapsedSinceLastAppend = max(0, insertionEpochMs - previousAppendMs)
        guard elapsedSinceLastAppend > 0 else {
            return Array(repeating: insertionEpochMs, count: characterCount)
        }

        let baseDelta = elapsedSinceLastAppend / Int64(characterCount)
        let remainder = Int(elapsedSinceLastAppend % Int64(characterCount))
        var cursor = previousAppendMs
        return (0..<characterCount).map { index in
            let delta = baseDelta + (index < remainder ? 1 : 0)
            cursor += delta
            return cursor
        }
    }
}

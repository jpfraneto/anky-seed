//
//  GeshtuDebugSeed.swift
//  Anky — the Geshtu Redesign (dev-only test infrastructure).
//
//  Populates the local archive — and, for sent days, the reflection store —
//  with synthetic strata so the landing surface (§7 / addendum A1), the opened
//  entry (addendum A2), unsent coexistence (addendum A3), and the surfacing
//  performance path (verification Q6) can be seen and measured without writing
//  hundreds of real sessions by hand.
//
//  Behind DEBUG only. Never compiled into a shipping build; it writes to the
//  same real stores the app uses, so it also exercises the real read paths.
//

#if DEBUG
import Foundation

enum GeshtuDebugSeed {

    /// A small, hand-authored showcase: sent days (with reflections) and unsent
    /// days (writing only) interleaved, so the column's refusal to distinguish
    /// them (addendum A3.1) and the opened-entry order (A2.2) are both visible.
    static func seedShowcase() {
        wipe()
        // (writing, ageInDays, sent?)
        let days: [(String, Int, Bool)] = [
            ("tonight i sat with the kind of quiet that has weight. not empty but full in a way i cannot always explain. i stayed. i kept choosing this.", 0, true),
            ("woke before the alarm and lay there listening to the building come awake. i did not reach for the phone. small thing. it did not feel small.", 1, false),
            ("the argument kept replaying and then it just stopped. i think i forgave him somewhere in the middle of writing this sentence.", 2, true),
            ("nothing to say today and i said it anyway. sometimes the practice is only showing up to the blank page and breathing near it.", 4, false),
            ("i walked to the water and the light was doing that thing it does in october, going gold and low and a little sad and i loved it.", 6, true),
            ("counted the things that did not go wrong. it is a longer list than fear lets me believe on the worst mornings.", 9, true),
            ("she said my name like it still meant something and i have been carrying it around all day like a warm stone in a pocket.", 13, false),
            ("began again. i am always beginning again. maybe that is the whole thing, the beginning, over and over, until it is a life.", 18, true),
        ]
        for day in days {
            save(text: day.0, ageDays: day.1, sent: day.2)
        }
    }

    /// A bulk column for the surfacing-performance test (Q6): confirm that
    /// surface-to-now does not fire per-stratum work for every entry it passes.
    static func seedBulk(_ count: Int = 500) {
        wipe()
        for index in 0..<count {
            let n = count - index
            let sent = index % 3 != 0
            save(
                text: "day \(n). a seeded stratum with enough words to wrap onto a second line so the column has real height. i was here.",
                ageDays: index,
                sent: sent
            )
        }
    }

    static func wipe() {
        try? LocalAnkyArchive().clear()
        try? ReflectionStore().clear()
    }

    // MARK: - Building one synthetic day

    private static func save(text: String, ageDays: Int, sent: Bool) {
        // Absolute epoch of the first keystroke fixes the day's createdAt.
        let startMs = Int64(Date().addingTimeInterval(TimeInterval(-ageDays * 86_400)).timeIntervalSince1970 * 1000)
        var writer = AnkyWriter()
        var cursor = startMs
        for character in text {
            // Newlines are not protocol characters; everything else is accepted.
            writer.accept(character, at: cursor)
            cursor += 220
        }
        writer.closeWithTerminalSilence()

        guard let saved = try? LocalAnkyArchive().save(writer.text) else { return }
        guard sent else { return }

        let reflection = LocalReflection(
            hash: saved.hash,
            title: "",
            reflection: reflectionText(forFirstWords: text),
            createdAt: saved.createdAt
        )
        try? ReflectionStore().save(reflection)
    }

    /// A blessing in the §6 voice: the writer's own language returned, first
    /// person to second person, confession to blessing. Kept short (4–5 lines).
    private static func reflectionText(forFirstWords text: String) -> String {
        let seed = text.split(separator: " ").prefix(4).joined(separator: " ")
        return [
            "you stayed.",
            "and the quiet stayed with you.",
            "\(seed) — this too you kept.",
            "let it be enough that you came.",
            "begin again from here."
        ].joined(separator: "\n")
    }
}
#endif

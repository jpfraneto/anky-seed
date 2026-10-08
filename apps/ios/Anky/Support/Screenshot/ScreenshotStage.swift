//
//  ScreenshotStage.swift
//  Anky — composes one marketing scene, deterministically.
//
//  Two entry points, in launch order:
//
//    `prepareProcess()`  from the app delegate, before any view exists. Wipes
//                        and reseeds the real stores, pins the preferences the
//                        scenes depend on, and takes onboarding out of the way.
//    `apply(...)`        from the world's first appearance. Parks the state
//                        machine on the scene's surface and signals ready.
//
//  Why the split: the archive column, the reflection and the writer's target
//  are all read during view construction, so they have to exist before the
//  first frame. The phase change has to happen after, because it needs the
//  live `GeshtuState`.
//
//  Determinism notes worth keeping:
//    * Dates come from the fixture, never from `Date()`. Regenerating the set
//      next month produces byte-identical archive rows.
//    * The writing scenes go in as a RECOVERED DRAFT, which the write engine
//      restores frozen (`isFrozen`, `resumesOnNextInput`) with its ticker
//      cancelled. That is the app's own resume path, so the clock reads the
//      fixture's elapsed time and the silence sentinel cannot fire mid-capture
//      and close the channel out from under the camera.
//
#if DEBUG
import Foundation
import SwiftUI
import UIKit

enum ScreenshotStage {

    /// Set once `prepareProcess` has run, so the view layer knows the stores
    /// under it are the fixture's and not the simulator's leftovers.
    private(set) static var preparedLocale: ScreenshotLocaleFixture?
    private(set) static var preparationError: String?

    /// The writing scenes own the write engine themselves; the world must not
    /// start a blank session over the top of the staged draft.
    static var stagesWritingSurface: Bool {
        guard ScreenshotMode.isActive else { return false }
        switch ScreenshotMode.scene {
        case .ritual, .simplicity: return true
        default: return false
        }
    }

    /// Scene 05 stands the camera and an in-progress take.
    static var stagesRecording: Bool {
        ScreenshotMode.isActive && ScreenshotMode.scene == .recording
    }

    /// Scenes 01 and 02 are worthless without a keyboard, and a simulator
    /// with a hardware keyboard attached will happily focus the text view and
    /// show nothing. The stage watches for the real thing and refuses to
    /// signal ready without it, so a keyboardless frame can never be captured.
    private static var keyboardDidShow = false
    private static var keyboardObserver: NSObjectProtocol?

    /// What the app can see about its own input state. The difference between
    /// "the text view never took first responder" and "it did, and iOS still
    /// showed no keyboard" is the difference between an app bug and a
    /// simulator configuration problem — worth reporting rather than guessing.
    private static func inputStateDescription() -> String {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        let responder = windows.compactMap { firstResponder(in: $0) }.first
        let responderName = responder.map { String(describing: type(of: $0)) } ?? "none"
        let keyboardWindows = windows
            .map { String(describing: type(of: $0)) }
            .filter { $0.localizedCaseInsensitiveContains("keyboard") }
        let keyboardWindow = keyboardWindows.isEmpty ? "none" : keyboardWindows.joined(separator: "+")
        return "firstResponder=\(responderName) keyboardWindow=\(keyboardWindow) windows=\(windows.count)"
    }

    private static func firstResponder(in view: UIView) -> UIView? {
        if view.isFirstResponder { return view }
        for subview in view.subviews {
            if let found = firstResponder(in: subview) { return found }
        }
        return nil
    }

    private static func watchForKeyboard() {
        guard keyboardObserver == nil else { return }
        keyboardObserver = NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardDidShowNotification,
            object: nil,
            queue: .main
        ) { _ in keyboardDidShow = true }
    }

    // MARK: - Phase one: the process, before any view

    static func prepareProcess() {
        guard ScreenshotMode.isActive else { return }
        ScreenshotMode.clearSignal()
        // Registered before the first view: the write surface takes first
        // responder during its initial render, which is earlier than onAppear.
        watchForKeyboard()

        guard ScreenshotMode.scene != nil else {
            fail("ANKY_SCREENSHOT_SCENE missing or unrecognized. Expected one of: "
                 + ScreenshotMode.Scene.allCases.map(\.rawValue).joined(separator: ", "))
            return
        }

        let fixture: ScreenshotLocaleFixture
        do {
            fixture = try ScreenshotFixtures.locale(ScreenshotMode.localeCode)
        } catch {
            fail(error.localizedDescription)
            return
        }

        // Nothing from a previous launch survives into a capture.
        try? LocalAnkyArchive().clear()
        try? ReflectionStore().clear()
        ActiveDraftStore().clear()

        // Out of the way: onboarding, the first-session rehearsal, and the
        // one-shot welcome an imported App Clip session would raise.
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: "anky.onboardingCompleted")
        defaults.set(true, forKey: "anky.axisRehearsalDone")
        defaults.set(false, forKey: ClipSessionImporter.pendingWelcomeDefaultsKey)

        // The clock the writing scenes read from, pinned to the 8 minute
        // ritual so the fixture's elapsed time yields the intended countdown.
        DailyTargetStore().applyImmediateTarget(AnkyDuration.completeRitualMinutes)
        WritingPreferencesStore().update {
            $0.durationIsInfinite = false
            $0.eightSecondRuleEnabled = true
            $0.terminalSilenceMs = AnkyDuration.defaultTerminalSilenceMs
        }

        seedArchive(fixture)
        preparedLocale = fixture
    }

    /// The archive column, oldest first so the newest lands on top, with the
    /// feature writing as the most recent day.
    private static func seedArchive(_ fixture: ScreenshotLocaleFixture) {
        let archive = LocalAnkyArchive()
        let reflections = ReflectionStore()

        for entry in fixture.archive.sorted(by: { $0.date < $1.date }) {
            guard let saved = save(entry.text, at: entry.date, in: archive) else {
                fail("Could not seal archive entry dated \(entry.date).")
                return
            }
            guard entry.reflected else { continue }
            try? reflections.save(LocalReflection(
                hash: saved.hash,
                title: "",
                reflection: shortBlessing(for: entry.text),
                createdAt: saved.createdAt
            ))
        }

        guard let feature = save(fixture.feature.text, at: fixture.feature.date, in: archive) else {
            fail("Could not seal the feature writing.")
            return
        }
        try? reflections.save(LocalReflection(
            hash: feature.hash,
            title: "",
            reflection: fixture.feature.reflection,
            createdAt: feature.createdAt
        ))
        featureHash = feature.hash
    }

    private(set) static var featureHash: String?

    /// Replays a text through the real writer so the artifact on disk is a
    /// genuine .anky protocol string — same path a written session takes.
    /// The keystrokes are spread across `spanMs` so the sealed duration is
    /// exactly what the fixture asked for.
    private static func save(
        _ text: String,
        at date: Date,
        in archive: LocalAnkyArchive,
        spanMs: Int64 = 8 * 60 * 1000
    ) -> SavedAnky? {
        var writer = AnkyWriter()
        replay(text, into: &writer, startingAt: Int64(date.timeIntervalSince1970 * 1000), spanMs: spanMs)
        writer.closeWithTerminalSilence()
        return try? archive.save(writer.text)
    }

    /// Distributes `spanMs` across the accepted characters so the deltas sum
    /// to exactly `spanMs` — the elapsed clock is the sum of those deltas.
    private static func replay(
        _ text: String,
        into writer: inout AnkyWriter,
        startingAt startMs: Int64,
        spanMs: Int64
    ) {
        let characters = text.filter { $0 != "\n" && $0 != "\r" }
        let gaps = max(1, characters.count - 1)
        let step = spanMs / Int64(gaps)
        var remainder = spanMs - step * Int64(gaps)
        var cursor = startMs
        for (index, character) in characters.enumerated() {
            if index > 0 {
                var delta = step
                if remainder > 0 { delta += 1; remainder -= 1 }
                cursor += delta
            }
            writer.accept(character, at: cursor)
        }
    }

    /// A four line blessing in the §6 voice for the column's reflected days.
    /// Never shown at full size in any scene — it only has to make the
    /// reflected/unreflected distinction real in the archive.
    private static func shortBlessing(for text: String) -> String {
        let opening = text.split(separator: " ").prefix(4).joined(separator: " ")
        return "\(opening)\n\n\u{2014}"
    }

    // MARK: - Phase two: the world, on first appearance

    @MainActor
    static func apply(axis: GeshtuState, writeViewModel: WriteViewModel) {
        guard ScreenshotMode.isActive else { return }
        if let preparationError {
            ScreenshotMode.signalFailure(preparationError)
            return
        }
        guard let scene = ScreenshotMode.scene, let fixture = preparedLocale else {
            ScreenshotMode.signalFailure("Screenshot stage was never prepared.")
            return
        }

        switch scene {
        case .ritual:
            guard stageWriting(fixture.ritual, into: writeViewModel) else { return }
            axis.debugSetPhase(.writing)
        case .simplicity:
            guard stageWriting(fixture.simplicity, into: writeViewModel) else { return }
            axis.debugSetPhase(.writing)
        case .reflection, .recording:
            guard let hash = featureHash,
                  let entry = try? LocalAnkyArchive().load(hash: hash) else {
                ScreenshotMode.signalFailure("The feature writing is not in the archive.")
                return
            }
            axis.openEntry(entry)
            if scene == .reflection {
                // Bring the seam — where the writing ends and Anky's response
                // begins — onto the screen, which is what this scene is about.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    axis.requestResponseStart()
                }
            }
        case .archive:
            axis.openDrawer()
        }

        confirmReady(scene: scene, fixture: fixture)
    }

    /// Puts the fixture's writing on the page as a recovered draft: text
    /// restored, clock at the fixture's elapsed time, engine frozen.
    @MainActor
    private static func stageWriting(
        _ writing: ScreenshotLocaleFixture.Writing,
        into writeViewModel: WriteViewModel
    ) -> Bool {
        var writer = AnkyWriter()
        // A stable, arbitrary wall-clock origin: nothing on the writing
        // surface renders it, and pinning it keeps drafts reproducible.
        let origin = Int64(Date(timeIntervalSince1970: 1_787_000_000).timeIntervalSince1970 * 1000)
        replay(writing.text, into: &writer, startingAt: origin, spanMs: writing.elapsedMs)
        guard writer.isStarted else {
            ScreenshotMode.signalFailure("The staged writing produced no protocol characters.")
            return false
        }
        let draft = writer.text
        ActiveDraftStore().save(draft)
        let recovery = ActiveDraftRecovery(
            text: draft,
            createdAt: Date(timeIntervalSince1970: TimeInterval(origin) / 1000),
            durationMs: writer.writingElapsedMs,
            wordCount: writing.text.split { $0.isWhitespace || $0.isNewline }.count
        )
        guard writeViewModel.resumeRecoveredDraft(recovery) else {
            ScreenshotMode.signalFailure("The write engine refused the staged draft.")
            return false
        }
        // Draft recovery paints every glyph at full silence — the madder the
        // sentinel uses just before it closes the channel. That is honest for a
        // resumed draft and wrong for the moment these scenes depict, which is
        // someone mid-sentence. Repaint to ink.
        writeViewModel.debugPaintGlyphsAsInkForScreenshot()
        return true
    }

    /// Waits for the surface to actually settle before telling the capture
    /// script to shoot, and — for the writing scenes — refuses to shoot at all
    /// until the software keyboard is genuinely on screen.
    ///
    /// Two run loop hops plus a short grace covers the phase transition's ease
    /// and the archive's first lazy rows. The keyboard gets longer, because it
    /// is the one thing here that depends on how the simulator was booted.
    private static func confirmReady(scene: ScreenshotMode.Scene, fixture: ScreenshotLocaleFixture) {
        let needsKeyboard = scene == .ritual || scene == .simplicity
        DispatchQueue.main.async {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                awaitKeyboard(scene: scene, fixture: fixture, required: needsKeyboard, attempt: 0)
            }
        }
    }

    private static let keyboardAttempts = 30      // 30 x 0.3s = 9 seconds

    private static func awaitKeyboard(
        scene: ScreenshotMode.Scene,
        fixture: ScreenshotLocaleFixture,
        required: Bool,
        attempt: Int
    ) {
        if !required || keyboardDidShow {
            ScreenshotMode.signalReady(
                scene: scene,
                locale: fixture.appLocale,
                detail: [
                    "appStoreLocale": fixture.appStoreLocale,
                    "languageName": fixture.languageName,
                    "keyboard": keyboardDidShow ? "shown" : "not required"
                ]
            )
            return
        }
        guard attempt < keyboardAttempts else {
            ScreenshotMode.signalFailure(
                "The software keyboard never appeared for the \(scene.rawValue) scene. "
                + "App-side input state: \(inputStateDescription()). "
                + "If firstResponder is a text view, the app did its part and the simulator "
                + "is suppressing the keyboard — see AppStoreScreenshots/keyboard-diagnostics.txt."
            )
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            awaitKeyboard(scene: scene, fixture: fixture, required: required, attempt: attempt + 1)
        }
    }

    private static func fail(_ reason: String) {
        preparationError = reason
        ScreenshotMode.signalFailure(reason)
    }
}
#endif

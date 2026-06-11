# Android Build 61 Writing Parity Verification

## Verdict

VERIFIED: P0 writing parity patch matches iOS build 61.

This verification treats `ANDROID_BUILD_61_WRITING_PARITY_PATCH_REPORT.md` as a claim and checks the current Android diff/source against the audit's iOS build 61 findings.

## Files Reviewed

* `ANDROID_BUILD_61_WRITING_PARITY_AUDIT.md`
* `ANDROID_BUILD_61_WRITING_PARITY_PATCH_REPORT.md`
* `apps/android/app/src/main/java/inc/anky/android/feature/write/WriteViewModel.kt`
* `apps/android/app/src/main/java/inc/anky/android/core/protocol/AnkyWriter.kt`
* `apps/android/app/src/main/java/inc/anky/android/core/protocol/AnkyParser.kt`
* `apps/android/app/src/main/java/inc/anky/android/core/protocol/AnkyDuration.kt`
* `apps/android/app/src/main/java/inc/anky/android/core/protocol/AnkyReconstructor.kt`
* `apps/android/app/src/main/java/inc/anky/android/core/storage/LocalAnkyArchive.kt`
* `apps/android/app/src/main/java/inc/anky/android/core/storage/SessionIndexStore.kt`
* `apps/android/app/src/main/java/inc/anky/android/core/storage/ActiveDraftStore.kt`
* `apps/android/app/src/main/java/inc/anky/android/core/storage/SingleAnkyImporter.kt`
* `apps/android/app/src/main/java/inc/anky/android/core/storage/BackupImporter.kt`
* `apps/android/app/src/main/java/inc/anky/android/feature/reveal/RevealViewModel.kt`
* `apps/android/app/src/main/java/inc/anky/android/core/mirror/MirrorClient.kt`
* `apps/android/app/src/main/java/inc/anky/android/core/privacy/SafeLog.kt`
* `apps/android/app/src/test/java/inc/anky/android/write/WriteViewModelTest.kt`
* `apps/android/app/src/test/java/inc/anky/android/protocol/ProtocolFixtureTest.kt`
* `apps/android/app/src/test/java/inc/anky/android/storage/StorageTest.kt`
* `apps/android/app/src/test/java/inc/anky/android/privacy/SourceInvariantTest.kt`

## Diff Summary

Relevant app code changes are limited to Android protocol, storage import normalization, and writing lifecycle:

* `AnkyWriter.accept` now serializes a typed space as `SPACE`.
* `AnkyParser` now parses `SPACE` to a real space and rejects literal one-space payloads as non-canonical.
* `SingleAnkyImporter` and `BackupImporter` normalize canonical `SPACE` and legacy literal-space payloads to `SPACE`, preserving canonical iOS `.anky` files instead of converting them to literal-space payloads.
* `WriteViewModel.continueSession` restores from `artifact.text` directly and refuses restored closed writers.
* `WriteViewModel.sealSession` no longer calls `writer.closeWithTerminalSilence()`; it saves `writer.text` directly.
* `WriteViewModel.sealSession` clears active draft only for complete artifacts and preserves exact fragment text for incomplete artifacts.
* `WriteViewModel.sealSession` now uses `artifact.durationMs` and proportional progress after fragment close instead of forcing complete progress.

`git diff --name-only -- apps/ios docs protocol README.md apps/android/README.md` returned no files, so no iOS, docs, shared protocol docs, or Android README files were modified.

## Terminal 8000 Verification

PASS.

Evidence:

* Active close path: `WriteViewModel.closeAfterTerminalSilence()` calls `sealSession()`; `sealSession()` takes `val text = writer.text`, saves that text to the draft, archive, and index, and does not call `closeWithTerminalSilence()` (`WriteViewModel.kt:300-312`).
* Incomplete and complete close share the same `sealSession()` path, so both save unmutated `writer.text` (`WriteViewModel.kt:305-336`).
* `LocalAnkyArchive.save` hashes and writes the exact `ankyText.toByteArray(Charsets.UTF_8)` it receives (`LocalAnkyArchive.kt:20-26`).
* Parser compatibility remains: `AnkyParser` accepts one `TerminalSilenceMs` line, rejects duplicates, and rejects events after terminal (`AnkyParser.kt:16-25`).
* Completion and duration ignore terminal silence: `AnkyDuration.durationMs` delegates to `writingDurationMs`, and `isComplete` checks `writingDurationMs >= 480000` (`AnkyDuration.kt:11-18`).
* Tests assert no terminal emission for stale incomplete drafts and active complete saves (`WriteViewModelTest.kt:31-52`, `WriteViewModelTest.kt:121-149`) and legacy terminal parsing/completion boundaries (`ProtocolFixtureTest.kt:117-147`).

Search summary:

* `closeWithTerminalSilence` remains in `AnkyWriter`, protocol tests, `SourceInvariantTest`, and `feature/you/YouScreen.kt`. It is not called in `feature/write/WriteViewModel.kt`.
* `openContinuationText` has no matches.
* Literal terminal usage in the active write path is via `AnkyDuration.TerminalSilenceMs` for timers/countdown/state only, not byte mutation.

## SPACE Serialization Verification

PASS.

Evidence:

* Writer serialization maps `" "` to `SPACE` through `protocolGlyphText()` before appending protocol lines (`AnkyWriter.kt:19-26`, `AnkyWriter.kt:61-62`).
* Parser maps raw `SPACE` to a real space and rejects raw literal-space payloads (`AnkyParser.kt:43-50`).
* Reconstructor joins parsed glyphs, so parsed `SPACE` reconstructs as `" "` (`AnkyReconstructor.kt:3-5`).
* Archive save/hash bytes use the exact canonical text produced by the writer (`LocalAnkyArchive.kt:20-26`, `LocalAnkyArchive.kt:78-86`).
* Ask Anky sends exact saved artifact bytes: `RevealViewModel` calls `artifact.text.toByteArray(Charsets.UTF_8)` (`RevealViewModel.kt:195-197`), and `MirrorClient` posts those bytes directly as `text/plain; charset=utf-8` to `/anky` (`MirrorClient.kt:31-35`).
* Active nudge send bytes also use current `writer.text` without JSON wrapping (`WriteViewModel.kt:160-171`, `WriteViewModel.kt:403-412`).
* Importers preserve canonical iOS `SPACE` lines and normalize legacy literal-space payloads to `SPACE` (`SingleAnkyImporter.kt:121-141`, `BackupImporter.kt:261-272`).
* Tests assert writer output and parser reconstruction for `SPACE`, rejection of literal-space payloads, importer canonicalization, and active nudge bytes containing `SPACE` (`ProtocolFixtureTest.kt:50-74`, `StorageTest.kt:740-757`, `WriteViewModelTest.kt:490-514`).

Search summary:

* Space serialization matches are confined to `AnkyWriter.protocolGlyphText`, `AnkyParser` `SPACE` parsing, importer normalization, and tests.
* No newly written active-session path emits a literal-space protocol payload.

## Continuation Verification

PASS.

Evidence:

* Continuation refuses complete artifacts first (`WriteViewModel.kt:238-242`).
* Continuation restores directly from `artifact.text`, not a modified continuation string (`WriteViewModel.kt:243-246`).
* Continuation refuses terminal-marked closed artifacts by checking `restored.isClosed` (`WriteViewModel.kt:244-245`).
* `AnkyWriter.fromDraft` preserves original first epoch through parsed text and sets `lastAcceptedEpochMs` to `startEpochMs + sum(deltaMs)` (`AnkyWriter.kt:43-56`).
* Restored writer is frozen until the next glyph via `isFrozenForContinuation = true` (`WriteViewModel.kt:260`).
* First resumed glyph does not include idle gap: `resumeIfFrozen(now)` calls `writer.prepareToResume(now)` before `writer.accept(glyph, now)` (`WriteViewModel.kt:143-148`, `WriteViewModel.kt:389-393`, `AnkyWriter.kt:38-40`).
* Continued save replaces/deletes old artifact and index entry when the hash changed (`WriteViewModel.kt:315-319`).
* Continued save uses the same non-terminal `sealSession()` path and therefore does not append `8000` (`WriteViewModel.kt:305-336`).
* Tests assert non-terminal fragment continuation, original duration, zero first resumed delta, old artifact/index replacement, preserved fragment draft, and terminal-marked fragment refusal (`WriteViewModelTest.kt:206-265`).

Search summary:

* `openContinuationText` has no matches.
* `.removeSuffix` matches are unrelated filename handling and image set test logic, not writing continuation.

## Active Draft Verification

PASS.

Evidence:

* Active writing saves draft after each accepted glyph as `writer.text` (`WriteViewModel.kt:143-153`).
* `sealSession()` saves exact `writer.text` before archive save; on success, it clears only complete artifacts and saves exact fragment text for incomplete artifacts (`WriteViewModel.kt:305-325`).
* On archive save failure, it preserves the same unmutated text as draft (`WriteViewModel.kt:337-340`).
* Restored stale open drafts close immediately because `scheduleCloseForRestoredDraft()` computes remaining silence and `scheduleClose()` clamps negative delays to zero (`WriteViewModel.kt:292-297`, `WriteViewModel.kt:343-348`).
* Closed legacy drafts are not reopened as active writers; closed restored writers cause the write model to start blank (`WriteViewModel.kt:86-95`) while parser compatibility remains.
* Tests assert stale incomplete restored drafts save without terminal mutation and preserve draft, complete saves clear draft, save failure preserves non-terminal draft, and closed legacy draft remains closed/not displayed (`WriteViewModelTest.kt:31-76`, `WriteViewModelTest.kt:121-174`, `WriteViewModelTest.kt:177-203`).

## Fragment Duration/Progress Verification

PASS.

Evidence:

* Post-save state now sets `elapsedMs = artifact.durationMs` and `progress = artifact.durationMs / CompleteRitualMs`, clamped (`WriteViewModel.kt:329-335`).
* `artifact.durationMs` is computed from parsed writing duration only (`LocalAnkyArchive.kt:78-86`, `AnkyDuration.kt:11-18`).
* Complete sessions still show complete state because `artifact.durationMs >= 480000` yields `progress = 1f` and `hasReachedRitualMark` remains true (`WriteViewModel.kt:329-335`, `WriteViewModel.kt:48-49`).
* Tests assert a one-character incomplete close keeps `elapsedMs = 0` and `progress = 0f`, while a complete restored draft keeps `elapsedMs = 480000` and `progress = 1f` (`WriteViewModelTest.kt:121-149`, `WriteViewModelTest.kt:177-203`).

## Privacy/Protocol Verification

PASS.

Evidence:

* No raw writing logging was introduced. Search for logging APIs found only `SafeLog` as production logging and no new `Log.*`, `println`, `Timber`, `logger`, or `printStackTrace` calls in the touched paths.
* `SafeLog` rejects raw `.anky`-shaped multiline content, recovery phrases, private keys, signatures, prompts, and reflection content (`SafeLog.kt:6-31`), with existing tests covering these cases.
* Mirror request body remains exact `.anky` UTF-8 bytes with no JSON wrapper: `RevealViewModel` passes `artifact.text.toByteArray(Charsets.UTF_8)` and `MirrorClient` posts the same bytes to `/anky` using `bytes.toRequestBody("text/plain; charset=utf-8")` (`RevealViewModel.kt:195-197`, `MirrorClient.kt:31-35`).
* The diff does not include iOS, backend, API contract, docs, identity, credits, RevenueCat, onboarding, Play Integrity, signing, or pricing files.

Search summaries:

* `closeWithTerminalSilence`: no active write save call; remaining app-code call is in `feature/you/YouScreen.kt`, outside this P0 writing lifecycle patch.
* `openContinuationText`: no matches.
* `.removeSuffix`: only backup filename handling and image set test logic; no continuation stripping.
* literal `"8000"` / `TerminalSilenceMs`: active write usage is timer/countdown/state; parser/importer retain legacy terminal support.
* logging around writing/protocol/reflection: no unsafe logging API use introduced in touched paths; `SafeLog` forbids raw sensitive content.

## Tests And Build

Command:

```sh
git diff --check -- .
```

Result:

```text
passed with no output
```

Command:

```sh
git status --short
```

Result before this verification report was created:

```text
 M apps/android/app/src/main/java/inc/anky/android/core/protocol/AnkyParser.kt
 M apps/android/app/src/main/java/inc/anky/android/core/protocol/AnkyWriter.kt
 M apps/android/app/src/main/java/inc/anky/android/core/storage/BackupImporter.kt
 M apps/android/app/src/main/java/inc/anky/android/core/storage/SingleAnkyImporter.kt
 M apps/android/app/src/main/java/inc/anky/android/feature/write/WriteViewModel.kt
 M apps/android/app/src/test/java/inc/anky/android/privacy/SourceInvariantTest.kt
 M apps/android/app/src/test/java/inc/anky/android/protocol/ProtocolFixtureTest.kt
 M apps/android/app/src/test/java/inc/anky/android/storage/StorageTest.kt
 M apps/android/app/src/test/java/inc/anky/android/write/WriteViewModelTest.kt
?? ANDROID_BUILD_61_WRITING_PARITY_AUDIT.md
?? ANDROID_BUILD_61_WRITING_PARITY_PATCH_REPORT.md
```

Command:

```sh
git diff -- apps/android
```

Result summary:

```text
9 files changed, 104 insertions(+), 38 deletions(-)
```

The diff is limited to the Android protocol/writing/storage implementation and Android tests listed above.

Command:

```sh
cd apps/android && ./gradlew :app:testDebugUnitTest
```

Result:

```text
BUILD SUCCESSFUL in 947ms
24 actionable tasks: 24 up-to-date
```

Command:

```sh
cd apps/android && ./gradlew :app:assembleDebug
```

Result:

```text
BUILD SUCCESSFUL in 535ms
37 actionable tasks: 37 up-to-date
```

## Remaining Blockers

None.

## Remaining Non-P0 Gaps

* Device QA should still exercise the writing lifecycle on real Android hardware/emulator: fresh launch focus, background/foreground before and after 8 seconds, Reveal navigation, Map/day-detail continuation, and keyboard composing behavior.
* The audit's P1/P2 items remain out of this patch scope: explicit foreground/background lifecycle hooks, rejected-enter stats/copy parity, and haptic timing/visual refinements.

## Next Recommended Step

Android device QA for the writing lifecycle only.

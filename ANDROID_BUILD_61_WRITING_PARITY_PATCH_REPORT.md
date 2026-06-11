# Android Build 61 Writing Parity Patch Report

## Summary

Implemented the P0 Android writing lifecycle parity fixes from `ANDROID_BUILD_61_WRITING_PARITY_AUDIT.md`.

Android active writing silence close now saves the current `writer.text` bytes directly, matching the current iOS build 61 flow. Android no longer appends terminal `8000` during active silence close for incomplete fragments or complete 8-minute sessions.

Android protocol serialization now writes typed spaces as `SPACE`, parses `SPACE` back to a real space, preserves legacy terminal parsing, and normalizes imported legacy literal-space payloads to the iOS canonical `SPACE` form.

Continuation now restores from `artifact.text` directly, refuses terminal-marked closed fragments, preserves the first epoch, freezes until next input, resets the resumed timestamp before the first resumed glyph, and replaces/deletes old fragment artifact and index entries when the continued save hash changes.

Active draft behavior now matches iOS: complete saves clear the active draft, incomplete fragment saves preserve the exact unmutated fragment protocol text, and restored stale drafts close without terminal mutation.

Incomplete post-close state now keeps actual artifact duration/progress instead of forcing 8-minute completion.

## Exact Files Changed

* `apps/android/app/src/main/java/inc/anky/android/core/protocol/AnkyWriter.kt`
* `apps/android/app/src/main/java/inc/anky/android/core/protocol/AnkyParser.kt`
* `apps/android/app/src/main/java/inc/anky/android/core/storage/BackupImporter.kt`
* `apps/android/app/src/main/java/inc/anky/android/core/storage/SingleAnkyImporter.kt`
* `apps/android/app/src/main/java/inc/anky/android/feature/write/WriteViewModel.kt`
* `apps/android/app/src/test/java/inc/anky/android/privacy/SourceInvariantTest.kt`
* `apps/android/app/src/test/java/inc/anky/android/protocol/ProtocolFixtureTest.kt`
* `apps/android/app/src/test/java/inc/anky/android/storage/StorageTest.kt`
* `apps/android/app/src/test/java/inc/anky/android/write/WriteViewModelTest.kt`
* `ANDROID_BUILD_61_WRITING_PARITY_PATCH_REPORT.md`

## Required Confirmations

* Active Android silence close no longer appends terminal `8000`.
* Android spaces serialize as `SPACE`.
* Android parser/reconstructor returns a real space for `SPACE`.
* Closed terminal fragments are not continued by stripping `8000`.
* Incomplete saves preserve active draft as exact fragment protocol text.
* Complete saves clear active draft.
* Incomplete fragment progress/duration is no longer forced complete.
* Saved/hash/nudge bytes use canonical non-terminal active-flow text.

## Tests Added Or Updated

* `ProtocolFixtureTest.writerEmitsDeterministicProtocolLines`
* `ProtocolFixtureTest.parserAcceptsCanonicalSpaceAndRejectsLiteralSpacePayload`
* `ProtocolFixtureTest.completionUsesDurationWithoutTerminalSilence`
* `ProtocolFixtureTest.parserRejectsDuplicateTerminalAndEventsAfterTerminal`
* `WriteViewModelTest.restoredIncompleteDraftClosesAfterElapsedSilenceLikeIos`
* `WriteViewModelTest.completedSessionFreezesWriteStateLikeIos`
* `WriteViewModelTest.saveFailureShowsIosErrorCopyAndPreservesClosedDraft`
* `WriteViewModelTest.shortSessionSilenceClosePreservesFragmentDurationAndDraftLikeIos`
* `WriteViewModelTest.nonTerminalFragmentContinuesInWriteAndReplacesOldFragment`
* `WriteViewModelTest.terminalMarkedFragmentIsNotMadeContinuableByStrippingTerminalSilence`
* `WriteViewModelTest.ankyNudgeShowsListeningThenOneLineAndClears`
* `StorageTest.singleAnkyImporterNormalizesSpacePlaceholderAndTrailingWhitespaceLikeIos`
* `SourceInvariantTest` continuation source invariant for direct `artifact.text` restore and closed-fragment refusal

## Validation Results

Command:

```sh
cd apps/android && ./gradlew :app:testDebugUnitTest --tests inc.anky.android.protocol.ProtocolFixtureTest --tests inc.anky.android.write.WriteViewModelTest --tests inc.anky.android.storage.StorageTest --tests inc.anky.android.privacy.SourceInvariantTest
```

Result:

```text
BUILD SUCCESSFUL in 8s
24 actionable tasks: 6 executed, 18 up-to-date
```

Command:

```sh
cd apps/android && ./gradlew :app:testDebugUnitTest
```

Result:

```text
BUILD SUCCESSFUL in 2s
24 actionable tasks: 1 executed, 23 up-to-date
```

Command:

```sh
cd apps/android && ./gradlew :app:assembleDebug
```

Result:

```text
BUILD SUCCESSFUL in 2s
37 actionable tasks: 4 executed, 33 up-to-date
```

## Remaining Known Gaps

No remaining known P0 gaps from the requested writing/continuation patch scope.

# Android Build 61 Reveal Navigation After Silence Patch Report

## Root Cause

After the P0 parity patch, incomplete fragments correctly preserved their active draft and no longer appended terminal `8000`. However, after a successful silence seal, `WriteViewModel` still kept the just-sealed writer in memory and marked it as frozen for continuation.

That left the Write screen looking like an active restored fragment. More importantly, the live write refresh loop could run once more after seal and call `refreshLiveState()`, which rebuilt state without `completedHash`. That could erase the one-shot post-write Reveal navigation hash before `AnkyApp` observed it.

The visible device symptom matched this: after silence close, the screen stayed on Write, the ring dropped the 8 seconds of silence, and the session appeared frozen/restored instead of opening Reveal.

## Files Changed

* `apps/android/app/src/main/java/inc/anky/android/feature/write/WriteViewModel.kt`
* `apps/android/app/src/test/java/inc/anky/android/write/WriteViewModelTest.kt`
* `ANDROID_BUILD_61_REVEAL_NAV_AFTER_SILENCE_PATCH_REPORT.md`

## Fix Summary

`sealSession()` still saves and indexes the artifact first, and still preserves the active draft for incomplete fragments. After that, it now clears only the in-memory writer/session state with `resetInMemoryWriterAfterSeal()` before publishing the state that contains `completedHash`.

This makes the post-save Reveal hash a stable one-shot navigation signal:

* The draft remains on disk for restoration/backup parity.
* The in-memory writer is no longer treated as an active frozen continuation.
* A stale `refreshLiveState()` after seal is a no-op because `writer.isStarted` is false.
* Typing again without explicit Continue starts a new session instead of appending to the sealed fragment.

## Active Draft Preservation

Active draft preservation no longer blocks Reveal navigation because the active draft is no longer used to hydrate the in-memory writer immediately after seal. The draft is only persisted to storage; the current `WriteViewModel` resets its in-memory writer and emits `completedHash` for Reveal navigation.

Explicit continuation still goes through `continueSession(artifact)`, which restores from `artifact.text` only when the user taps Continue from Reveal/Map.

## Terminal 8000 Confirmation

Terminal `8000` was not reintroduced.

`WriteViewModel.sealSession()` still saves `val text = writer.text` directly and does not call `writer.closeWithTerminalSilence()`. Legacy terminal parser/writer support remains only in protocol compatibility code and tests.

## Fragment Duration/Progress Confirmation

Fragment duration/progress remains actual writing duration.

The sealed state still uses:

* `elapsedMs = artifact.durationMs`
* `progress = artifact.durationMs / AnkyDuration.CompleteRitualMs`
* no added 8 seconds of silence
* no forced complete progress for incomplete fragments

## Tests Added Or Updated

* `WriteViewModelTest.shortSessionSilenceCloseNavigatesToReveal`
* `WriteViewModelTest.shortSessionSilenceCloseDoesNotRemainFrozenInWrite`
* `WriteViewModelTest.incompleteSavePreservesDraftButStillEmitsRevealNavigation`
* `WriteViewModelTest.incompleteSaveDoesNotAutoContinue`
* `WriteViewModelTest.completedSessionNavigatesAndClearsDraftLikeIos`
* `WriteViewModelTest.restoredIncompleteDraftClosesAfterElapsedSilenceLikeIos`

Existing tests still cover:

* no terminal `8000` active emission
* canonical `SPACE`
* terminal-marked fragment continuation refusal
* complete save clears active draft
* incomplete save preserves active draft
* fragment progress/duration is not forced complete

## Manual Reproduction

Before fix:

1. Fresh install or clear app data.
2. Open Android app.
3. Type for around 10 seconds.
4. Stop typing.
5. Wait 8 seconds.
6. Actual: Write stayed visible/frozen and the ring dropped the silence.

Expected and fixed behavior:

1. Fresh install or clear app data.
2. Open Android app.
3. Type for around 10 seconds.
4. Stop typing.
5. Wait 8 seconds.
6. Reveal opens immediately for the incomplete fragment.

## Validation Results

Command:

```sh
cd apps/android && ./gradlew :app:testDebugUnitTest --tests inc.anky.android.write.WriteViewModelTest
```

Result:

```text
BUILD SUCCESSFUL in 1s
24 actionable tasks: 2 executed, 22 up-to-date
```

Command:

```sh
cd apps/android && ./gradlew :app:testDebugUnitTest
```

Result:

```text
BUILD SUCCESSFUL in 1s
24 actionable tasks: 1 executed, 23 up-to-date
```

Command:

```sh
cd apps/android && ./gradlew :app:assembleDebug
```

Result:

```text
BUILD SUCCESSFUL in 841ms
37 actionable tasks: 3 executed, 34 up-to-date
```

Command:

```sh
git diff --check -- .
```

Result:

```text
passed with no output
```

## Remaining Gaps

No known code-level blocker remains for the post-silence Reveal navigation bug. The next check should be on the connected Redmi: reinstall the debug APK, clear app data if needed, type for about 10 seconds, stop, wait 8 seconds, and confirm Reveal opens immediately.

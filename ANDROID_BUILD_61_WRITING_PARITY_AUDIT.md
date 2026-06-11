# Android Build 61 Writing Parity Audit

## Source Of Truth

* Source of truth: iOS build 61 current app code under `apps/ios/Anky`, not stale protocol/docs.
* Root/shared files inspected: `README.md`, `docs/PRODUCT_LAW.md`, `docs/API_CONTRACT.md`, `docs/TECHNICAL_LAW.md`, `protocol/SPEC.md`, `protocol/fixtures/*`.
* iOS files inspected: `apps/ios/README.md`, `apps/ios/Anky/AppRoot.swift`, `apps/ios/Anky/Features/Write/WriteView.swift`, `apps/ios/Anky/Features/Write/WriteViewModel.swift`, `apps/ios/Anky/Core/Protocol/AnkyWriter.swift`, `AnkyParser.swift`, `AnkyValidator.swift`, `AnkyReconstructor.swift`, `AnkyDuration.swift`, `AnkyLine.swift`, `apps/ios/Anky/Core/Storage/LocalAnkyArchive.swift`, `SessionIndexStore.swift`, `ActiveDraftStore.swift`, `apps/ios/Anky/Features/Reveal/RevealView.swift`, `RevealViewModel.swift`, `apps/ios/Anky/Features/Map/MapView.swift`, `MapViewModel.swift`, `apps/ios/Anky/Core/Mirror/MirrorEligibility.swift`, `MirrorClient.swift`, plus relevant iOS tests.
* Android files inspected: `apps/android/README.md`, `apps/android/app/src/main/java/inc/anky/android/app/AnkyApp.kt`, `AnkyNav.kt`, `AppContainer.kt`, `apps/android/app/src/main/java/inc/anky/android/feature/write/*`, `feature/reveal/*`, `feature/map/*`, `core/protocol/*`, `core/storage/*`, `core/mirror/*`, plus relevant Android unit/source invariant tests.

## Executive Summary

* Android does not currently match iOS build 61 writing lifecycle.
* Biggest P0 mismatch: Android appends terminal `8000` during active silence close before saving/hash/send. Current iOS active writing flow does not append terminal `8000`; it saves `writer.text` directly.
* Biggest continuation mismatch: iOS can continue only non-complete, non-closed fragments. Android strips terminal `8000` from a saved fragment and continues it, which allows continuation of artifacts iOS would reject. This is mostly caused by Android emitting terminal `8000` on normal save.
* Terminal `8000` conclusion: keep parser/import compatibility, but stop emitting it in Android active writing saves. Completion is based on summed writing deltas, not terminal silence.
* Additional P0 protocol/storage mismatch: iOS serializes a space as `SPACE`; Android serializes a literal space payload (`"<delta>  "`). Save/hash/send bytes therefore diverge for ordinary writing containing spaces.
* Android tests pass, but some tests currently lock the stale behavior and must be updated.

## iOS Writing Lifecycle State Machine

The active iOS writing flow starts on the Write tab. `AppRoot.onAppear` selects tab 0 and clears `revealAfterWriting` (`apps/ios/Anky/AppRoot.swift:151`). `WriteView` focuses the `ForwardOnlyTextView` when `shouldFocus` and `viewModel.canAcceptInput` are true (`WriteView.swift:52`, `WriteView.swift:54`). `prepareForWritingScene()` refreshes counts, bumps `keyboardFocusID`, and prepares haptics (`WriteViewModel.swift:354`).

Input is forward-only. `ForwardOnlyTextView.Coordinator.shouldChangeTextIn` accepts only `range.length == 0`, exactly one Swift `Character`, and not newline/carriage return (`WriteView.swift:712`). It returns `false` after calling `viewModel.accept`, so UIKit does not own the text (`WriteView.swift:730`). Autocorrection, autocapitalization, spellcheck, smart dashes, smart quotes, and smart insert/delete are disabled (`WriteView.swift:594`).

The first accepted character starts the writer with epoch milliseconds (`AnkyWriter.accept`, `AnkyWriter.swift:48`). Later accepted characters append delta milliseconds (`AnkyWriter.swift:53`). A space is serialized as `SPACE` (`AnkyWriter.swift:77`). Newlines are rejected by both UI and writer (`WriteView.swift:720`, `AnkyWriter.swift:73`).

After each accepted character, iOS updates display state, saves the active draft as `writer.text`, and schedules an 8-second silence close (`WriteViewModel.swift:127`, `WriteViewModel.swift:381`). The active draft is saved after every accepted character and on background/navigation (`WriteViewModel.swift:197`, `WriteViewModel.swift:211`). If the app foregrounds and silence already elapsed, `closeIfSilenceElapsed()` closes immediately; otherwise it reschedules the remaining delay (`WriteView.swift:165`, `WriteViewModel.swift:368`).

On silence close, current active iOS code does not call `AnkyWriter.closeWithTerminalSilence()`. `closeOrFreezeAfterSilence()` calls `sealAndSave()` (`WriteViewModel.swift:724`). `sealAndSave()` sets `protocolText = writer.text`, validates that text, and persists that exact text (`WriteViewModel.swift:464`, `WriteViewModel.swift:472`, `WriteViewModel.swift:487`). `persistSealedSession()` saves via `LocalAnkyArchive.save(protocolText)`, upserts the session index, clears active draft only for complete sessions, and saves the fragment text as active draft for incomplete sessions (`WriteViewModel.swift:732`, `WriteViewModel.swift:746`).

Files are named `<sha256>.anky`, where SHA-256 is computed over exact UTF-8 bytes (`LocalAnkyArchive.swift:49`). `SavedAnky.durationMs` and `isComplete` come from `AnkyDuration.durationMs(parsed)` and `AnkyDuration.isComplete(parsed)` (`LocalAnkyArchive.swift:318`). `AnkyDuration.durationMs` is only summed writing event deltas; terminal silence is ignored (`AnkyDuration.swift:8`, `AnkyDuration.swift:14`, `AnkyDuration.swift:18`). Reveal sends exact `Data(artifact.text.utf8)` only when the writer taps Ask Anky (`RevealViewModel.swift:314`). The mirror request uses `POST /anky` with `text/plain; charset=utf-8` (`MirrorClient.swift:132`).

Reveal opens immediately after save through `AppRoot.revealOnMap`, which sets `revealAfterWriting`, switches to Map, and `MapView.openPendingRevealIfNeeded()` pushes `.reveal(artifact)` (`AppRoot.swift:43`, `MapView.swift:109`). Reveal shows text/stats/copy/privacy. Fragments have `canContinueWriting = true` and no Ask Anky (`RevealViewModel.swift:99`, `MirrorEligibility.swift:3`). Complete sessions have Ask Anky if no local reflection exists (`RevealViewModel.swift:118`).

Continuation is explicit from incomplete Reveal or Map Reveal. `AppRoot.beginContinuingWriting(from:)` calls `writeViewModel.continueSession(from:)` and then switches to Write without animation (`AppRoot.swift:310`). iOS refuses complete artifacts (`WriteViewModel.swift:250`). It restores an `AnkyWriter(draftText: artifact.text)` and then refuses if `restored.isClosed` is true (`WriteViewModel.swift:257`, `WriteViewModel.swift:259`). For a continuable fragment, iOS preserves the original first epoch, reconstructed text, and summed elapsed duration; freezes the writer; sets `resumesOnNextInput = true`; stores `continuedArtifactToReplace`; and saves the restored text as active draft (`WriteViewModel.swift:268`, `WriteViewModel.swift:274`, `WriteViewModel.swift:279`, `WriteViewModel.swift:286`). On the next accepted character, `resumeIfFrozen(now:)` calls `writer.prepareToResume(at: now)`, so the idle gap is not appended (`WriteViewModel.swift:454`, `AnkyWriter.swift:40`). After the continued session saves, iOS deletes the old artifact and old index entry if the hash changed (`WriteViewModel.swift:734`).

## Android Writing Lifecycle State Machine

Android starts `NavHost` at `write` (`AnkyApp.kt:352`). A singleton `WriteViewModel` is created from stores in `AnkyApp` (`AnkyApp.kt:187`). `WriteScreen` uses `HiddenTextInput` and requests focus/show keyboard when input is enabled or `focusRequestId` changes (`HiddenTextInput.kt:62`).

Android input is hidden Compose `BasicTextField`. It accepts a single protocol glyph and rejects empty or multi-character changes (`HiddenTextInput.kt:41`). Autocorrect is disabled and keyboard type is `Password` (`HiddenTextInput.kt:52`). `onGlyphs` is wired from `WriteScreen` but is not called by `HiddenTextInput`; paste/multi-character input is rejected at UI level (`WriteScreen.kt:185`, `HiddenTextInput.kt:27`).

`WriteViewModel.acceptGlyphAt` starts the session, appends via `AnkyWriter.accept`, saves active draft, schedules 8-second close, and updates state (`WriteViewModel.kt:143`). However Android writer serializes the glyph directly; a space becomes a literal space payload, not `SPACE` (`AnkyWriter.kt:19`). This is a protocol/storage mismatch with iOS.

On silence close, Android calls `sealSession()`, and `sealSession()` calls `writer.closeWithTerminalSilence()` before saving (`WriteViewModel.kt:300`, `WriteViewModel.kt:305`). That appends `8000` and marks the writer closed (`AnkyWriter.kt:31`). Android saves/hash/indexes those mutated bytes (`WriteViewModel.kt:308`, `LocalAnkyArchive.kt:20`). This is the main terminal `8000` mismatch.

Android also clears active draft after every successful save, regardless of completeness (`WriteViewModel.kt:322`). iOS clears active draft only for complete sessions and persists incomplete fragments as active draft (`WriteViewModel.swift:746`). Android currently sets post-save state elapsed to `maxOf(artifact.durationMs, 480000)` even for fragments (`WriteViewModel.kt:326`), causing an incomplete fragment to appear as fully progressed in write state.

Android Reveal loads by hash, reconstructs local text, gates Ask Anky using `MirrorEligibility.canAsk(isComplete, hasReflection)`, and sends exact `artifact.text.toByteArray(UTF_8)` on Ask Anky (`RevealViewModel.kt:143`, `RevealViewModel.kt:147`, `RevealViewModel.kt:195`). Because Android saved bytes differ, the exact sent bytes differ from iOS for the same session.

Android continuation from Reveal calls `WriteViewModel.continueSession(artifact)` (`AnkyApp.kt:293`, `RevealScreen.kt:352`). It refuses complete artifacts, but for fragments it first strips a trailing terminal `8000` with `openContinuationText()` and then restores the writer (`WriteViewModel.kt:238`, `WriteViewModel.kt:244`, `WriteViewModel.kt:498`). This means Android can continue terminal-marked fragments that iOS would reject as closed. It freezes until next input, calls `prepareToResume(now)`, and deletes/replaces the old artifact and index entry if the hash changes (`WriteViewModel.kt:386`, `WriteViewModel.kt:316`).

## State-By-State Parity Table

| State | iOS behavior | Android behavior | Match? | Priority | Files/functions | Recommended fix |
| --- | --- | --- | --- | --- | --- | --- |
| 1. Fresh install/app launch chooses initial surface | `AppRoot` starts Write tab (`selectedTab = 0`) after onboarding/lock checks. | `NavHost` start destination is Write. | Mostly | P1 visual/copy | iOS `AppRoot.onAppear`; Android `AnkyApp.NavHost` | Keep; verify onboarding overlay does not alter write focus parity. |
| 2. Write opens before first character | Empty writer, ritual cursor/ring, no active `.anky`. | Empty writer, hidden text input, ring. | Mostly | P1 visual/copy | iOS `WriteView`, Android `WriteScreen` | Keep visual QA separate. |
| 3. Keyboard focus before first character | `becomeFirstResponder()` when focus id changes and input allowed. | `FocusRequester.requestFocus()` and `keyboard.show()`. | Mostly | P1 navigation | iOS `ForwardOnlyTextView`; Android `HiddenTextInput` | Add lifecycle focus test/smoke if needed. |
| 4. First accepted character starts `.anky` session | First line is epoch plus character; space serializes as `SPACE`. | First line is epoch plus raw glyph; space serializes as literal space. | No | P0 protocol/storage | iOS `AnkyWriter.accept/protocolCharacterText`; Android `AnkyWriter.accept` | Android writer/parser/import must use `SPACE` canonically like iOS. |
| 5. Later accepted characters append delta events | Delta from previous accepted epoch. | Delta from previous accepted epoch. | Yes except space bytes | P0 protocol/storage | Both `AnkyWriter.accept` | Fix space serialization. |
| 6. Backspace/delete attempt | Rejected by `range.length > 0` or empty replacement; warning haptic/copy. | Empty replacement rejected; warning haptic/copy. | Mostly | P1 visual/copy | iOS `WriteView.Coordinator`; Android `HiddenTextInput`, `ignoreBackspaceOrReplacement` | Align rejection copy only if desired. |
| 7. Selection/replacement attempt | Rejected by nonzero range; caret forced to end. | Selection toolbar disabled; mutation rejected if not single glyph. | Mostly | P1 visual/copy | iOS `ForwardOnlyTextView`; Android `HiddenTextInput` | Add UI test for replacement rejection. |
| 8. Paste attempt | Multi-character replacement rejected. | Multi-character `onValueChange` rejected; `onGlyphs` unused. | Mostly | test coverage gap | iOS `shouldChangeTextIn`; Android `HiddenTextInput` | Add Compose/UI paste rejection test. |
| 9. Newline/return attempt | Rejected; enter count increments; writer also rejects. | Newline rejected by glyph validator; no separate enter count. | Partial | P1 visual/copy | iOS `nudgeInvalidInput(.enter)`; Android `ignoreBackspaceOrReplacement` | Add separate rejected enter stats/copy if matching Reveal stats. |
| 10. Autocorrect/suggestions/smart punctuation/composing | Disabled via UITextView settings. | Autocorrect disabled, password keyboard. | Mostly | P1 visual/copy | iOS `ForwardOnlyTextView.makeUIView`; Android `HiddenTextInput` | Verify composing text cannot commit multi-glyph replacements. |
| 11. App backgrounds before first character | No writer started; reset/empty state if abandoned. | No writer started; no active draft. | Mostly | P1 navigation | iOS `persistOnBackground`; Android no explicit writer lifecycle hook | Add Android lifecycle persistence hook for parity clarity. |
| 12. App backgrounds during active writing | Saves `writer.text`; does not close immediately. | Draft already saved after each glyph; no explicit lifecycle persist. Timer may run if process stays alive. | Partial | P1 navigation | iOS `WriteView.scenePhase`; Android `WriteViewModel.scheduleClose` | Add Android foreground/background lifecycle handling mirroring iOS. |
| 13. App foregrounds before 8 sec silence | Reschedules remaining silence. | If ViewModel alive, existing coroutine remains; if process recreated, restored draft schedules remaining delay. | Partial | P1 navigation | iOS `closeIfSilenceElapsed`; Android `scheduleCloseForRestoredDraft` | Add explicit `onForeground` method to close/reschedule by last accepted ms. |
| 14. App foregrounds after 8 sec silence | Closes immediately via `closeIfSilenceElapsed`. | Restored draft schedules immediate close because negative delay clamps to 0; live background coroutine may already have closed. | Partial | P0 behavior | iOS `closeIfSilenceElapsed`; Android `scheduleCloseForRestoredDraft` | Keep immediate close but make saved bytes/draft semantics match iOS. |
| 15. 8 sec silence closes incomplete session | Saves exact `writer.text` with no terminal `8000`; saves fragment to archive; keeps active draft text. | Appends `8000`; saves fragment; clears active draft; state progress forced complete. | No | P0 protocol/storage | iOS `sealAndSave`, `persistSealedSession`; Android `sealSession` | Do not call `closeWithTerminalSilence`; keep fragment draft; do not force elapsed/progress to complete. |
| 16. 8 sec silence closes complete 8-min session | Saves exact `writer.text` with no terminal `8000`; clears draft. | Appends `8000`; saves and clears draft. | No | P0 protocol/storage | same | Stop terminal emission. |
| 17. Whether silence close mutates `.anky` bytes | No mutation beyond existing `writer.text`. | Mutates by appending terminal `8000`. | No | P0 protocol/storage | iOS `WriteViewModel.swift:472`; Android `WriteViewModel.kt:307` | Remove active-flow terminal append. |
| 18. Active draft persisted while writing | Saves after each accepted char and on background/navigation. | Saves after each accepted char and on close-to-map. | Mostly | P1 navigation | iOS `persistDraftAndScheduleSilence`; Android `acceptGlyphAt`, `abandonIfEmpty` | Add lifecycle persist hook if needed. |
| 19. Active draft cleared after save | Complete: clear. Fragment: save/preserve protocol text. | Always clear after successful save. | No | P0 behavior | iOS `persistSealedSession`; Android `sealSession` | Clear only complete, save fragment text for incomplete. |
| 20. Ended sessions saved into archive | `LocalAnkyArchive.save(protocolText)`. | `LocalAnkyArchive.save(text)` after terminal append. | No | P0 protocol/storage | archive save paths | Save unmutated protocol text. |
| 21. Saved file names/hashes | `<sha256>.anky` over exact UTF-8 bytes. | Same algorithm, wrong bytes due terminal/space. | No | P0 protocol/storage | iOS `LocalAnkyArchive.save`; Android `LocalAnkyArchive.save` | Fix bytes; hash logic can stay. |
| 22. Session index updated | Upsert summary from saved artifact; includes input stats. | Upsert summary from saved artifact; no input stats. | Partial | P1 visual/copy | iOS `SessionSummary.make`; Android `SessionSummary.make` | Add input stats only if Reveal stats parity is in scope. |
| 23. Reveal opens immediately after session end | Save callback switches Map then pushes Reveal artifact. | Completed hash navigates to Map then Reveal by hash. | Mostly | P1 navigation | iOS `revealOnMap`, `MapView.openPendingRevealIfNeeded`; Android `openPostWriteReveal` | Keep, retest after hash changes. |
| 24. Reveal state for incomplete fragments | Reconstructed text, duration, copy, continue action, no Ask Anky. | Same high-level state. | Mostly | P1 visual/copy | iOS `RevealViewModel`; Android `RevealViewModel` | Fix fragment bytes and duration/progress source. |
| 25. Reveal state for complete sessions | Copy and Ask Anky if no reflection. | Same high-level state. | Mostly | P1 visual/copy | mirror eligibility | Keep. |
| 26. Ask Anky availability incomplete vs complete | Only complete and no reflection. | Same. | Yes | none | `MirrorEligibility` both | Keep. |
| 27. Continue from incomplete Reveal | Available for incomplete; restore only if not closed. | Available for incomplete; strips terminal `8000` and restores. | No | P0 behavior | iOS `continueSession`; Android `continueSession/openContinuationText` | Remove stripping in active continuation path; after no-emission fix, ordinary fragments will be open. |
| 28. Continue from Map/day detail | Map opens Reveal; Reveal continue triggers `onTryAgain`. | Same route through Reveal. | Mostly | P1 navigation | iOS `MapView`; Android `MapScreen`, `RevealScreen` | Keep after continuation fix. |
| 29. What happens when continuing a fragment | Restored text/glyphs, frozen, wait for next char. | Same, but can be terminal-stripped first. | Partial | P0 behavior | both `continueSession` | Restore artifact text directly; reject closed legacy fragments like iOS unless product chooses parser compatibility only. |
| 30. Reuse same writer/session or new one | Creates restored writer from artifact text; preserves original epoch. | Creates restored writer from continuation text; preserves original epoch. | Partial | P0 behavior | both `AnkyWriter.from draft` | Use artifact text directly after no-terminal save. |
| 31. Continuation replaces old fragment artifact after new save | Deletes old artifact if new hash differs. | Same. | Yes | P0 behavior | iOS `persistSealedSession`; Android `sealSession` | Keep. |
| 32. Deletes old hash/index after replacement | Deletes archive and index. | Deletes archive and index. | Yes | P0 behavior | same | Keep; add test. |
| 33. Continuation after complete session | Refused; starts new blank retry path. | Refused; starts new blank retry path. | Yes | P1 navigation | iOS/Android `continueSession` | Keep. |
| 34. Restored session already exceeded silence time | Foreground/appear closes immediately using unmutated writer text. | Restored draft closes immediately but appends `8000`. | No | P0 protocol/storage | iOS `closeIfSilenceElapsed`; Android `scheduleCloseForRestoredDraft` | Close immediately without terminal append and preserve fragment draft if incomplete. |
| 35. User starts new session after deleting fragment | Reveal delete removes archive/index/reflection; next write starts blank. | Same high-level behavior. | Mostly | P1 navigation | iOS `RevealViewModel.deleteSession`; Android `RevealViewModel.deleteSession` | Retest after active draft preservation changes. |
| 36. User starts new session after completing full anky | Complete save clears draft; Write tab reset begins blank. | Complete save clears draft; retry clears completed session. | Mostly | P1 navigation | iOS `beginBlankSessionFromWriteTab`; Android `beginRetryWriting` | Keep. |
| 37. Elapsed duration computed | Sum of event deltas only; live ring uses writer elapsed, not terminal. | Protocol duration sum of deltas, but live UI uses wall time from `sessionStartMs`; post-fragment close forces 480000. | No | P0 behavior | iOS `AnkyDuration`; Android `deriveState` | After close, use artifact.durationMs; do not force complete progress for fragments. |
| 38. Word count/reconstructed text | Reconstruct events; words split whitespace/newline. | Reconstruct events; words split regex whitespace. | Mostly | P1 visual/copy | iOS `AnkyReconstructor`, `SessionSummary`; Android same | Fix space token first. |
| 39. UI indicates 8-sec countdown | Shows latest character, then countdown number/ring after 3 sec; warning haptics from 5 sec. | Shows latest glyph/countdown/ring; warning haptic at about 7 sec. | Partial | P2 polish | iOS `RitualRingsView`, `updateLiveState`; Android `RitualRings`, `WriteHaptics` | Align warning haptic threshold if desired. |
| 40. Haptics/timing/visual around silence/close | Light key haptic every accepted key, minute haptics, warning haptics after 5 sec, complete haptics. | Key haptics throttled, minute haptic, warning at 7 sec. | Partial | P2 polish | iOS `WriteViewModel.updateLiveState`; Android `WriteHaptics` | Lower priority after byte/protocol parity. |

## Terminal 8000 / Silence Close

Current iOS active flow does not append terminal `8000` when a session ends by silence. The decisive path is:

* `WriteView` calls `viewModel.closeIfSilenceElapsed()` on appear/active (`WriteView.swift:153`, `WriteView.swift:165`).
* `closeIfSilenceElapsed()` calls `closeOrFreezeAfterSilence()` when silence elapsed (`WriteViewModel.swift:368`).
* `closeOrFreezeAfterSilence()` calls `sealAndSave()` (`WriteViewModel.swift:724`).
* `sealAndSave()` sets `protocolText = writer.text` and persists that (`WriteViewModel.swift:472`, `WriteViewModel.swift:487`).
* There is no call to `writer.closeWithTerminalSilence()` in this active path.

`AnkyWriter.closeWithTerminalSilence()` still exists and appends `8000` (`AnkyWriter.swift:65`), but active iOS writing does not call it. Existing tests and docs still mention terminal lines, so this is legacy/protocol support and stale documentation, not current app save behavior.

The answer is the same for incomplete fragments and complete 8-minute sessions: neither active iOS silence close appends terminal `8000`. Completion is based on `AnkyDuration.writingDurationMs(parsed) >= 480000`, not terminal silence (`AnkyDuration.swift:18`). Terminal silence does not make fragments complete; iOS tests assert that (`ReconstructionTests.swift:37`).

iOS still parses legacy `.anky` files with terminal `8000`: `AnkyParser.parse` accepts one terminal line and rejects events after it (`AnkyParser.swift:22`). `AnkyWriter(draftText:)` marks such parsed text closed (`AnkyWriter.swift:19`). The complete-only import path can import complete terminal artifacts, while under-8-minute fragments remain parse/load compatible but are rejected by import because they are incomplete. Current active flow should not emit terminal `8000`.

Android currently appends terminal `8000` on silence close (`WriteViewModel.kt:307`, `AnkyWriter.kt:31`). This must change. Android parser can continue supporting legacy terminal files, but active write/save/hash/send bytes must not include terminal `8000`.

## Continuation Of Incomplete Sessions

iOS behavior:

* Only incomplete artifacts are considered for continuation (`WriteViewModel.swift:250`).
* iOS restores `AnkyWriter(draftText: artifact.text)` and parses the same artifact text (`WriteViewModel.swift:257`).
* If restored writer is closed because the artifact contains terminal `8000`, continuation is refused (`WriteViewModel.swift:259`).
* For valid open fragments, original first epoch is preserved by the parsed artifact.
* `elapsedMs` is restored from `writer.writingElapsedMs`; `silenceElapsedMs` resets to 0 (`WriteViewModel.swift:274`).
* `isFrozen = true` and `resumesOnNextInput = true` are set (`WriteViewModel.swift:279`).
* On next input, `writer.prepareToResume(at: now)` resets last accepted timestamp before accepting, so the idle gap is not stored (`WriteViewModel.swift:454`, `AnkyWriter.swift:40`).
* New deltas append after resume. In the first resumed character, the delta is 0 because `prepareToResume` and `accept` receive the same `now`.
* After saving the continued artifact, iOS deletes the old fragment artifact and old index entry when the hash changes (`WriteViewModel.swift:734`).
* Continuation after a complete session is refused and falls back to a blank retry (`WriteViewModel.swift:251`, `AppRoot.swift:313`).

Android behavior:

* Android refuses complete artifacts (`WriteViewModel.kt:238`).
* Android calls `artifact.text.openContinuationText()` before restore (`WriteViewModel.kt:244`).
* `openContinuationText()` removes trailing terminal `8000` (`WriteViewModel.kt:498`).
* Android then restores/freeze/resumes similarly and replaces old fragment artifact/index after save (`WriteViewModel.kt:251`, `WriteViewModel.kt:260`, `WriteViewModel.kt:386`, `WriteViewModel.kt:316`).

Mismatch:

* Android can continue terminal-marked fragments; iOS refuses them as closed.
* Android emits terminal-marked fragments in the normal active flow, then strips the marker during continuation. iOS does neither in the current active flow.
* Android clears the active draft after saving an incomplete fragment, while iOS keeps/saves the fragment text as active draft.

Required Android parity:

* Stop emitting terminal `8000` on active silence close.
* Restore continuation from `artifact.text` directly; do not strip terminal `8000` in the normal continuation path.
* Preserve parser support for legacy terminal files, but refuse continuation of closed terminal artifacts to match iOS.
* Keep original epoch, frozen resumed state, zero idle gap on first resumed character, and old artifact/index replacement.

## Explicit Answers

1. Does current iOS append terminal `8000` to `.anky` when a session ends by silence? No, not in the active build 61 writing flow. It saves `writer.text` directly.
2. Is the answer the same for incomplete fragments and complete 8-minute sessions? Yes. Neither active silence close path appends `8000`.
3. Does current iOS still parse/import legacy `.anky` files with terminal `8000`? Yes for parsing and complete-artifact import. `AnkyParser` accepts one terminal line; complete legacy terminal artifacts can be imported; incomplete terminal fragments can be parsed/loaded but are rejected by the complete-only import path.
4. Does current iOS completion depend on terminal `8000`, elapsed writing duration, or something else? Completion depends on summed accepted-event deltas via `AnkyDuration.writingDurationMs >= 480000`; terminal silence is ignored for duration/completion.
5. When continuing a fragment, iOS preserves original first epoch, resets last accepted timestamp on first resumed input, appends new deltas after resume, marks the restored writer as frozen/waiting to resume, and deletes/replaces the old fragment artifact/index after the new save. It refuses closed terminal artifacts.
6. Does Android do the same? Partially. It preserves original epoch, freezes, resets timestamp on resume, appends after resume, and replaces/deletes old artifact/index. It does not match because it strips terminal `8000` and continues closed fragments, emits terminal `8000` on save, clears fragment draft, and writes literal spaces instead of `SPACE`.
7. Exact Android changes needed: remove active-flow `closeWithTerminalSilence()` call; save/hash/send raw `writer.text`; canonicalize spaces as `SPACE` in writer/parser/import/backup compatibility; remove `openContinuationText()` stripping from continuation; reject closed terminal artifacts like iOS; preserve active draft for incomplete saves; fix post-fragment close state duration/progress; update tests that currently assert terminal emission and literal-space behavior.

## P0 Fix Plan

1. In `apps/android/app/src/main/java/inc/anky/android/feature/write/WriteViewModel.kt`, change `sealSession()` so it does not call `writer.closeWithTerminalSilence()` for active writing. Persist `writer.text` exactly.
2. In the same file, change successful save handling to clear active draft only when `artifact.isComplete`; otherwise save the unmutated fragment text, matching iOS `persistSealedSession`.
3. In the same file, change post-save state so fragment close uses `artifact.durationMs` and fragment progress remains `artifact.durationMs / 480000`, not forced to 1.
4. In `continueSession`, remove `openContinuationText()` from the normal path. Restore from `artifact.text` and reject if `AnkyWriter.fromDraft(artifact.text).isClosed`, matching iOS.
5. Update `AnkyWriter`, `AnkyParser`, `SingleAnkyImporter`, and backup importer normalization so Android canonical space bytes match iOS: write and save spaces as `SPACE`; parse `SPACE` as reconstructed space; reject or normalize literal-space legacy files according to iOS import behavior.
6. Keep `AnkyWriter.closeWithTerminalSilence()` and parser support for legacy/protocol compatibility, but ensure active writing flow does not call it.
7. Update unit tests in `WriteViewModelTest`, `ProtocolFixtureTest`, `StorageTest`, and source invariant tests that currently assert terminal emission, continuation stripping, or literal-space bytes.

## P1 Fix Plan

1. Add explicit Android lifecycle callbacks for writing foreground/background to mirror iOS `persistOnBackground` and `closeIfSilenceElapsed`.
2. Persist and display rejected backspace/enter stats if Reveal stats must match iOS exactly.
3. Align Write haptic timing: iOS warning haptics start at 5 seconds of silence; Android currently warns near 7 seconds.
4. Verify Android top bar/new-page controls against iOS paused fragment and completed artifact states.
5. Revisit stale docs after code fixes, but not in the P0 implementation pass unless explicitly requested.

## Tests To Add Or Update

* No terminal `8000` emission: active incomplete silence close saves exactly `"<epoch> h"` for a one-character fragment; complete silence close saves no terminal line.
* Legacy terminal parsing: parser accepts one terminal `8000`, rejects duplicate terminal and event after terminal, and terminal does not affect duration/completion.
* Completion calculation: `479999` is fragment, `480000` is complete, with or without legacy terminal line.
* Canonical space bytes: Android writer emits `SPACE`; parser reconstructs `SPACE` to `" "`; import normalizes literal-space legacy payloads to `SPACE` like iOS.
* Fragment continuation: continuing a non-terminal fragment preserves first epoch, freezes until next glyph, first resumed glyph has `0` delta, then saves without terminal.
* Closed fragment continuation: terminal-marked fragment is not continued, matching iOS.
* Old fragment replacement/deletion: after continued save with changed hash, old artifact file and old index entry are gone.
* Reveal navigation after close: silence close writes archive/index and opens Reveal by new hash.
* Active draft semantics: complete save clears draft; incomplete save keeps draft.
* Background/foreground silence close: restored draft older than 8 seconds closes immediately without terminal mutation.

## Validation Results

Command: `cd apps/android && ./gradlew :app:testDebugUnitTest`

Result:

```text
BUILD SUCCESSFUL in 774ms
24 actionable tasks: 24 up-to-date
```

Command: `cd apps/android && ./gradlew :app:assembleDebug`

Result:

```text
BUILD SUCCESSFUL in 436ms
37 actionable tasks: 37 up-to-date
```

These validations do not block the audit. Passing tests are not proof of parity because existing tests assert stale terminal `8000` emission and terminal-stripping continuation behavior.

## Stale Documentation

The following inspected docs conflict with current iOS build 61 active code and should not be used as implementation truth for this pass:

* `apps/ios/README.md` says 8000ms silence appends terminal `8000`.
* `apps/android/README.md` says Android appends terminal silence after 8 seconds.
* `protocol/SPEC.md` says terminal silence advances elapsed ritual time.
* `docs/API_CONTRACT.md` still shows an example request body with terminal `8000`.

Current iOS code and tests show active save does not append terminal `8000`, and duration/completion ignore terminal silence.

## Next Codex Prompt

```text
You are working in /Users/kithkui/anky on jpfraneto/anky-seed.

Implement only the P0 Android writing/continuation parity fixes from ANDROID_BUILD_61_WRITING_PARITY_AUDIT.md. Do not touch credits, RevenueCat, onboarding, mirror API behavior, backend, identity, Play Integrity, app icons/assets, release signing, or unrelated visual polish.

Source of truth is current iOS build 61 code under apps/ios/Anky.

Required P0 behavior:
1. Android active writing silence close must not append terminal 8000 to saved .anky bytes for either incomplete fragments or complete 8-minute sessions.
2. Android save/hash/send bytes must match iOS for the same writing session, including canonical SPACE serialization for spaces.
3. Android parser/import may preserve compatibility with legacy terminal 8000 files, but completion must not depend on terminal 8000.
4. Android continuation must match iOS: only incomplete, non-closed fragments continue; preserve original first epoch; freeze restored writer until next input; reset last accepted timestamp on first resumed input; append new deltas after resume; replace/delete old fragment artifact and index entry after new save.
5. Android must not strip terminal 8000 to make a closed fragment continuable.
6. Active draft semantics must match iOS: complete save clears active draft; incomplete save keeps the fragment protocol text as active draft.
7. Post-fragment close state must not force elapsed/progress to a complete 8-minute state.

Update focused tests for no terminal emission, legacy terminal parsing, completion calculation, canonical SPACE bytes, fragment continuation, closed terminal fragment continuation refusal, old fragment replacement/deletion, active draft clear/preserve behavior, Reveal navigation after close, and restored-draft silence close.

Run:
cd apps/android && ./gradlew :app:testDebugUnitTest
cd apps/android && ./gradlew :app:assembleDebug

Report exact changed files and validation results.
```

# WIRING-core.md — WS1 core protocol & storage foundation

Wiring that WS1 could not do itself because the files are outside its allowed
paths. Whoever owns these files should apply the notes below.

## 1. RecoveryPhrase checksum validation on import (WriterIdentityStore.kt)

`core/identity/RecoveryPhrase.kt` now has iOS-parity BIP39 checksum support:

- `RecoveryPhrase.parse(text)` — unchanged, non-validating (stored phrases must
  keep loading even if a pre-validation import wrote a checksum-invalid phrase).
- `RecoveryPhrase.parse(text, validatingChecksum = true)` — throws
  `IllegalArgumentException("Recovery phrase checksum is invalid.")` on a
  dictionary-valid one-word typo.
- `phrase.hasValidChecksum` — the underlying check.

Required change in `core/identity/WriterIdentityStore.kt` (mirrors iOS
`WriterIdentityStore.importIdentity` using `RecoveryPhrase(text:validatingChecksum:)`):

```kotlin
fun importRecoveryPhrase(text: String): WriterIdentity {
    val phrase = RecoveryPhrase.parse(text, validatingChecksum = true)  // was: RecoveryPhrase.parse(text)
    ...
}
```

`loadRecoveryPhrase()` must stay on the non-validating `parse(clear)`.
The import error surfaces in `feature/you/YouViewModel.importRecoveryPhrase` —
iOS shows a dedicated message for `RecoveryPhraseError.invalidChecksum`; Android
should map the `IllegalArgumentException` message similarly.

## 2. WritingInputStats plumbing (WriteViewModel + RevealScreen)

`LocalAnkyArchive.save` now accepts stats and persists a
`<hash>.input-stats.json` sidecar; `SavedAnky.inputStats` and
`SessionSummary.backspaceCount/enterCount` carry them (old index JSON decodes
as zero, missing sidecar = zero — iOS parity):

- `feature/write/WriteViewModel.kt` line ~327: change `archive.save(text)` to
  `archive.save(text, WritingInputStats(backspaceCount = ..., enterCount = ...))`
  once the writing surface counts backspaces/enters (iOS WriteViewModel keeps
  these counters and passes them at seal time).
- `feature/reveal/RevealScreen.kt` line ~371 currently hardcodes
  `backspaceCount = 0`; feed `artifact.inputStats.backspaceCount` (and iOS uses
  the stored `enterCount`, not `reconstructedText.count { it == '\n' }`).

## 3. WritingPreferencesStore consumers

New `core/storage/WritingPreferencesStore.kt` (key `anky.writingPreferences.v1`,
JSON shape identical to iOS Codable: `backspaceAllowed`, `autocorrectEnabled`,
`fontChoice` raw values quill/georgia/round/plain/typewriter, `textSize` raw
values small/medium/large/grand). Not yet constructed anywhere:

- `app/AppContainer.kt`: expose `val writingPreferencesStore = WritingPreferencesStore(context)`.
- Writing surface (WS owning WriteScreen/HiddenTextInput): honor
  `backspaceAllowed` (route backspace through
  `AnkyWriter.replaceSuffix(keepingPrefixGlyphCount = N - 1, replacementText = lastGlyph, epochMs)`
  so the protocol records the rewrite and text never goes empty) and
  `autocorrectEnabled` (IME flags), map `fontChoice`/`textSize.pointSize` to
  Compose `FontFamily`/`sp` in the UI layer (iOS mapping lives in AnkyLazure.swift:
  quill=serif, georgia=Georgia, round=rounded sans, plain=system sans,
  typewriter=typewriter serif).
- A settings surface equivalent to iOS `AnkySettingsView` is still unported.

## 4. WritingSessionEngine adoption + UnlockPolicy overlap (WS2)

New `core/protocol/WritingSessionEngine.kt` mirrors iOS
`Core/WriteBeforeScroll/WritingSessionEngine.swift` (accept / prepareToResume /
replaceSuffix / closeWithTerminalSilence / reset / silenceElapsedMs /
`snapshot()` → `WritingSessionSnapshot`). Notes:

- `WriteViewModel` still drives `AnkyWriter` directly; it can migrate to the
  engine to gain the reconstructed-text mirror and snapshots.
- `WritingSessionSnapshot.hasCompletedSentence` inlines iOS
  `UnlockPolicy.hasCompletedQuickSentence` (completed sentence OR >= 6 words)
  as companion helpers (`hasCompletedSentenceIn`, `wordCountIn`,
  `QuickPassWordThreshold`). When WS2 ports UnlockPolicy it should delegate to
  or reuse these to avoid drift.

## 5. AvatarStore consumers

New `core/storage/AvatarStore.kt` stores the onboarding selfie at
`filesDir/avatar.jpg` (`hasAvatar` / `loadData` / `save(ByteArray)` / `delete`).
Needs wiring in AppContainer + onboarding/You surfaces; Bitmap/JPEG encoding
(iOS uses `jpegData(compressionQuality: 0.85)`) belongs in the UI layer.

## 6. AnkyverseCalendar

New `core/storage/AnkyverseCalendar.kt` (96-day cycle, twelve 8-day regions,
1-based `AnkyversePosition(dayIndex, cycleDay, region, dayInRegion)`), now used
by `SessionIndexStore.groupByDay` / `groupByContinuousDays`; `SessionDay` gained
`cycleDay` and `region` (defaults 1). Map/journey UI can start consuming
`region`/`cycleDay` for region theming like iOS.
